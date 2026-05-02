import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_models/shared_models.dart';

import '../../theme/myshop_colors.dart';
import '../../theme/myshop_spacing.dart';
import '../../theme/myshop_typography.dart';

/// Server-backed help search.
///
/// Caller hands us [onSearch] — a debounced, audience-scoped query
/// runner. The widget enforces:
///   - 300 ms debounce on keystrokes
///   - min 2-char gate (mirrored on the backend)
///
/// The bare bones state machine: idle → loading → results / empty / error.
class MyShopHelpSearchScreen extends StatefulWidget {
  const MyShopHelpSearchScreen({
    super.key,
    required this.onSearch,
    required this.onArticleTap,
    this.initialQuery,
  });

  final Future<List<HelpArticle>> Function(String query) onSearch;
  final void Function(HelpArticle article) onArticleTap;
  final String? initialQuery;

  @override
  State<MyShopHelpSearchScreen> createState() => _MyShopHelpSearchScreenState();
}

class _MyShopHelpSearchScreenState extends State<MyShopHelpSearchScreen> {
  final _ctrl = TextEditingController();
  Timer? _debounce;
  String _lastQuery = '';
  List<HelpArticle> _results = const [];
  bool _loading = false;
  Object? _error;

  @override
  void initState() {
    super.initState();
    if (widget.initialQuery != null && widget.initialQuery!.isNotEmpty) {
      _ctrl.text = widget.initialQuery!;
      _runSearch(widget.initialQuery!);
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _ctrl.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    final trimmed = value.trim();
    if (trimmed.length < 2) {
      setState(() {
        _results = const [];
        _loading = false;
        _error = null;
        _lastQuery = trimmed;
      });
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 300), () {
      _runSearch(trimmed);
    });
  }

  Future<void> _runSearch(String query) async {
    if (query == _lastQuery && _results.isNotEmpty) return;
    setState(() {
      _loading = true;
      _error = null;
      _lastQuery = query;
    });
    try {
      final results = await widget.onSearch(query);
      if (!mounted) return;
      // Drop late responses if the user has typed past this query.
      if (_ctrl.text.trim() != query) return;
      setState(() {
        _results = results;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: MyShopColors.offWhite,
      appBar: AppBar(
        backgroundColor: MyShopColors.surfaceWhite,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: const Icon(
            Icons.arrow_back,
            color: MyShopColors.textPrimary,
          ),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        titleSpacing: 0,
        title: Container(
          height: 40,
          padding: const EdgeInsets.symmetric(horizontal: MyShopSpacing.md),
          decoration: BoxDecoration(
            color: MyShopColors.offWhite,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: MyShopColors.divider),
          ),
          child: Row(
            children: [
              const Icon(
                Icons.search,
                size: 18,
                color: MyShopColors.textSecondary,
              ),
              const SizedBox(width: MyShopSpacing.sm),
              Expanded(
                child: TextField(
                  controller: _ctrl,
                  autofocus: true,
                  textInputAction: TextInputAction.search,
                  onChanged: _onChanged,
                  onSubmitted: (v) {
                    final trimmed = v.trim();
                    if (trimmed.length >= 2) _runSearch(trimmed);
                  },
                  style: MyShopTypography.body1,
                  decoration: InputDecoration(
                    hintText: 'Search help articles…',
                    hintStyle: MyShopTypography.body1.copyWith(
                      color: MyShopColors.textSecondary,
                      fontWeight: FontWeight.w400,
                    ),
                    border: InputBorder.none,
                    isDense: true,
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
              ),
              if (_ctrl.text.isNotEmpty)
                GestureDetector(
                  onTap: () {
                    _ctrl.clear();
                    _onChanged('');
                  },
                  child: const Icon(
                    Icons.cancel,
                    size: 18,
                    color: MyShopColors.textSecondary,
                  ),
                ),
            ],
          ),
        ),
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_lastQuery.length < 2) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(MyShopSpacing.lg),
          child: Text(
            'Type at least 2 characters to search.',
            style: MyShopTypography.body2,
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(MyShopSpacing.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.error_outline,
                size: 48,
                color: MyShopColors.error,
              ),
              SizedBox(height: MyShopSpacing.sm),
              Text(
                "Couldn't search right now. Try again.",
                style: MyShopTypography.body2,
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }
    if (_results.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(MyShopSpacing.lg),
          child: Text(
            'No articles match "$_lastQuery".',
            style: MyShopTypography.body2,
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.all(MyShopSpacing.md),
      itemCount: _results.length,
      separatorBuilder: (_, __) => const SizedBox(height: MyShopSpacing.sm),
      itemBuilder: (_, i) {
        final a = _results[i];
        return InkWell(
          onTap: () => widget.onArticleTap(a),
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.all(MyShopSpacing.md),
            decoration: BoxDecoration(
              color: MyShopColors.surfaceWhite,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: MyShopColors.divider),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  a.title,
                  style: MyShopTypography.h3.copyWith(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                if (a.summary != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    a.summary!,
                    style: MyShopTypography.body2,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
                if (a.categoryTitle != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    a.categoryTitle!.toUpperCase(),
                    style: MyShopTypography.caption.copyWith(
                      color: MyShopColors.primaryGoldDark,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.6,
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}
