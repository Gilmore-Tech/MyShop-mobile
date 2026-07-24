import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_ui/shared_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/app_lifecycle_provider.dart';
import '../../services/providers/bid_list_provider.dart';
import '../../services/providers/job_detail_provider.dart';
import '../../services/widgets/bid_list_sheet.dart';
import '../providers/activity_provider.dart';

/// How often the activity list polls for updates while visible. Protects
/// against missed socket events — if the socket is healthy the poll is a
/// no-op for the user because the backend returns the same data.
const _activityPollInterval = Duration(seconds: 15);

// ── Screen ─────────────────────────────────────────────────────────────────────
// PRD 4 — Activity tab: client views all their artisan job requests, filtered
// by status. Tapping a card opens JobDetailScreen.
// API: GET /v1/jobs?status=<filter>&q=<search>&page=1&limit=20

class ActivityScreen extends ConsumerStatefulWidget {
  const ActivityScreen({super.key});

  @override
  ConsumerState<ActivityScreen> createState() => _ActivityScreenState();
}

class _ActivityScreenState extends ConsumerState<ActivityScreen> {
  final _searchController = TextEditingController();
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    _poll = Timer.periodic(_activityPollInterval, (_) {
      if (!mounted || !ref.read(appForegroundedProvider)) return;
      ref.read(activityNotifierProvider.notifier).silentReload();
    });
  }

  @override
  void dispose() {
    _poll?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final w = size.width;
    final h = size.height;

    final activityState = ref.watch(activityNotifierProvider);
    final jobs = ref.watch(filteredJobsProvider);

    return Scaffold(
      backgroundColor: MyShopColors.offWhite,
      body: Column(
        children: [
          _TopSection(
            w: w,
            h: h,
            activeFilter: activityState.activeFilter,
            searchController: _searchController,
            onFilterChanged: (f) =>
                ref.read(activityNotifierProvider.notifier).setFilter(f),
            onSearchChanged: (q) =>
                ref.read(activityNotifierProvider.notifier).setSearch(q),
          ),
          Expanded(
            child: RefreshIndicator(
              color: MyShopColors.primaryGold,
              onRefresh: () =>
                  ref.read(activityNotifierProvider.notifier).reload(),
              child: jobs.isEmpty
                  ? _EmptyScrollable(
                      child: _EmptyState(
                        filter: activityState.activeFilter,
                        w: w,
                        h: h,
                      ),
                    )
                  : _JobList(jobs: jobs, w: w, h: h),
            ),
          ),
          _BottomNav(w: w, h: h),
        ],
      ),
    );
  }
}

// ── Top section: header + tabs + search + count ────────────────────────────────

class _TopSection extends StatelessWidget {
  final double w;
  final double h;
  final RequestFilter activeFilter;
  final TextEditingController searchController;
  final void Function(RequestFilter) onFilterChanged;
  final void Function(String) onSearchChanged;

  const _TopSection({
    required this.w,
    required this.h,
    required this.activeFilter,
    required this.searchController,
    required this.onFilterChanged,
    required this.onSearchChanged,
  });

  @override
  Widget build(BuildContext context) {
    final topPad = MediaQuery.paddingOf(context).top;
    return Container(
      color: MyShopColors.surfaceWhite,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(height: topPad + h * 0.019),
          // ── Title ──
          Padding(
            padding: EdgeInsets.symmetric(horizontal: w * 0.041),
            child: Text(
              'Activities',
              style: TextStyle(
                fontSize: w * 0.064, // ~25dp
                fontWeight: FontWeight.w700,
                color: MyShopColors.textPrimary,
                height: 1.2,
              ),
            ),
          ),
          SizedBox(height: h * 0.017),
          // ── Filter tab bar ──
          _FilterTabBar(
            activeFilter: activeFilter,
            onFilterChanged: onFilterChanged,
            w: w,
            h: h,
          ),
          const Divider(height: 1, thickness: 1, color: MyShopColors.divider),
          SizedBox(height: h * 0.014),
          // ── Search row ──
          _SearchRow(
            controller: searchController,
            onChanged: onSearchChanged,
            w: w,
            h: h,
          ),
          SizedBox(height: h * 0.012),
        ],
      ),
    );
  }
}

// ── Scrollable filter tab bar ──────────────────────────────────────────────────

class _FilterTabBar extends StatelessWidget {
  final RequestFilter activeFilter;
  final void Function(RequestFilter) onFilterChanged;
  final double w;
  final double h;

