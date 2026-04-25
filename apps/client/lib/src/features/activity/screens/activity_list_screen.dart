import 'package:flutter/material.dart';
import 'package:shared_ui/shared_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router.dart';
import '../providers/activity_history_provider.dart';

// ── Screen ────────────────────────────────────────────────────────────────────
// PRD § 4.6 Activity & History: unified ride + job transaction feed.
// Rides API: GET /v1/rides?page=1&limit=50
// Jobs  API: GET /v1/jobs?page=1&limit=50
// Merged client-side, grouped by date bucket (today / yesterday / last week).

class ActivityListScreen extends ConsumerStatefulWidget {
  const ActivityListScreen({super.key});

  @override
  ConsumerState<ActivityListScreen> createState() =>
      _ActivityListScreenState();
}

class _ActivityListScreenState
    extends ConsumerState<ActivityListScreen> {
  late final TextEditingController _searchCtrl;

  @override
  void initState() {
    super.initState();
    _searchCtrl = TextEditingController();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size   = MediaQuery.sizeOf(context);
    final w      = size.width;
    final h      = size.height;
    final bottom = MediaQuery.paddingOf(context).bottom;

    final state  = ref.watch(activityHistoryProvider);
    final groups = ref.watch(filteredActivityGroupsProvider);

    return Scaffold(
      backgroundColor: MyShopColors.offWhite,
      appBar: _buildAppBar(context, w),
      body: state.isLoading
          ? _LoadingSkeleton(w: w, h: h)
          : state.errorMessage != null
              ? _ErrorState(
                  message: state.errorMessage!,
                  onRetry: () =>
                      ref.read(activityHistoryProvider.notifier).reload(),
                  w: w,
                  h: h,
                )
              : CustomScrollView(
              slivers: [
                SliverToBoxAdapter(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(height: h * 0.018),

                      // ── Search bar ────────────────────────────────────
                      _SearchBar(
                        ctrl: _searchCtrl,
                        w: w,
                        h: h,
                        onChanged: (q) => ref
                            .read(activityHistoryProvider.notifier)
                            .setSearch(q),
                      ),

                      SizedBox(height: h * 0.014),

                      // ── Filter chips ──────────────────────────────────
                      _FilterChipsRow(
                        selected: state.filter,
                        onSelect: (f) => ref
                            .read(activityHistoryProvider.notifier)
                            .setFilter(f),
                        w: w,
                        h: h,
                      ),

                      SizedBox(height: h * 0.018),

                      // ── Summary card ──────────────────────────────────
                      if (state.summary != null)
                        _SummaryCard(
                          summary: state.summary!,
                          w: w,
                          h: h,
                        ),

                      SizedBox(height: h * 0.022),

                      // ── Recent Transactions heading ───────────────────
                      Padding(
                        padding: EdgeInsets.symmetric(
                            horizontal: w * 0.044),
                        child: Text(
                          'Recent Transactions',
                          style: TextStyle(
                            fontFamily: 'Raleway',
                            fontSize: w * 0.046,
                            fontWeight: FontWeight.w700,
                            color: MyShopColors.textPrimary,
                            height: 1.3,
                          ),
                        ),
                      ),

                      SizedBox(height: h * 0.014),
                    ],
                  ),
                ),

                // ── Date-grouped transaction list ─────────────────────
                if (groups.isEmpty)
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: _EmptyState(
                        filter: state.filter, w: w, h: h),
                  )
                else ...[
                  for (final group in groups) ...[
                    SliverToBoxAdapter(
                      child: _DateGroupHeader(
                          label: group.label, w: w, h: h),
                    ),
                    SliverList(
                      delegate: SliverChildBuilderDelegate(
                        (ctx, i) => _TransactionCard(
                          item: group.items[i],
                          w: w,
                          h: h,
                        ),
                        childCount: group.items.length,
                      ),
                    ),
                    SliverToBoxAdapter(
                        child: SizedBox(height: h * 0.008)),
                  ],

                  // ── Missing a trip? ──────────────────────────────────
                  SliverToBoxAdapter(
                    child: _MissingTripSection(w: w, h: h),
                  ),
                  SliverToBoxAdapter(
                    child: SizedBox(height: bottom + h * 0.032),
                  ),
                ],
              ],
            ),
    );
  }

  PreferredSizeWidget _buildAppBar(BuildContext context, double w) {
    return AppBar(
      backgroundColor: MyShopColors.surfaceWhite,
      elevation: 0,
      scrolledUnderElevation: 0,
      automaticallyImplyLeading: false,
      titleSpacing: w * 0.044,
      title: Text(
        'Activity & History',
        style: TextStyle(
          fontFamily: 'Raleway',
          fontSize: w * 0.050,
          fontWeight: FontWeight.w700,
          color: MyShopColors.textPrimary,
          height: 1.3,
        ),
      ),
      centerTitle: false,
    );
  }
}

