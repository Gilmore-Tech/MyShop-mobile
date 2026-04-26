import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_ui/shared_ui.dart';

import '../providers/saved_places_provider.dart';

// ── Public entry-point ────────────────────────────────────────────────────────

/// Bottom sheet to rename a saved place. Label-only — to change the
/// underlying location, the user deletes and re-adds (the current address
/// is read-only here so they can confirm the place they're renaming).
Future<void> showRenamePlaceSheet(
  BuildContext context,
  SavedPlace place,
) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.45),
    builder: (_) => _RenamePlaceSheet(place: place),
  );
}

// ── Sheet root ────────────────────────────────────────────────────────────────

class _RenamePlaceSheet extends ConsumerStatefulWidget {
  final SavedPlace place;
  const _RenamePlaceSheet({required this.place});

  @override
  ConsumerState<_RenamePlaceSheet> createState() => _RenamePlaceSheetState();
}

class _RenamePlaceSheetState extends ConsumerState<_RenamePlaceSheet> {
  late final TextEditingController _labelCtrl;
  bool   _isSaving = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    // The list stores labels uppercased for the badge — show them in
    // sentence case while editing so the user types normally.
    _labelCtrl = TextEditingController(
      text: _toSentenceCase(widget.place.name),
    );
  }

  @override
  void dispose() {
    _labelCtrl.dispose();
    super.dispose();
  }

  static String _toSentenceCase(String input) {
    if (input.isEmpty) return input;
    return input[0].toUpperCase() + input.substring(1).toLowerCase();
  }

  bool get _canSave {
    final trimmed = _labelCtrl.text.trim();
    return !_isSaving &&
        trimmed.isNotEmpty &&
        trimmed.toLowerCase() !=
            _toSentenceCase(widget.place.name).toLowerCase();
  }

  Future<void> _onSave() async {
    final newLabel = _labelCtrl.text.trim();
    if (newLabel.isEmpty) return;

    setState(() {
      _isSaving = true;
      _errorMessage = null;
    });
    final error = await ref.read(savedPlacesProvider.notifier).renamePlace(
          id:    widget.place.id,
          label: newLabel,
        );
    if (!mounted) return;
    if (error != null) {
      setState(() {
        _isSaving = false;
        _errorMessage = error;
      });
      return;
    }
    Navigator.of(context).pop();
    MyShopToast.show(context, message: 'Place renamed');
  }

  @override
  Widget build(BuildContext context) {
    final size  = MediaQuery.sizeOf(context);
    final w     = size.width;
    final h     = size.height;
    final inset = MediaQuery.viewInsetsOf(context).bottom;

    return Container(
      decoration: BoxDecoration(
        color: MyShopColors.surfaceWhite,
        borderRadius: BorderRadius.vertical(top: Radius.circular(w * 0.041)),
      ),
      padding: EdgeInsets.only(bottom: inset),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(height: h * 0.014),
            // Drag handle
            Container(
              width:  w * 0.103,
              height: h * 0.005,
              decoration: BoxDecoration(
                color:        MyShopColors.divider,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            SizedBox(height: h * 0.019),

            // Header
            Padding(
              padding: EdgeInsets.symmetric(horizontal: w * 0.041),
              child: Column(
                children: [
                  Text(
                    'Rename place',
                    style: TextStyle(
                      fontSize:   w * 0.051,
                      fontWeight: FontWeight.w700,
                      color:      MyShopColors.textPrimary,
                    ),
                  ),
                  SizedBox(height: h * 0.007),
                  Text(
                    widget.place.address,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: w * 0.031,
                      color:    MyShopColors.textSecondary,
                      height:   1.4,
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(height: h * 0.024),

            // Label input
            Padding(
              padding: EdgeInsets.symmetric(horizontal: w * 0.041),
              child: Container(
                decoration: BoxDecoration(
                  color: MyShopColors.surfaceGrey,
                  borderRadius: BorderRadius.circular(w * 0.021),
                  border: Border.all(
                    color: MyShopColors.primaryGold,
                    width: 1.5,
                  ),
                ),
                child: TextField(
                  controller: _labelCtrl,
                  autofocus:  true,
                  onChanged:  (_) => setState(() {}),
                  style: TextStyle(
                    fontSize: w * 0.036,
                    color:    MyShopColors.textPrimary,
                  ),
                  decoration: InputDecoration(
                    hintText: 'Place name',
                    hintStyle: TextStyle(
                      fontSize: w * 0.033,
                      color:    MyShopColors.textHint,
                    ),
                    prefixIcon: Icon(
                      Icons.bookmark_outline_rounded,
                      size:  w * 0.046,
                      color: MyShopColors.textSecondary,
                    ),
                    border:        InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: w * 0.020,
                      vertical:   h * 0.017,
                    ),
                  ),
                ),
              ),
            ),

            if (_errorMessage != null) ...[
              SizedBox(height: h * 0.014),
              Padding(
                padding: EdgeInsets.symmetric(horizontal: w * 0.041),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.error_outline_rounded,
                      size:  w * 0.041,
                      color: MyShopColors.error,
                    ),
                    SizedBox(width: w * 0.020),
                    Expanded(
                      child: Text(
                        _errorMessage!,
                        style: TextStyle(
                          fontSize:   w * 0.031,
                          fontWeight: FontWeight.w500,
                          color:      MyShopColors.error,
                          height:     1.4,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            SizedBox(height: h * 0.024),

            // Save
            Padding(
              padding: EdgeInsets.symmetric(horizontal: w * 0.041),
              child: SizedBox(
                width: double.infinity,
                height: h * 0.062,
                child: ElevatedButton(
                  onPressed: _canSave ? _onSave : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _canSave
                        ? MyShopColors.darkSlate
                        : MyShopColors.surfaceGrey,
                    foregroundColor: _canSave
                        ? MyShopColors.surfaceWhite
                        : MyShopColors.disabled,
                    disabledBackgroundColor: MyShopColors.surfaceGrey,
                    disabledForegroundColor: MyShopColors.disabled,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(w * 0.021),
                    ),
                  ),
                  child: _isSaving
                      ? SizedBox(
                          width:  w * 0.051,
                          height: w * 0.051,
                          child: const CircularProgressIndicator(
                            strokeWidth: 2,
                            color: MyShopColors.surfaceWhite,
                          ),
                        )
                      : Text(
                          'Save',
                          style: TextStyle(
                            fontSize:      w * 0.036,
                            fontWeight:    FontWeight.w600,
                            letterSpacing: 0.3,
                          ),
                        ),
                ),
              ),
            ),

            SizedBox(height: h * 0.014),
            GestureDetector(
              onTap: () => Navigator.of(context).pop(),
              behavior: HitTestBehavior.opaque,
              child: Padding(
                padding: EdgeInsets.symmetric(
                  vertical:   h * 0.009,
                  horizontal: w * 0.041,
                ),
                child: Text(
                  'Cancel',
                  style: TextStyle(
                    fontSize:   w * 0.033,
                    fontWeight: FontWeight.w500,
                    color:      MyShopColors.textSecondary,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
            SizedBox(height: h * 0.028),
          ],
        ),
      ),
    );
  }
}