  const _FilterTabBar({
    required this.activeFilter,
    required this.onFilterChanged,
    required this.w,
    required this.h,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: h * 0.047, // ~40dp
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.symmetric(horizontal: w * 0.041),
        children: RequestFilter.values.map((f) {
          final isActive = f == activeFilter;
          return GestureDetector(
            onTap: () => onFilterChanged(f),
            behavior: HitTestBehavior.opaque,
            child: Padding(
              padding: EdgeInsets.only(right: w * 0.062),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Text(
                    f.label,
                    style: TextStyle(
                      fontSize: w * 0.036,
                      fontWeight: isActive ? FontWeight.w700 : FontWeight.w400,
                      color: isActive
                          ? MyShopColors.textPrimary
                          : MyShopColors.textSecondary,
                    ),
                  ),
                  SizedBox(height: h * 0.007),
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    height: 2.5,
                    width: isActive ? w * 0.077 : 0,
                    decoration: BoxDecoration(
                      color: MyShopColors.primaryGold,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ],
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

// ── Search row ─────────────────────────────────────────────────────────────────

class _SearchRow extends StatelessWidget {
  final TextEditingController controller;
  final void Function(String) onChanged;
  final double w;
  final double h;

  const _SearchRow({
    required this.controller,
    required this.onChanged,
    required this.w,
    required this.h,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: w * 0.041),
      child: Row(
        children: [
          Expanded(
            child: Container(
              height: h * 0.054, // ~46dp
              decoration: BoxDecoration(
                color: MyShopColors.surfaceGrey,
                borderRadius: BorderRadius.circular(w * 0.021),
              ),
              child: TextField(
                controller: controller,
                onChanged: onChanged,
                style: TextStyle(
                  fontSize: w * 0.036,
                  color: MyShopColors.textPrimary,
                ),
                decoration: InputDecoration(
                  hintText: 'Search requests...',
                  hintStyle: TextStyle(
                    fontSize: w * 0.036,
                    fontWeight: FontWeight.w400,
                    color: MyShopColors.textHint,
                  ),
                  prefixIcon: Icon(
                    Icons.search_rounded,
                    size: w * 0.051,
                    color: MyShopColors.textHint,
                  ),
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.symmetric(
                    vertical: h * 0.014,
                  ),
                ),
              ),
            ),
          ),
          SizedBox(width: w * 0.026),
          // Filter / sort icon button
          Container(
            width: h * 0.054,
            height: h * 0.054,
            decoration: BoxDecoration(
              color: MyShopColors.surfaceGrey,
              borderRadius: BorderRadius.circular(w * 0.021),
            ),
            child: Icon(
              Icons.tune_rounded,
              size: w * 0.051,
              color: MyShopColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Scrollable wrapper for empty state so pull-to-refresh still works ────────

class _EmptyScrollable extends StatelessWidget {
  const _EmptyScrollable({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (_, constraints) => SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: child,
        ),
      ),
    );
  }
}

// ── Job list ────────────────────────────────────────────────────────────────────

class _JobList extends StatelessWidget {
  final List<JobListItem> jobs;
  final double w;
  final double h;

  const _JobList({required this.jobs, required this.w, required this.h});

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: EdgeInsets.only(
        left: w * 0.041,
        right: w * 0.041,
        top: h * 0.005,
        bottom: h * 0.014,
      ),
      itemCount: jobs.length + 1, // +1 for the count header
      separatorBuilder: (_, i) =>
          i == 0 ? const SizedBox.shrink() : SizedBox(height: h * 0.005),
      itemBuilder: (context, i) {
        if (i == 0) {
          return Padding(
            padding: EdgeInsets.only(
              top: h * 0.014,
              bottom: h * 0.010,
            ),
            child: Text(
              'Showing ${jobs.length} request${jobs.length == 1 ? '' : 's'}',
              style: TextStyle(
                fontSize: w * 0.033,
                fontWeight: FontWeight.w400,
                color: MyShopColors.textSecondary,
              ),
            ),
          );
        }
        final job = jobs[i - 1];
        return _JobCard(job: job, w: w, h: h);
      },
    );
  }
}

// ── Individual job card ────────────────────────────────────────────────────────

class _JobCard extends StatelessWidget {
  final JobListItem job;
  final double w;
  final double h;

  const _JobCard({required this.job, required this.w, required this.h});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: EdgeInsets.only(bottom: h * 0.007),
      decoration: BoxDecoration(
        color: MyShopColors.surfaceWhite,
        borderRadius: BorderRadius.circular(w * 0.031),
        border: Border.all(color: MyShopColors.divider),
      ),
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: w * 0.041,
          vertical: h * 0.017,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Title row ──
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Category icon circle
                Container(
                  width: w * 0.103,
                  height: w * 0.103,
                  decoration: const BoxDecoration(
                    color: MyShopColors.surfaceGrey,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    job.categoryIcon,
                    size: w * 0.051,
                    color: MyShopColors.textSecondary,
                  ),
                ),
                SizedBox(width: w * 0.031),
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
                              job.title,
                              style: TextStyle(
                                fontSize: w * 0.041,
                                fontWeight: FontWeight.w700,
                                color: MyShopColors.textPrimary,
                                height: 1.25,
                              ),
                            ),
                          ),
                          GestureDetector(
                            onTap: () => _showCardMenu(context, job),
                            behavior: HitTestBehavior.opaque,
                            child: Padding(
                              padding: EdgeInsets.only(left: w * 0.021),
                              child: Icon(
                                Icons.more_vert_rounded,
                                size: w * 0.051,
                                color: MyShopColors.textSecondary,
                              ),
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: h * 0.005),
                      // Location + posted time
                      Row(
                        children: [
                          Icon(
                            Icons.location_on_outlined,
                            size: w * 0.031,
                            color: MyShopColors.textHint,
                          ),
                          SizedBox(width: w * 0.010),
                          Expanded(
                            child: Text(
                              '${job.location} · ${job.postedAt}',
                              style: TextStyle(
                                fontSize: w * 0.031,
                                fontWeight: FontWeight.w400,
                                color: MyShopColors.textSecondary,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),

            SizedBox(height: h * 0.014),

            // ── Status badge row ──
            Row(
              children: [
                _StatusBadge(status: job.status, w: w),
              ],
            ),

            // ── Active bids row (only for ongoing jobs) ──
            if (job.showBidRow) ...[
              SizedBox(height: h * 0.012),
              const Divider(height: 1, color: MyShopColors.divider),
              SizedBox(height: h * 0.012),
              _BidRow(job: job, w: w, h: h),
            ],
          ],
        ),
      ),
    );
  }

  void _showCardMenu(BuildContext context, JobListItem job) {
    final w = MediaQuery.sizeOf(context).width;
    final h = MediaQuery.sizeOf(context).height;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => _CardMenuSheet(job: job, w: w, h: h),
    );
  }
}

// ── Status badge ───────────────────────────────────────────────────────────────

class _StatusBadge extends StatelessWidget {
  final JobStatus status;
  final double w;

  const _StatusBadge({required this.status, required this.w});

  @override
  Widget build(BuildContext context) {
    final (bg, fg) = _colors(status);
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: w * 0.031,
        vertical: w * 0.013,
      ),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(w * 0.051),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: w * 0.018,
            height: w * 0.018,
            decoration: BoxDecoration(color: fg, shape: BoxShape.circle),
          ),
          SizedBox(width: w * 0.015),
          Text(
            status.displayLabel.toUpperCase(),
            style: TextStyle(
              fontSize: w * 0.028,
              fontWeight: FontWeight.w700,
              color: fg,
              letterSpacing: 0.4,
            ),
          ),
        ],
      ),
    );
  }

  (Color bg, Color fg) _colors(JobStatus s) => switch (s) {
        JobStatus.completed => (
            MyShopColors.successLight,
            MyShopColors.success
          ),
        JobStatus.cancelled => (MyShopColors.errorLight, MyShopColors.error),
        JobStatus.inProgress ||
        JobStatus.open ||
        JobStatus.artisanMarkedComplete ||
        JobStatus.enRoute ||
        JobStatus.arrived ||
        JobStatus.confirmed =>
          (MyShopColors.successLight, MyShopColors.success),
        _ => (MyShopColors.warningLight, MyShopColors.warning),
      };
}

// ── Active bids row inside card ────────────────────────────────────────────────

class _BidRow extends StatelessWidget {
  final JobListItem job;
  final double w;
  final double h;