// ── Search bar ────────────────────────────────────────────────────────────────

class _SearchBar extends StatelessWidget {
  final TextEditingController ctrl;
  final double w;
  final double h;
  final ValueChanged<String> onChanged;
  const _SearchBar({
    required this.ctrl,
    required this.w,
    required this.h,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: w * 0.044),
      child: Container(
        height: h * 0.056,
        decoration: BoxDecoration(
          color: MyShopColors.surfaceWhite,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: MyShopColors.divider, width: 1),
          boxShadow: const [
            BoxShadow(
                color: Color(0x08000000), blurRadius: 4, offset: Offset(0, 1))
          ],
        ),
        child: TextField(
          controller: ctrl,
          onChanged: onChanged,
          style: TextStyle(
            fontFamily: 'Raleway',
            fontSize: w * 0.036,
            color: MyShopColors.textPrimary,
            height: 1.3,
          ),
          decoration: InputDecoration(
            hintText: 'Search by location, job or ID...',
            hintStyle: TextStyle(
              fontFamily: 'Raleway',
              fontSize: w * 0.034,
              color: MyShopColors.textHint,
              height: 1.3,
            ),
            prefixIcon: Icon(Icons.search_rounded,
                color: MyShopColors.textHint, size: w * 0.048),
            border: InputBorder.none,
            contentPadding: EdgeInsets.symmetric(vertical: h * 0.014),
          ),
        ),
      ),
    );
  }
}

// ── Filter chips row ──────────────────────────────────────────────────────────

