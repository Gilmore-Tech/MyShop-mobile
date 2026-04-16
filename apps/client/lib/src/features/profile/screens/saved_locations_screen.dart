import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:shared_ui/shared_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/saved_places_provider.dart';

// ── Screen ────────────────────────────────────────────────────────────────────
// PRD 4.11 — Saved places: Home, Work, Favourites + custom.
// API: GET /v1/users/me/saved-locations  |  PUT /v1/users/me (update list)
// EDD: saved_locations normalised table with PostGIS POINT, last_used_at.

class SavedLocationsScreen extends ConsumerWidget {
  const SavedLocationsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final size = MediaQuery.sizeOf(context);
    final w    = size.width;
    final h    = size.height;

    final state = ref.watch(savedPlacesProvider);

    return Scaffold(
      backgroundColor: MyShopColors.offWhite,
      floatingActionButton: _AddFab(w: w),
      body: Column(
        children: [
          _AppBar(w: w, h: h),
          Expanded(
            child: SingleChildScrollView(
              padding: EdgeInsets.only(
                bottom: MediaQuery.paddingOf(context).bottom + h * 0.10,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(height: h * 0.014),
                  _SearchBar(w: w, h: h),
                  SizedBox(height: h * 0.019),
                  _QuickCategoriesRow(w: w, h: h),
                  SizedBox(height: h * 0.022),
                  _AddressesSection(state: state, w: w, h: h),
                  SizedBox(height: h * 0.014),
                  _FrequentRoutesCard(w: w, h: h),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── App Bar ───────────────────────────────────────────────────────────────────

class _AppBar extends StatelessWidget {
  final double w;
  final double h;
  const _AppBar({required this.w, required this.h});

  @override
  Widget build(BuildContext context) {
    final topPad = MediaQuery.paddingOf(context).top;
    return Container(
      color: MyShopColors.surfaceWhite,
      padding: EdgeInsets.only(
        top:    topPad + h * 0.010,
        bottom: h * 0.017,
        left:   w * 0.041,
        right:  w * 0.041,
      ),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => Navigator.of(context).maybePop(),
            behavior: HitTestBehavior.opaque,
            child: Padding(
              padding: EdgeInsets.only(right: w * 0.031),
              child: Icon(Icons.arrow_back,
                  size: w * 0.056, color: MyShopColors.textPrimary),
            ),
          ),
          Text(
            'Saved Places',
            style: TextStyle(
              fontSize:   w * 0.051,
              fontWeight: FontWeight.w700,
              color:      MyShopColors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Search Bar ────────────────────────────────────────────────────────────────

class _SearchBar extends StatelessWidget {
  final double w;
  final double h;
  const _SearchBar({required this.w, required this.h});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: w * 0.041),
      child: GestureDetector(
        onTap: () {
          // TODO: open Google Places autocomplete to add a new saved place
        },
        behavior: HitTestBehavior.opaque,
        child: Container(
          height: h * 0.058,
          decoration: BoxDecoration(
            color:        MyShopColors.surfaceGrey,
            borderRadius: BorderRadius.circular(w * 0.026),
          ),
          padding: EdgeInsets.symmetric(horizontal: w * 0.038),
          child: Row(
            children: [
              Icon(Icons.search_rounded,
                  size: w * 0.051, color: MyShopColors.textHint),
              SizedBox(width: w * 0.026),
              Text(
                'Search for a new place...',
                style: TextStyle(
                  fontSize: w * 0.036,
                  color:    MyShopColors.textHint,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Quick Categories ──────────────────────────────────────────────────────────

class _QuickCategoriesRow extends StatelessWidget {
  final double w;
  final double h;
  const _QuickCategoriesRow({required this.w, required this.h});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.only(left: w * 0.041),
          child: Text(
            'QUICK CATEGORIES',
            style: TextStyle(
              fontSize:      w * 0.023,
              fontWeight:    FontWeight.w900,
              color:         MyShopColors.textSecondary,
              letterSpacing: 0.7,
            ),
          ),
        ),
        SizedBox(height: h * 0.010),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: EdgeInsets.symmetric(horizontal: w * 0.041),
          child: Row(
            children: [
              ...kQuickCategories.map(
                (cat) => Padding(
                  padding: EdgeInsets.only(right: w * 0.021),
                  child: _CategoryChip(category: cat, w: w, h: h),
                ),
              ),
              _AddCategoryChip(w: w, h: h),
            ],
          ),
        ),
      ],
    );
  }
}

class _CategoryChip extends StatelessWidget {
  final QuickCategory category;
  final double        w;
  final double        h;
  const _CategoryChip(
      {required this.category, required this.w, required this.h});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {},
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: w * 0.031,
          vertical:   h * 0.009,
        ),
        decoration: BoxDecoration(
          color:        MyShopColors.surfaceWhite,
          borderRadius: BorderRadius.circular(w * 0.051),
          border:       Border.all(color: MyShopColors.divider),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(category.icon,
                size: w * 0.036, color: MyShopColors.textSecondary),
            SizedBox(width: w * 0.015),
            Text(
              category.label,
              style: TextStyle(
                fontSize:   w * 0.031,
                fontWeight: FontWeight.w500,
                color:      MyShopColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AddCategoryChip extends StatelessWidget {
  final double w;
  final double h;
  const _AddCategoryChip({required this.w, required this.h});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {},
      behavior: HitTestBehavior.opaque,
      child: Container(
        width:  w * 0.077,
        height: w * 0.077,
        decoration: BoxDecoration(
          color:        MyShopColors.surfaceWhite,
          shape:        BoxShape.circle,
          border:       Border.all(color: MyShopColors.divider),
        ),
        child: Icon(Icons.add_rounded,
            size: w * 0.041, color: MyShopColors.textSecondary),
      ),
    );
  }
}

// ── Addresses Section ─────────────────────────────────────────────────────────

class _AddressesSection extends ConsumerWidget {
  final SavedPlacesState state;
  final double           w;
  final double           h;
  const _AddressesSection(
      {required this.state, required this.w, required this.h});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Header ──
        Padding(
          padding: EdgeInsets.symmetric(horizontal: w * 0.041),
          child: Row(
            children: [
              Text(
                'MY ADDRESSES',
                style: TextStyle(
                  fontSize:      w * 0.023,
                  fontWeight:    FontWeight.w900,
                  color:         MyShopColors.textSecondary,
                  letterSpacing: 0.7,
                ),
              ),
              const Spacer(),
              Container(
                padding: EdgeInsets.symmetric(
                  horizontal: w * 0.026,
                  vertical:   h * 0.005,
                ),
                decoration: BoxDecoration(
                  color:        MyShopColors.primaryGold,
                  borderRadius: BorderRadius.circular(w * 0.041),
                ),
                child: Text(
                  state.countLabel,
                  style: TextStyle(
                    fontSize:   w * 0.023,
                    fontWeight: FontWeight.w800,
                    color:      MyShopColors.surfaceWhite,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
            ],
          ),
        ),
        SizedBox(height: h * 0.011),

        // ── Cards ──
        Container(
          color: MyShopColors.surfaceWhite,
          child: state.places.isEmpty
              ? _EmptyPlaces(w: w, h: h)
              : Column(
                  children: [
                    for (var i = 0; i < state.places.length; i++) ...[
                      _PlaceCard(
                        place:       state.places[i],
                        isDeleting:
                            state.isDeletingId &&
                            state.deletingId == state.places[i].id,
                        w: w,
                        h: h,
                      ),
                      if (i < state.places.length - 1)
                        Padding(
                          padding: EdgeInsets.only(
                            left: w * 0.041 + w * 0.185 + w * 0.031,
                          ),
                          child: const Divider(height: 1, color: MyShopColors.divider),
                        ),
                    ],
                  ],
                ),
        ),
      ],
    );
  }
}

// ── Place Card ────────────────────────────────────────────────────────────────

class _PlaceCard extends ConsumerWidget {
  final SavedPlace place;
  final bool       isDeleting;
  final double     w;
  final double     h;
  const _PlaceCard({
    required this.place,
    required this.isDeleting,
    required this.w,
    required this.h,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: w * 0.041,
        vertical:   h * 0.017,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Map thumbnail ──
          ClipRRect(
            borderRadius: BorderRadius.circular(w * 0.026),
            child: SizedBox(
              width:  w * 0.185,
              height: w * 0.185,
              child: CustomPaint(
                painter: _MapThumbnailPainter(place.thumbnailStyle),
              ),
            ),
          ),
          SizedBox(width: w * 0.031),

          // ── Info ──
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Name row + actions
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      child: Text(
                        place.name,
                        style: TextStyle(
                          fontSize:   w * 0.036,
                          fontWeight: FontWeight.w700,
                          color:      MyShopColors.textPrimary,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    // Edit
                    GestureDetector(
                      onTap: () {
                        // TODO: navigate to edit saved place screen
                      },
                      behavior: HitTestBehavior.opaque,
                      child: Padding(
                        padding: EdgeInsets.symmetric(
                            horizontal: w * 0.015,
                            vertical:   h * 0.005),
                        child: Icon(
                          Icons.edit_outlined,
                          size:  w * 0.041,
                          color: MyShopColors.textSecondary,
                        ),
                      ),
                    ),
                    // Delete
                    GestureDetector(
                      onTap: isDeleting
                          ? null
                          : () => _confirmDelete(context, ref),
                      behavior: HitTestBehavior.opaque,
                      child: Padding(
                        padding: EdgeInsets.symmetric(
                            horizontal: w * 0.010,
                            vertical:   h * 0.005),
                        child: isDeleting
                            ? SizedBox(
                                width:  w * 0.036,
                                height: w * 0.036,
                                child: const CircularProgressIndicator(
                                  strokeWidth: 1.5,
                                  color:       MyShopColors.error,
                                ),
                              )
                            : Icon(
                                Icons.delete_outline_rounded,
                                size:  w * 0.041,
                                color: MyShopColors.textSecondary,
                              ),
                      ),
                    ),
                  ],
                ),
                SizedBox(height: h * 0.006),

                // Address
                Text(
                  place.address,
                  style: TextStyle(
                    fontSize:   w * 0.031,
                    fontWeight: FontWeight.w400,
                    color:      MyShopColors.textSecondary,
                    height:     1.4,
                  ),
                  maxLines: 2,
                ),
                SizedBox(height: h * 0.008),

                // Last visited
                Row(
                  children: [
                    Icon(Icons.access_time_rounded,
                        size: w * 0.028, color: MyShopColors.textHint),
                    SizedBox(width: w * 0.010),
                    Text(
                      'Last visited: ${place.lastVisitedLabel}',
                      style: TextStyle(
                        fontSize: w * 0.026,
                        color:    MyShopColors.textHint,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _confirmDelete(BuildContext context, WidgetRef ref) {
    final w = MediaQuery.sizeOf(context).width;
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          'Remove ${place.name}?',
          style: TextStyle(
            fontSize:   w * 0.041,
            fontWeight: FontWeight.w700,
            color:      MyShopColors.textPrimary,
          ),
        ),
        content: Text(
          'This place will be removed from your saved addresses.',
          style: TextStyle(
            fontSize: w * 0.033,
            color:    MyShopColors.textSecondary,
          ),
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(w * 0.031),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text('Cancel',
                style: TextStyle(color: MyShopColors.darkSlate)),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              ref
                  .read(savedPlacesProvider.notifier)
                  .deletePlace(place.id);
            },
            child: Text(
              'Remove',
              style: TextStyle(
                color:      MyShopColors.error,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Empty state ───────────────────────────────────────────────────────────────

class _EmptyPlaces extends StatelessWidget {
  final double w;
  final double h;
  const _EmptyPlaces({required this.w, required this.h});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: h * 0.040),
      child: Center(
        child: Column(
          children: [
            Icon(Icons.location_off_outlined,
                size: w * 0.128, color: MyShopColors.textHint),
            SizedBox(height: h * 0.014),
            Text(
              'No saved places yet',
              style: TextStyle(
                fontSize:   w * 0.038,
                fontWeight: FontWeight.w600,
                color:      MyShopColors.textSecondary,
              ),
            ),
            SizedBox(height: h * 0.006),
            Text(
              'Tap + to add your first address.',
              style: TextStyle(
                fontSize: w * 0.031,
                color:    MyShopColors.textHint,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Map Thumbnail Painter ─────────────────────────────────────────────────────
// Draws a simplified map preview per ThumbnailStyle.
// Three distinct colour palettes so HOME / WORK / GYM cards look different.

class _MapThumbnailPainter extends CustomPainter {
  final ThumbnailStyle style;
  const _MapThumbnailPainter(this.style);

  @override
  void paint(Canvas canvas, Size size) {
    switch (style) {
      case ThumbnailStyle.residential:
        _drawResidential(canvas, size);
      case ThumbnailStyle.urban:
        _drawUrban(canvas, size);
      case ThumbnailStyle.commercial:
        _drawCommercial(canvas, size);
    }
  }

  // ── Residential (HOME) — soft green parks, sandy roads ──

  void _drawResidential(Canvas canvas, Size s) {
    // Background
    canvas.drawRect(
      Rect.fromLTWH(0, 0, s.width, s.height),
      Paint()..color = const Color(0xFFE8F5E9),
    );
    // Park block
    canvas.drawRect(
      Rect.fromLTWH(s.width * 0.10, s.height * 0.08,
          s.width * 0.45, s.height * 0.38),
      Paint()..color = const Color(0xFFC8E6C9),
    );
    // Roads
    final road = Paint()
      ..color       = const Color(0xFFF5F5DC)
      ..strokeWidth = s.width * 0.065
      ..strokeCap   = StrokeCap.square;
    canvas.drawLine(
      Offset(0, s.height * 0.50),
      Offset(s.width, s.height * 0.50),
      road,
    );
    canvas.drawLine(
      Offset(s.width * 0.55, 0),
      Offset(s.width * 0.55, s.height),
      road,
    );
    // Road outlines
    final outline = Paint()
      ..color       = MyShopColors.disabled
      ..strokeWidth = 0.6
      ..style       = PaintingStyle.stroke;
    for (final y in [s.height * 0.465, s.height * 0.535]) {
      canvas.drawLine(Offset(0, y), Offset(s.width, y), outline);
    }
    // Pin
    _drawPin(canvas, s, Offset(s.width * 0.55, s.height * 0.44),
        MyShopColors.error);
  }

  // ── Urban (WORK) — dense grid, grey streets ──

  void _drawUrban(Canvas canvas, Size s) {
    canvas.drawRect(
      Rect.fromLTWH(0, 0, s.width, s.height),
      Paint()..color = const Color(0xFFF5F5F5),
    );
    // Building blocks
    final block = Paint()..color = MyShopColors.divider;
    for (final rect in [
      Rect.fromLTWH(s.width * 0.05, s.height * 0.06,
          s.width * 0.35, s.height * 0.38),
      Rect.fromLTWH(s.width * 0.55, s.height * 0.06,
          s.width * 0.38, s.height * 0.22),
      Rect.fromLTWH(s.width * 0.55, s.height * 0.56,
          s.width * 0.38, s.height * 0.37),
      Rect.fromLTWH(s.width * 0.05, s.height * 0.58,
          s.width * 0.35, s.height * 0.35),
    ]) {
      canvas.drawRect(rect, block);
    }
    // Roads
    final road = Paint()
      ..color       = MyShopColors.surfaceWhite
      ..strokeWidth = s.width * 0.055;
    canvas.drawLine(
        Offset(0, s.height * 0.49), Offset(s.width, s.height * 0.49), road);
    canvas.drawLine(
        Offset(s.width * 0.46, 0), Offset(s.width * 0.46, s.height), road);
    // Pin
    _drawPin(canvas, s, Offset(s.width * 0.46, s.height * 0.43),
        MyShopColors.primaryGold);
  }

  // ── Commercial (GYM) — tighter urban blocks, darker palette ──

  void _drawCommercial(Canvas canvas, Size s) {
    canvas.drawRect(
      Rect.fromLTWH(0, 0, s.width, s.height),
      Paint()..color = const Color(0xFFECEFF1),
    );
    // Large commercial block
    canvas.drawRect(
      Rect.fromLTWH(s.width * 0.04, s.height * 0.04,
          s.width * 0.56, s.height * 0.56),
      Paint()..color = const Color(0xFFCFD8DC),
    );
    // Small blocks
    for (final rect in [
      Rect.fromLTWH(s.width * 0.66, s.height * 0.04,
          s.width * 0.28, s.height * 0.24),
      Rect.fromLTWH(s.width * 0.04, s.height * 0.66,
          s.width * 0.24, s.height * 0.28),
      Rect.fromLTWH(s.width * 0.34, s.height * 0.66,
          s.width * 0.59, s.height * 0.28),
    ]) {
      canvas.drawRect(
          rect, Paint()..color = const Color(0xFFB0BEC5));
    }
    // Roads
    final road = Paint()
      ..color       = MyShopColors.surfaceWhite
      ..strokeWidth = s.width * 0.055;
    canvas.drawLine(
        Offset(0, s.height * 0.62), Offset(s.width, s.height * 0.62), road);
    canvas.drawLine(
        Offset(s.width * 0.62, 0), Offset(s.width * 0.62, s.height), road);
    // Pin
    _drawPin(canvas, s,
        Offset(s.width * 0.30, s.height * 0.32), MyShopColors.darkSlate);
  }

  // ── Pin helper ──

  void _drawPin(Canvas canvas, Size s, Offset tip, Color color) {
    final r    = s.width * 0.095;
    final cx   = tip.dx;
    final cy   = tip.dy - r * 1.35;

    // Drop shadow
    canvas.drawCircle(
      Offset(cx + 1, cy + 2),
      r,
      Paint()..color = Colors.black26,
    );

    // Filled circle
    canvas.drawCircle(Offset(cx, cy), r, Paint()..color = color);

    // White inner dot
    canvas.drawCircle(
      Offset(cx, cy),
      r * 0.38,
      Paint()..color = MyShopColors.surfaceWhite,
    );

    // Tail
    final path = Path()
      ..moveTo(cx - r * 0.45, cy + r * 0.6)
      ..lineTo(cx,            tip.dy)
      ..lineTo(cx + r * 0.45, cy + r * 0.6)
      ..close();
    canvas.drawPath(path, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_MapThumbnailPainter old) => old.style != style;
}

// ── Frequent Routes Card ──────────────────────────────────────────────────────

class _FrequentRoutesCard extends StatelessWidget {
  final double w;
  final double h;
  const _FrequentRoutesCard({required this.w, required this.h});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: w * 0.041),
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: w * 0.041,
          vertical:   h * 0.019,
        ),
        decoration: BoxDecoration(
          color:        MyShopColors.surfaceGrey,
          borderRadius: BorderRadius.circular(w * 0.031),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Paper-plane icon
            Container(
              width:  w * 0.092,
              height: w * 0.092,
              decoration: BoxDecoration(
                color: MyShopColors.primaryGold.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Transform.rotate(
                angle: -math.pi / 6,
                child: Icon(
                  Icons.send_rounded,
                  size:  w * 0.046,
                  color: MyShopColors.primaryGold,
                ),
              ),
            ),
            SizedBox(width: w * 0.031),

            // Text
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Traveling frequent routes?',
                    style: TextStyle(
                      fontSize:   w * 0.036,
                      fontWeight: FontWeight.w700,
                      color:      MyShopColors.textPrimary,
                    ),
                  ),
                  SizedBox(height: h * 0.005),
                  Text(
                    'Add your frequent destinations to get real-time '
                    'traffic alerts and faster route planning.',
                    style: TextStyle(
                      fontSize: w * 0.031,
                      color:    MyShopColors.textSecondary,
                      height:   1.4,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Add FAB ───────────────────────────────────────────────────────────────────

class _AddFab extends StatelessWidget {
  final double w;
  const _AddFab({required this.w});

  @override
  Widget build(BuildContext context) {
    return FloatingActionButton(
      onPressed: () {
        // TODO: open add-place sheet (map pin selection via Mapbox)
      },
      backgroundColor:   MyShopColors.darkSlate,
      elevation:         4,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(w * 0.041),
      ),
      child: Icon(Icons.add_rounded, size: w * 0.064, color: MyShopColors.surfaceWhite),
    );
  }
}