  const _BidRow({
    required this.job,
    required this.w,
    required this.h,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(
          Icons.people_alt_outlined,
          size: w * 0.041,
          color: MyShopColors.primaryGold,
        ),
        SizedBox(width: w * 0.015),
        Text(
          '${job.activeBidCount} Bidders active',
          style: TextStyle(
            fontSize: w * 0.033,
            fontWeight: FontWeight.w500,
            color: MyShopColors.textSecondary,
          ),
        ),
        const Spacer(),
        GestureDetector(
          onTap: () => showBidListSheet(
            context,
            job: ActiveJobSummary(
              jobId: job.id,
              title: job.title,
              budgetPesewas: job.budgetPesewas,
            ),
          ),
          behavior: HitTestBehavior.opaque,
          child: Text(
            'View Bids',
            style: TextStyle(
              fontSize: w * 0.033,
              fontWeight: FontWeight.w700,
              color: MyShopColors.primaryGold,
            ),
          ),
        ),
      ],
    );
  }
}

// ── Card 3-dot menu sheet ──────────────────────────────────────────────────────

class _CardMenuSheet extends StatelessWidget {
  final JobListItem job;
  final double w;
  final double h;

  const _CardMenuSheet({
    required this.job,
    required this.w,
    required this.h,
  });

  @override
  Widget build(BuildContext context) {
    final bottomPad = MediaQuery.paddingOf(context).bottom;
    final isActive =
        RequestFilter.active.statuses?.contains(job.status) ?? false;

    return Container(
      decoration: BoxDecoration(
        color: MyShopColors.surfaceWhite,
        borderRadius: BorderRadius.vertical(top: Radius.circular(w * 0.041)),
      ),
      padding: EdgeInsets.only(
        top: h * 0.014,
        bottom: bottomPad + h * 0.019,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Drag handle
          Container(
            width: w * 0.103,
            height: h * 0.005,
            decoration: BoxDecoration(
              color: MyShopColors.divider,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          SizedBox(height: h * 0.017),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: w * 0.041),
            child: Text(
              job.title,
              style: TextStyle(
                fontSize: w * 0.038,
                fontWeight: FontWeight.w700,
                color: MyShopColors.textPrimary,
              ),
            ),
          ),
          SizedBox(height: h * 0.010),
          const Divider(height: 1, color: MyShopColors.divider),
          _SheetMenuItem(
            icon: Icons.info_outline_rounded,
            label: 'View Details',
            color: MyShopColors.textPrimary,
            onTap: () => Navigator.of(context).pop(),
            w: w,
            h: h,
          ),
          if (isActive) ...[
            const Divider(height: 1, color: MyShopColors.divider),
            _SheetMenuItem(
              icon: Icons.cancel_outlined,
              label: 'Cancel Request',
              color: MyShopColors.error,
              onTap: () => Navigator.of(context).pop(),
              w: w,
              h: h,
            ),
          ],
          const Divider(height: 1, color: MyShopColors.divider),
          _SheetMenuItem(
            icon: Icons.share_outlined,
            label: 'Share',
            color: MyShopColors.textPrimary,
            onTap: () => Navigator.of(context).pop(),
            w: w,
            h: h,
          ),
        ],
      ),
    );
  }
}

