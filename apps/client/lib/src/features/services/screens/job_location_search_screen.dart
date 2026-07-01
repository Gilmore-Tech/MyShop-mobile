import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_ui/shared_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/di/providers.dart';
import '../../../core/providers/recent_locations_provider.dart';
import '../../../core/services/google_places_service.dart';
import '../providers/job_form_provider.dart';

/// Result returned when the user selects a location (either from autocomplete
/// or by dropping a pin on the map).
class JobLocationResult {
  final String address;
  final double latitude;
  final double longitude;

  const JobLocationResult({
    required this.address,
    required this.latitude,
    required this.longitude,
  });
}

/// Full-screen location search with Google Places autocomplete and a
/// "Pick on map" option. Used by the job form destination field.
class JobLocationSearchScreen extends ConsumerStatefulWidget {
  const JobLocationSearchScreen({super.key});

  @override
  ConsumerState<JobLocationSearchScreen> createState() =>
      _JobLocationSearchScreenState();
}

class _JobLocationSearchScreenState
    extends ConsumerState<JobLocationSearchScreen> {
  final _searchController = TextEditingController();
  final _focusNode = FocusNode();

  List<PlaceSuggestion> _suggestions = [];
  bool _isLoading = false;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _focusNode.requestFocus();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _onSearchChanged(String query) {
    _debounce?.cancel();
    if (query.trim().isEmpty) {
      setState(() {
        _suggestions = [];
        _isLoading = false;
      });
      return;
    }
    setState(() => _isLoading = true);
    _debounce = Timer(const Duration(milliseconds: 400), () async {
      final places = ref.read(googlePlacesServiceProvider);
      final results = await places.autocomplete(query);
      if (!mounted) return;
      setState(() {
        _suggestions = results;
        _isLoading = false;
      });
    });
  }

  Future<void> _selectSuggestion(PlaceSuggestion suggestion) async {
    setState(() => _isLoading = true);
    final places = ref.read(googlePlacesServiceProvider);
    final detail = await places.getPlaceDetail(suggestion.placeId);
    if (!mounted) return;

    if (detail != null) {
      ref.read(jobFormProvider.notifier).setLocation(
            address: detail.address,
            latitude: detail.latitude,
            longitude: detail.longitude,
          );
      // Fire-and-forget — recents persistence shouldn't block the pop.
      ref.read(recentLocationsProvider.notifier).add(
            name: suggestion.mainText,
            address: detail.address,
            lat: detail.latitude,
            lng: detail.longitude,
          );
      if (context.mounted && context.canPop()) context.pop();
    } else {
      setState(() => _isLoading = false);
    }
  }

  void _selectRecent(RecentLocation r) {
    ref.read(jobFormProvider.notifier).setLocation(
          address: r.address,
          latitude: r.lat,
          longitude: r.lng,
        );
    // Bump it to the top of the list.
    ref.read(recentLocationsProvider.notifier).add(
          name: r.name,
          address: r.address,
          lat: r.lat,
          lng: r.lng,
        );
    if (context.canPop()) context.pop();
  }

  void _openMapPicker() {
    context.push('/services/job/location/map');
  }

  Widget _buildResults(double w, double h) {
    final hasQuery = _searchController.text.trim().isNotEmpty;

    // Searching: show autocomplete results, or "no results" empty state.
    if (hasQuery) {
      if (_suggestions.isEmpty) {
        return _EmptyState(hasQuery: true, w: w, h: h);
      }
      return ListView.separated(
        padding: EdgeInsets.only(top: h * 0.007),
        itemCount: _suggestions.length,
        separatorBuilder: (_, __) => const Divider(
          height: 1,
          color: MyShopColors.divider,
        ),
        itemBuilder: (_, i) {
          final s = _suggestions[i];
          return _SuggestionTile(
            suggestion: s,
            onTap: () => _selectSuggestion(s),
            w: w,
            h: h,
          );
        },
      );
    }

    // Idle: show recents (if any) above the prompt-style empty state.
    final recents = ref.watch(recentLocationsProvider);
    if (recents.isEmpty) {
      return _EmptyState(hasQuery: false, w: w, h: h);
    }
    return ListView(
      padding: EdgeInsets.only(top: h * 0.007),
      children: [
        Padding(
          padding:
              EdgeInsets.fromLTRB(w * 0.041, h * 0.012, w * 0.041, h * 0.006),
          child: Text(
            'RECENT',
            style: TextStyle(
              color: MyShopColors.textSecondary,
              fontSize: w * 0.028,
              fontWeight: FontWeight.w900,
              letterSpacing: 1.4,
            ),
          ),
        ),
        for (var i = 0; i < recents.length; i++) ...[
          _RecentLocationTile(
            recent: recents[i],
            onTap: () => _selectRecent(recents[i]),
            w: w,
            h: h,
          ),
          if (i < recents.length - 1)
            const Divider(height: 1, color: MyShopColors.divider),
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final w = size.width;
    final h = size.height;
    final topPad = MediaQuery.paddingOf(context).top;

    return Scaffold(
      backgroundColor: MyShopColors.offWhite,
      body: Column(
        children: [
          // ── Search bar header ────────────────────────────────────────────
          Container(
            decoration: const BoxDecoration(
              color: MyShopColors.surfaceWhite,
              border: Border(bottom: BorderSide(color: MyShopColors.divider)),
            ),
            padding: EdgeInsets.only(
              top: topPad + h * 0.012,
              bottom: h * 0.014,
              left: w * 0.031,
              right: w * 0.041,
            ),
            child: Row(
              children: [
                GestureDetector(
                  onTap: () => context.pop(),
                  behavior: HitTestBehavior.opaque,
                  child: Padding(
                    padding: EdgeInsets.only(right: w * 0.021),
                    child: Icon(
                      Icons.arrow_back,
                      size: w * 0.056,
                      color: MyShopColors.textPrimary,
                    ),
                  ),
                ),
                Expanded(
                  child: Container(
                    height: h * 0.054,
                    decoration: BoxDecoration(
                      color: MyShopColors.surfaceGrey,
                      borderRadius: BorderRadius.circular(w * 0.021),
                    ),
                    child: TextField(
                      controller: _searchController,
                      focusNode: _focusNode,
                      onChanged: _onSearchChanged,
                      style: TextStyle(
                        fontSize: w * 0.038,
                        fontWeight: FontWeight.w400,
                        color: MyShopColors.textPrimary,
                      ),
                      decoration: InputDecoration(
                        hintText: 'Search for a location...',
                        hintStyle: TextStyle(
                          fontSize: w * 0.036,
                          fontWeight: FontWeight.w400,
                          color: MyShopColors.textHint,
                        ),
                        prefixIcon: Icon(
                          Icons.search_rounded,
                          size: w * 0.051,
                          color: MyShopColors.textSecondary,
                        ),
                        suffixIcon: _searchController.text.isNotEmpty
                            ? GestureDetector(
                                onTap: () {
                                  _searchController.clear();
                                  _onSearchChanged('');
                                },
                                child: Icon(
                                  Icons.close_rounded,
                                  size: w * 0.046,
                                  color: MyShopColors.textSecondary,
                                ),
                              )
                            : null,
                        border: InputBorder.none,
                        contentPadding: EdgeInsets.symmetric(
                          vertical: h * 0.015,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // ── Pick on map button ──────────────────────────────────────────
          GestureDetector(
            onTap: _openMapPicker,
            behavior: HitTestBehavior.opaque,
            child: Container(
              padding: EdgeInsets.symmetric(
                horizontal: w * 0.041,
                vertical: h * 0.017,
              ),
              decoration: const BoxDecoration(
                color: MyShopColors.surfaceWhite,
                border: Border(bottom: BorderSide(color: MyShopColors.divider)),
              ),
              child: Row(
                children: [
                  Container(
                    width: w * 0.092,
                    height: w * 0.092,
                    decoration: const BoxDecoration(
                      color: MyShopColors.primaryGoldLight,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.map_rounded,
                      size: w * 0.046,
                      color: MyShopColors.primaryGold,
                    ),
                  ),
                  SizedBox(width: w * 0.031),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Pick on map',
                          style: TextStyle(
                            fontSize: w * 0.038,
                            fontWeight: FontWeight.w600,
                            color: MyShopColors.textPrimary,
                          ),
                        ),
                        SizedBox(height: h * 0.003),
                        Text(
                          'Drop a pin to select your location',
                          style: TextStyle(
                            fontSize: w * 0.030,
                            fontWeight: FontWeight.w400,
                            color: MyShopColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    Icons.chevron_right_rounded,
                    size: w * 0.056,
                    color: MyShopColors.textSecondary,
                  ),
                ],
              ),
            ),
          ),

          // ── Results list ────────────────────────────────────────────────
          Expanded(
            child: _isLoading
                ? _LoadingIndicator(w: w, h: h)
                : _buildResults(w, h),
          ),
        ],
      ),
    );
  }
}

// ── Suggestion tile ──────────────────────────────────────────────────────────

class _SuggestionTile extends StatelessWidget {
  final PlaceSuggestion suggestion;
  final VoidCallback onTap;
  final double w;
  final double h;

  const _SuggestionTile({
    required this.suggestion,
    required this.onTap,
    required this.w,
    required this.h,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: w * 0.041,
          vertical: h * 0.015,
        ),
        child: Row(
          children: [
            Container(
              width: w * 0.092,
              height: w * 0.092,
              decoration: const BoxDecoration(
                color: MyShopColors.surfaceGrey,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.location_on_outlined,
                size: w * 0.046,
                color: MyShopColors.textSecondary,
              ),
            ),
            SizedBox(width: w * 0.031),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    suggestion.mainText,
                    style: TextStyle(
                      fontSize: w * 0.038,
                      fontWeight: FontWeight.w600,
                      color: MyShopColors.textPrimary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (suggestion.secondaryText.isNotEmpty) ...[
                    SizedBox(height: h * 0.003),
                    Text(
                      suggestion.secondaryText,
                      style: TextStyle(
                        fontSize: w * 0.030,
                        fontWeight: FontWeight.w400,
                        color: MyShopColors.textSecondary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Recent location tile ─────────────────────────────────────────────────────

class _RecentLocationTile extends StatelessWidget {
  final RecentLocation recent;
  final VoidCallback onTap;
  final double w;
  final double h;

  const _RecentLocationTile({
    required this.recent,
    required this.onTap,
    required this.w,
    required this.h,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: w * 0.041,
          vertical: h * 0.015,
        ),
        child: Row(
          children: [
            Container(
              width: w * 0.092,
              height: w * 0.092,
              decoration: const BoxDecoration(
                color: MyShopColors.surfaceGrey,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.history_rounded,
                size: w * 0.046,
                color: MyShopColors.textSecondary,
              ),
            ),
            SizedBox(width: w * 0.031),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    recent.name,
                    style: TextStyle(
                      fontSize: w * 0.038,
                      fontWeight: FontWeight.w600,
                      color: MyShopColors.textPrimary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (recent.address.isNotEmpty &&
                      recent.address != recent.name) ...[
                    SizedBox(height: h * 0.003),
                    Text(
                      recent.address,
                      style: TextStyle(
                        fontSize: w * 0.030,
                        fontWeight: FontWeight.w400,
                        color: MyShopColors.textSecondary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Loading indicator ─────────────────────────────────────────────────────────

class _LoadingIndicator extends StatelessWidget {
  final double w;
  final double h;
  const _LoadingIndicator({required this.w, required this.h});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(top: h * 0.05),
      child: Center(
        child: SizedBox(
          width: w * 0.056,
          height: w * 0.056,
          child: const CircularProgressIndicator(
            strokeWidth: 2,
            color: MyShopColors.primaryGold,
          ),
        ),
      ),
    );
  }
}

// ── Empty state ───────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  final bool hasQuery;
  final double w;
  final double h;
  const _EmptyState({
    required this.hasQuery,
    required this.w,
    required this.h,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: w * 0.082, vertical: h * 0.06),
      child: Column(
        children: [
          Icon(
            hasQuery ? Icons.search_off_rounded : Icons.place_outlined,
            size: w * 0.13,
            color: MyShopColors.textHint,
          ),
          SizedBox(height: h * 0.014),
          Text(
            hasQuery
                ? 'No locations found'
                : 'Search for a place or pick on map',
            style: TextStyle(
              fontSize: w * 0.036,
              fontWeight: FontWeight.w500,
              color: MyShopColors.textSecondary,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