class _FilterChipsRow extends StatelessWidget {
  final ActivityFilter selected;
  final ValueChanged<ActivityFilter> onSelect;
  final double w;
  final double h;
  const _FilterChipsRow({
    required this.selected,
    required this.onSelect,
    required this.w,
    required this.h,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: w * 0.044),
      child: Row(
        children: ActivityFilter.values.map((f) {
          final isSelected = f == selected;
          return Padding(
            padding: EdgeInsets.only(right: w * 0.022),
            child: _FilterChip(
              filter: f,
              isSelected: isSelected,
              onTap: () => onSelect(f),
              w: w,
              h: h,
            ),
          );
        }).toList(),
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  final ActivityFilter filter;
  final bool isSelected;
  final VoidCallback onTap;
  final double w;
  final double h;
  const _FilterChip({
    required this.filter,
    required this.isSelected,
    required this.onTap,
    required this.w,
    required this.h,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeInOut,
        padding: EdgeInsets.symmetric(
            horizontal: w * 0.034, vertical: h * 0.010),
        decoration: BoxDecoration(
          color: isSelected ? MyShopColors.darkSlate : MyShopColors.surfaceWhite,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected ? MyShopColors.darkSlate : MyShopColors.divider,
            width: 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              filter.icon,
              size: w * 0.038,
              color: isSelected ? Colors.white : MyShopColors.textSecondary,
            ),
            SizedBox(width: w * 0.016),
            Text(
              filter.label,
              style: TextStyle(
                fontFamily: 'Raleway',
                fontSize: w * 0.034,
                fontWeight:
                    isSelected ? FontWeight.w700 : FontWeight.w500,
                color: isSelected ? Colors.white : MyShopColors.textPrimary,
                height: 1.3,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Summary card ──────────────────────────────────────────────────────────────

class _SummaryCard extends StatelessWidget {
  final ActivitySummary summary;
  final double w;
  final double h;
  const _SummaryCard(
      {required this.summary, required this.w, required this.h});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: w * 0.044),
      child: Container(
        padding: EdgeInsets.symmetric(
            horizontal: w * 0.044, vertical: h * 0.018),
        decoration: BoxDecoration(
          color: MyShopColors.surfaceWhite,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: MyShopColors.divider, width: 1),
          boxShadow: const [
            BoxShadow(
                color: Color(0x0A000000),
                blurRadius: 6,
                offset: Offset(0, 2))
          ],
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Left: label + amount + link
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Spent in ${summary.monthLabel}',
                    style: TextStyle(
                      fontFamily: 'Raleway',
                      fontSize: w * 0.031,
                      fontWeight: FontWeight.w400,
                      color: MyShopColors.textSecondary,
                      height: 1.4,
                    ),
                  ),
                  SizedBox(height: h * 0.005),
                  Text(
                    summary.formattedSpend,
                    style: TextStyle(
                      fontFamily: 'Raleway',
                      fontSize: w * 0.060,
                      fontWeight: FontWeight.w700,
                      color: MyShopColors.textPrimary,
                      height: 1.15,
                    ),
                  ),
                  SizedBox(height: h * 0.008),
                  Builder(
                    builder: (context) => GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => context.push(AppRoutes.activityReport),
                      child: Text(
                        '+ VIEW DETAILED REPORT',
                        style: TextStyle(
                          fontFamily: 'Raleway',
                          fontSize: w * 0.028,
                          fontWeight: FontWeight.w700,
                          color: MyShopColors.primaryGold,
                          letterSpacing: 0.4,
                          height: 1.4,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(width: w * 0.020),
            // Right: trip count badge
            _TripCountBadge(count: summary.tripCount, w: w, h: h),
          ],
        ),
      ),
    );
  }
}

class _TripCountBadge extends StatelessWidget {
  final int count;
  final double w;
  final double h;
  const _TripCountBadge(
      {required this.count, required this.w, required this.h});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
          horizontal: w * 0.030, vertical: h * 0.014),
      decoration: BoxDecoration(
        color: MyShopColors.primaryGoldLight,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
            color: MyShopColors.primaryGold.withValues(alpha: 0.30), width: 1),
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          Icon(
            Icons.donut_large_rounded,
            size: w * 0.120,
            color: MyShopColors.primaryGold.withValues(alpha: 0.18),
          ),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '$count',
                style: TextStyle(
                  fontFamily: 'Raleway',
                  fontSize: w * 0.044,
                  fontWeight: FontWeight.w700,
                  color: MyShopColors.primaryGold,
                  height: 1.2,
                ),
              ),
              Text(
                'TRIPS',
                style: TextStyle(
                  fontFamily: 'Raleway',
                  fontSize: w * 0.024,
                  fontWeight: FontWeight.w900,
                  color: MyShopColors.primaryGold,
                  letterSpacing: 1.0,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Date group header ─────────────────────────────────────────────────────────

class _DateGroupHeader extends StatelessWidget {
  final String label;
  final double w;
  final double h;
  const _DateGroupHeader(
      {required this.label, required this.w, required this.h});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
          left: w * 0.044, right: w * 0.044, bottom: h * 0.008),
      child: Text(
        label,
        style: TextStyle(
          fontFamily: 'Raleway',
          fontSize: w * 0.026,
          fontWeight: FontWeight.w900,
          color: MyShopColors.textHint,
          letterSpacing: 1.4,
          height: 1.6,
        ),
      ),
    );
  }
}

// ── Transaction card ──────────────────────────────────────────────────────────

class _TransactionCard extends StatelessWidget {
  final TransactionItem item;
  final double w;
  final double h;
  const _TransactionCard(
      {required this.item, required this.w, required this.h});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
          left: w * 0.044,
          right: w * 0.044,
          bottom: h * 0.010),
      child: Material(
        color: MyShopColors.surfaceWhite,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: () => _openDetail(context, item),
          borderRadius: BorderRadius.circular(12),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: MyShopColors.divider, width: 1),
            ),
            padding: EdgeInsets.symmetric(
                horizontal: w * 0.041, vertical: h * 0.016),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Type icon circle
                Container(
                  width: w * 0.105,
                  height: w * 0.105,
                  decoration: BoxDecoration(
                    color: item.type == TransactionType.ride
                        ? MyShopColors.primaryGold.withValues(alpha: 0.12)
                        : MyShopColors.darkSlate.withValues(alpha: 0.10),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    item.type == TransactionType.ride
                        ? Icons.directions_car_filled_rounded
                        : Icons.home_repair_service_rounded,
                    color: item.type == TransactionType.ride
                        ? MyShopColors.primaryGold
                        : MyShopColors.darkSlate,
                    size: w * 0.050,
                  ),
                ),
                SizedBox(width: w * 0.031),
                // Content
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Title + 3-dot menu
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Text(
                              item.title,
                              style: TextStyle(
                                fontFamily: 'Raleway',
                                fontSize: w * 0.037,
                                fontWeight: FontWeight.w700,
                                color: MyShopColors.textPrimary,
                                height: 1.25,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          GestureDetector(
                            onTap: () =>
                                _showItemMenu(context, item, w, h),
                            behavior: HitTestBehavior.opaque,
                            child: Padding(
                              padding:
                                  EdgeInsets.only(left: w * 0.018),
                              child: Icon(
                                Icons.more_horiz_rounded,
                                color: MyShopColors.textSecondary,
                                size: w * 0.048,
                              ),
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: h * 0.004),
                      // Location label
                      Text(
                        item.locationLabel,
                        style: TextStyle(
                          fontFamily: 'Raleway',
                          fontSize: w * 0.030,
                          fontWeight: FontWeight.w400,
                          color: MyShopColors.textHint,
                          height: 1.4,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      SizedBox(height: h * 0.006),
                      // Time + status badge on same row
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Text(
                            item.timeLabel,
                            style: TextStyle(
                              fontFamily: 'Raleway',
                              fontSize: w * 0.028,
                              fontWeight: FontWeight.w400,
                              color: MyShopColors.textHint,
                              height: 1.4,
                            ),
                          ),
                          SizedBox(width: w * 0.022),
                          _StatusBadge(status: item.status, w: w),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showItemMenu(
      BuildContext context, TransactionItem item, double w, double h) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => _ItemMenuSheet(item: item, w: w, h: h),
    );
  }

  void _openDetail(BuildContext context, TransactionItem item) {
    final path = switch (item.type) {
      TransactionType.ride => AppRoutes.activityRidePath(item.id),
      TransactionType.job  => AppRoutes.jobDetailPath(item.id),
    };
    context.push(path);
  }
}

// ── Status badge ──────────────────────────────────────────────────────────────

class _StatusBadge extends StatelessWidget {
  final TransactionStatus status;
  final double w;
  const _StatusBadge({required this.status, required this.w});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
          horizontal: w * 0.024, vertical: w * 0.011),
      decoration: BoxDecoration(
        color: status.badgeBg,
        borderRadius: BorderRadius.circular(100),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(status.badgeIcon, color: status.badgeFg, size: w * 0.034),
          SizedBox(width: w * 0.012),
          Text(
            status.label,
            style: TextStyle(
              fontFamily: 'Raleway',
              fontSize: w * 0.028,
              fontWeight: FontWeight.w700,
              color: status.badgeFg,
              height: 1.3,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Item menu bottom sheet ────────────────────────────────────────────────────

class _ItemMenuSheet extends StatelessWidget {
  final TransactionItem item;
  final double w;
  final double h;
  const _ItemMenuSheet(
      {required this.item, required this.w, required this.h});

  @override
  Widget build(BuildContext context) {
    final bottomPad = MediaQuery.paddingOf(context).bottom;
    return Container(
      decoration: const BoxDecoration(
        color: MyShopColors.surfaceWhite,
        borderRadius:
            BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: EdgeInsets.only(
          top: h * 0.014, bottom: bottomPad + h * 0.016),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Drag handle
          Center(
            child: Container(
              width: w * 0.092,
              height: h * 0.005,
              decoration: BoxDecoration(
                  color: MyShopColors.divider,
                  borderRadius: BorderRadius.circular(4)),
            ),
          ),
          SizedBox(height: h * 0.014),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: w * 0.044),
            child: Text(
              item.title,
              style: TextStyle(
                fontFamily: 'Raleway',
                fontSize: w * 0.040,
                fontWeight: FontWeight.w700,
                color: MyShopColors.textPrimary,
              ),
            ),
          ),
          SizedBox(height: h * 0.010),
          const Divider(color: MyShopColors.divider, height: 1),
          _MenuItem(
            icon: Icons.receipt_long_outlined,
            label: 'View Details',
            onTap: () {
              Navigator.of(context).pop();
              final path = switch (item.type) {
                TransactionType.ride => AppRoutes.activityRidePath(item.id),
                TransactionType.job  => AppRoutes.jobDetailPath(item.id),
              };
              context.push(path);
            },
            w: w, h: h,
          ),
          const Divider(color: MyShopColors.divider, height: 1),
          _MenuItem(
            icon: Icons.share_outlined,
            label: 'Share Receipt',
            onTap: () => Navigator.of(context).pop(),
            w: w, h: h,
          ),
          const Divider(color: MyShopColors.divider, height: 1),
          _MenuItem(
            icon: Icons.flag_outlined,
            label: 'Report an Issue',
            color: MyShopColors.error,
            onTap: () => Navigator.of(context).pop(),
            w: w, h: h,
          ),
        ],
      ),
    );
  }
}

class _MenuItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
  final double w;
  final double h;
  const _MenuItem({
    required this.icon,
    required this.label,
    this.color = MyShopColors.textPrimary,
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
            horizontal: w * 0.044, vertical: h * 0.018),
        child: Row(
          children: [
            Icon(icon, color: color, size: w * 0.050),
            SizedBox(width: w * 0.034),
            Text(
              label,
              style: TextStyle(
                fontFamily: 'Raleway',
                fontSize: w * 0.038,
                fontWeight: FontWeight.w500,
                color: color,
                height: 1.3,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Missing a trip section ────────────────────────────────────────────────────

class _MissingTripSection extends StatelessWidget {
  final double w;
  final double h;
  const _MissingTripSection({required this.w, required this.h});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(
          horizontal: w * 0.044, vertical: h * 0.018),
      child: Container(
        width: double.infinity,
        padding: EdgeInsets.symmetric(
            horizontal: w * 0.044, vertical: h * 0.024),
        decoration: BoxDecoration(
          color: MyShopColors.surfaceGrey,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          children: [
            Icon(
              Icons.description_outlined,
              color: MyShopColors.textHint,
              size: w * 0.080,
            ),
            SizedBox(height: h * 0.014),
            Text(
              'Missing a trip?',
              style: TextStyle(
                fontFamily: 'Raleway',
                fontSize: w * 0.040,
                fontWeight: FontWeight.w700,
                color: MyShopColors.textPrimary,
                height: 1.3,
              ),
            ),
            SizedBox(height: h * 0.008),
            Text(
              "If you can't find a specific transaction,\nour support team can help you recover it.",
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: 'Raleway',
                fontSize: w * 0.032,
                fontWeight: FontWeight.w400,
                color: MyShopColors.textSecondary,
                height: 1.5,
              ),
            ),
            SizedBox(height: h * 0.016),
            Builder(
              builder: (context) => GestureDetector(
                onTap: () => context.push(AppRoutes.profileSupport),
                behavior: HitTestBehavior.opaque,
                child: Padding(
                  padding: EdgeInsets.symmetric(
                      horizontal: w * 0.020, vertical: h * 0.006),
                  child: Text(
                    'Contact Support',
                    style: TextStyle(
                      fontFamily: 'Raleway',
                      fontSize: w * 0.036,
                      fontWeight: FontWeight.w700,
                      color: MyShopColors.textPrimary,
                      height: 1.3,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Empty state ───────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  final ActivityFilter filter;
  final double w;
  final double h;
  const _EmptyState(
      {required this.filter, required this.w, required this.h});

  @override
  Widget build(BuildContext context) {
    final (icon, title, subtitle) = switch (filter) {
      ActivityFilter.rides => (
          Icons.directions_car_outlined,
          'No rides yet',
          'Your completed and past rides will appear here.',
        ),
      ActivityFilter.jobs => (
          Icons.work_outline_rounded,
          'No jobs yet',
          'Your artisan service history will appear here.',
        ),
      ActivityFilter.all => (
          Icons.history_rounded,
          'No transactions yet',
          'Your rides and service jobs will appear here.',
        ),
    };

    return Center(
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: w * 0.088),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: w * 0.154, color: MyShopColors.textHint),
            SizedBox(height: h * 0.018),
            Text(
              title,
              style: TextStyle(
                fontFamily: 'Raleway',
                fontSize: w * 0.042,
                fontWeight: FontWeight.w700,
                color: MyShopColors.textPrimary,
                height: 1.3,
              ),
              textAlign: TextAlign.center,
            ),
            SizedBox(height: h * 0.009),
            Text(
              subtitle,
              style: TextStyle(
                fontFamily: 'Raleway',
                fontSize: w * 0.033,
                fontWeight: FontWeight.w400,
                color: MyShopColors.textSecondary,
                height: 1.55,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

// ── Error state ──────────────────────────────────────────────────────────

class _ErrorState extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  final double w;
  final double h;
  const _ErrorState({
    required this.message,
    required this.onRetry,
    required this.w,
    required this.h,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: w * 0.088),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.cloud_off_rounded,
                size: w * 0.154, color: MyShopColors.textHint),
            SizedBox(height: h * 0.018),
            Text(
              message,
              style: TextStyle(
                fontFamily: 'Raleway',
                fontSize: w * 0.038,
                fontWeight: FontWeight.w500,
                color: MyShopColors.textSecondary,
                height: 1.5,
              ),
              textAlign: TextAlign.center,
            ),
            SizedBox(height: h * 0.022),
            GestureDetector(
              onTap: onRetry,
              child: Container(
                padding: EdgeInsets.symmetric(
                    horizontal: w * 0.064, vertical: h * 0.014),
                decoration: BoxDecoration(
                  color: MyShopColors.darkSlate,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  'Retry',
                  style: TextStyle(
                    fontFamily: 'Raleway',
                    fontSize: w * 0.036,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Loading skeleton ──────────────────────────────────────────────────────────

class _LoadingSkeleton extends StatelessWidget {
  final double w;
  final double h;
  const _LoadingSkeleton({required this.w, required this.h});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: EdgeInsets.symmetric(
          horizontal: w * 0.044, vertical: h * 0.018),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Shimmer(w: double.infinity, h: h * 0.056),
          SizedBox(height: h * 0.014),
          Row(children: [
            _Shimmer(w: w * 0.18, h: h * 0.040),
            SizedBox(width: w * 0.022),
            _Shimmer(w: w * 0.18, h: h * 0.040),
            SizedBox(width: w * 0.022),
            _Shimmer(w: w * 0.18, h: h * 0.040),
          ]),
          SizedBox(height: h * 0.018),
          _Shimmer(w: double.infinity, h: h * 0.110),
          SizedBox(height: h * 0.022),
          _Shimmer(w: w * 0.45, h: h * 0.026),
          SizedBox(height: h * 0.014),
          ...List.generate(
            4,
            (_) => Padding(
              padding: EdgeInsets.only(bottom: h * 0.010),
              child: _Shimmer(w: double.infinity, h: h * 0.100),
            ),
          ),
        ],
      ),
    );
  }
}

class _Shimmer extends StatelessWidget {
  final double w;
  final double h;
  const _Shimmer({required this.w, required this.h});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: w,
      height: h,
      decoration: BoxDecoration(
        color: MyShopColors.divider,
        borderRadius: BorderRadius.circular(8),
      ),
    );
  }
}