class _SheetMenuItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
  final double w;
  final double h;

  const _SheetMenuItem({
    required this.icon,
    required this.label,
    required this.color,
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
          vertical: h * 0.019,
        ),
        child: Row(
          children: [
            Icon(icon, size: w * 0.051, color: color),
            SizedBox(width: w * 0.038),
            Text(
              label,
              style: TextStyle(
                fontSize: w * 0.038,
                fontWeight: FontWeight.w500,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Empty state ────────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  final RequestFilter filter;
  final double w;
  final double h;

  const _EmptyState({
    required this.filter,
    required this.w,
    required this.h,
  });

  @override
  Widget build(BuildContext context) {
    final (icon, title, sub) = switch (filter) {
      RequestFilter.active => (
          Icons.hourglass_empty_rounded,
          'No active requests',
          'Post a new job to get bids from nearby artisans.'
        ),
      RequestFilter.completed => (
          Icons.check_circle_outline_rounded,
          'No completed jobs yet',
          'Your finished jobs will appear here.'
        ),
      RequestFilter.cancelled => (
          Icons.cancel_outlined,
          'No cancelled requests',
          'Cancelled jobs will be listed here.'
        ),
      RequestFilter.suspended => (
          Icons.pause_circle_outline_rounded,
          'No suspended requests',
          'Suspended jobs will be listed here.'
        ),
      _ => (
          Icons.work_outline_rounded,
          'No requests yet',
          'Post your first job to find a skilled artisan near you.'
        ),
    };

    return Center(
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: w * 0.082),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: w * 0.154, color: MyShopColors.disabled),
            SizedBox(height: h * 0.019),
            Text(
              title,
              style: TextStyle(
                fontSize: w * 0.041,
                fontWeight: FontWeight.w700,
                color: MyShopColors.textPrimary,
              ),
              textAlign: TextAlign.center,
            ),
            SizedBox(height: h * 0.009),
            Text(
              sub,
              style: TextStyle(
                fontSize: w * 0.033,
                fontWeight: FontWeight.w400,
                color: MyShopColors.textSecondary,
                height: 1.5,
              ),
              textAlign: TextAlign.center,
            ),
            SizedBox(height: h * 0.033),
            Builder(
              builder: (context) => GestureDetector(
                onTap: () => context.go('/services'),
                child: Container(
                  padding: EdgeInsets.symmetric(
                    horizontal: w * 0.077,
                    vertical: h * 0.017,
                  ),
                  decoration: BoxDecoration(
                    color: MyShopColors.darkSlate,
                    borderRadius: BorderRadius.circular(w * 0.021),
                  ),
                  child: Text(
                    'Post a Job',
                    style: TextStyle(
                      fontSize: w * 0.038,
                      fontWeight: FontWeight.w600,
                      color: MyShopColors.surfaceWhite,
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

// ── Bottom Navigation ──────────────────────────────────────────────────────────

class _BottomNav extends ConsumerWidget {
  final double w;
  final double h;
  const _BottomNav({required this.w, required this.h});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bottomPad = MediaQuery.paddingOf(context).bottom;
    final activeCount = ref.watch(activeJobCountProvider);

    return Container(
      height: h * 0.071 + bottomPad,
      decoration: const BoxDecoration(
        color: MyShopColors.surfaceWhite,
        border: Border(top: BorderSide(color: MyShopColors.divider)),
      ),
      padding: EdgeInsets.only(bottom: bottomPad),
      child: Row(
        children: [
          _NavItem(
            icon: Icons.home_outlined,
            label: 'Home',
            isActive: false,
            w: w,
            h: h,
          ),
          _NavItem(
            icon: Icons.grid_view_rounded,
            label: 'Services',
            isActive: false,
            w: w,
            h: h,
          ),
          _NavItemWithBadge(
            icon: Icons.history_rounded,
            label: 'Activity',
            isActive: true,
            badgeCount: activeCount,
            w: w,
            h: h,
          ),
          _NavItem(
            icon: Icons.person_outline_rounded,
            label: 'Account',
            isActive: false,
            w: w,
            h: h,
          ),
        ],
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isActive;
  final double w;
  final double h;

  const _NavItem({
    required this.icon,
    required this.label,
    required this.isActive,
    required this.w,
    required this.h,
  });

  @override
  Widget build(BuildContext context) {
    final color = isActive ? MyShopColors.primaryGold : MyShopColors.darkSlate;
    return Expanded(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: w * 0.062, color: color),
          SizedBox(height: h * 0.004),
          Text(
            label,
            style: TextStyle(
              fontSize: w * 0.026,
              fontWeight: isActive ? FontWeight.w700 : FontWeight.w400,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

class _NavItemWithBadge extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isActive;
  final int badgeCount;
  final double w;
  final double h;

  const _NavItemWithBadge({
    required this.icon,
    required this.label,
    required this.isActive,
    required this.badgeCount,
    required this.w,
    required this.h,
  });

  @override
  Widget build(BuildContext context) {
    final color = isActive ? MyShopColors.primaryGold : MyShopColors.darkSlate;
    return Expanded(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              Icon(icon, size: w * 0.062, color: color),
              if (badgeCount > 0)
                Positioned(
                  top: -(h * 0.008),
                  right: -(w * 0.026),
                  child: Container(
                    width: w * 0.051,
                    height: w * 0.051,
                    decoration: BoxDecoration(
                      color: MyShopColors.warning,
                      shape: BoxShape.circle,
                      border: Border.all(
                          color: MyShopColors.surfaceWhite, width: 1.5),
                    ),
                    child: Center(
                      child: Text(
                        '$badgeCount',
                        style: TextStyle(
                          fontSize: w * 0.023,
                          fontWeight: FontWeight.w700,
                          color: MyShopColors.surfaceWhite,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
          SizedBox(height: h * 0.004),
          Text(
            label,
            style: TextStyle(
              fontSize: w * 0.026,
              fontWeight: isActive ? FontWeight.w700 : FontWeight.w400,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}
