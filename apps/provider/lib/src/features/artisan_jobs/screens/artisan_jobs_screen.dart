import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_models/shared_models.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../../app/router.dart' show JobRequestRouteExtra;
import '../../../core/providers/nav_badge_provider.dart';
import '../../artisan_home/providers/active_job_provider.dart';
import '../../artisan_home/widgets/bid_status_banner.dart';
import '../providers/artisan_jobs_provider.dart';
import '../providers/pending_incoming_jobs_provider.dart';

/// "My Jobs" — the artisan's third tab. Lists every job the artisan has
/// bid on or been assigned to, grouped into Active / Bids / Completed.
///
/// Tapping a card opens the full `/job-request` screen so the artisan can
/// review, re-bid, message, or continue the work.
class ArtisanJobsScreen extends ConsumerStatefulWidget {
  const ArtisanJobsScreen({super.key});

  @override
  ConsumerState<ArtisanJobsScreen> createState() => _ArtisanJobsScreenState();
}

class _ArtisanJobsScreenState extends ConsumerState<ArtisanJobsScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;

  @override
  void initState() {
    super.initState();
    // Land on the "Bids" tab by default — that's the artisan's primary
    // workspace (where their submitted bids live). The other tabs cover
    // adjacent states (new requests, jobs in progress, completed work).
    _tabs = TabController(
      length: ArtisanJobFilter.values.length,
      vsync: this,
      initialIndex: ArtisanJobFilter.submitted.index,
    );
    // Clear the "New" badge once the artisan opens this screen — they're
    // looking at the requests now.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(navBadgeProvider.notifier).clear('/trips');
    });
  }

  Future<void> _pickDateRange() async {
    final current = ref.read(artisanJobsDateFilterProvider);
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 2),
      lastDate: now,
      initialDateRange: current ??
          DateTimeRange(
            start: now.subtract(const Duration(days: 30)),
            end: now,
          ),
      helpText: 'Filter by date',
      saveText: 'Apply',
    );
    if (picked != null) {
      ref.read(artisanJobsDateFilterProvider.notifier).state = picked;
    }
  }

  void _clearDateFilter() {
    ref.read(artisanJobsDateFilterProvider.notifier).state = null;
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(artisanJobsProvider);
    final dateFilter = ref.watch(artisanJobsDateFilterProvider);
    final hasDateFilter = dateFilter != null;

    return Scaffold(
      backgroundColor: MyShopColors.offWhite,
      appBar: AppBar(
        backgroundColor: MyShopColors.surfaceWhite,
        elevation: 0,
        title: Text(
          'My Jobs',
          style: MyShopTypography.h1.copyWith(
            fontWeight: FontWeight.w800,
            fontSize: 20,
          ),
        ),
        actions: [
          // Calendar icon — opens a date-range picker. When a filter is
          // active, the icon flips to filled + gold so the user can see at
          // a glance that the list is narrowed.
          IconButton(
            tooltip: 'Filter by date',
            icon: Icon(
              hasDateFilter
                  ? Icons.event_available
                  : Icons.calendar_today_outlined,
              color: hasDateFilter
                  ? MyShopColors.primaryGold
                  : MyShopColors.textPrimary,
            ),
            onPressed: _pickDateRange,
          ),
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh, color: MyShopColors.textPrimary),
            onPressed: () => ref.read(artisanJobsProvider.notifier).load(),
          ),
        ],
        bottom: TabBar(
          controller: _tabs,
          indicatorColor: MyShopColors.primaryGold,
          indicatorWeight: 3,
          labelColor: MyShopColors.primaryGold,
          unselectedLabelColor: MyShopColors.textSecondary,
          labelStyle: MyShopTypography.button.copyWith(
            fontWeight: FontWeight.w800,
          ),
          tabs: [
            for (final f in ArtisanJobFilter.values) Tab(text: f.label),
          ],
        ),
      ),
      body: Column(
        children: [
          if (hasDateFilter)
            _DateFilterChip(
              range: dateFilter,
              onTap: _pickDateRange,
              onClear: _clearDateFilter,
            ),
          Expanded(
            child: TabBarView(
              controller: _tabs,
              children: [
                for (final f in ArtisanJobFilter.values)
                  _JobsTab(
                    filter: f,
                    isLoading: state.isLoading,
                    errorMessage: state.errorMessage,
                    onRetry: () =>
                        ref.read(artisanJobsProvider.notifier).load(),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Compact chip shown below the tab bar when a date filter is active.
/// Tap the chip body to re-open the picker; tap × to clear the filter.
class _DateFilterChip extends StatelessWidget {
  const _DateFilterChip({
    required this.range,
    required this.onTap,
    required this.onClear,
  });

  final DateTimeRange range;
  final VoidCallback onTap;
  final VoidCallback onClear;

  static const _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  String _fmt(DateTime d) =>
      '${_months[d.month - 1]} ${d.day}, ${d.year}';

  @override
  Widget build(BuildContext context) {
    final sameDay = range.start.year == range.end.year &&
        range.start.month == range.end.month &&
        range.start.day == range.end.day;
    final label = sameDay
        ? _fmt(range.start)
        : '${_fmt(range.start)} — ${_fmt(range.end)}';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(
        MyShopSpacing.md,
        MyShopSpacing.sm,
        MyShopSpacing.md,
        0,
      ),
      color: MyShopColors.surfaceWhite,
      child: Row(
        children: [
          Expanded(
            child: InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(20),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: MyShopSpacing.md,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: MyShopColors.primaryGoldLight,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: MyShopColors.primaryGold),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.event_available,
                      size: 14,
                      color: MyShopColors.primaryGoldDark,
                    ),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        label,
                        style: MyShopTypography.body2.copyWith(
                          color: MyShopColors.primaryGoldDark,
                          fontWeight: FontWeight.w700,
                          fontSize: 12,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 6),
                    GestureDetector(
                      onTap: onClear,
                      child: const Icon(
                        Icons.close,
                        size: 14,
                        color: MyShopColors.primaryGoldDark,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _JobsTab extends ConsumerWidget {
  const _JobsTab({
    required this.filter,
    required this.isLoading,
    required this.errorMessage,
    required this.onRetry,
  });

  final ArtisanJobFilter filter;
  final bool isLoading;
  final String? errorMessage;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // The "New" tab is sourced from the in-memory pending list (socket
    // pushes), not from the backend `/jobs` query.
    if (filter == ArtisanJobFilter.newRequests) {
      final pending = ref.watch(pendingIncomingJobsProvider);
      if (pending.isEmpty) return _EmptyState(filter: filter);
      return RefreshIndicator(
        onRefresh: () => ref.read(artisanJobsProvider.notifier).load(),
        child: ListView.separated(
          padding: const EdgeInsets.all(MyShopSpacing.md),
          itemCount: pending.length,
          separatorBuilder: (_, __) => const SizedBox(height: MyShopSpacing.sm),
          itemBuilder: (_, i) =>
              _JobCard(entry: ArtisanJobEntry(job: pending[i])),
        ),
      );
    }

    if (isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (errorMessage != null) {
      return _ErrorState(message: errorMessage!, onRetry: onRetry);
    }

    final entries = ref.watch(artisanJobsFilteredProvider(filter));
    if (entries.isEmpty) return _EmptyState(filter: filter);

    return RefreshIndicator(
      onRefresh: () => ref.read(artisanJobsProvider.notifier).load(),
      child: ListView.separated(
        padding: const EdgeInsets.all(MyShopSpacing.md),
        itemCount: entries.length,
        separatorBuilder: (_, __) => const SizedBox(height: MyShopSpacing.sm),
        itemBuilder: (_, i) => _JobCard(entry: entries[i]),
      ),
    );
  }
}

class _JobCard extends ConsumerWidget {
  const _JobCard({required this.entry});

  final ArtisanJobEntry entry;

  /// Statuses owned by the /active-job screen — once the artisan has tapped
  /// "Accept & Start Job", tapping the card again should open the map flow
  /// directly rather than the request-details screen.
  static bool _isActiveWork(JobStatus status) =>
      status == JobStatus.artisanEnRoute ||
      status == JobStatus.arrived ||
      status == JobStatus.inProgress ||
      status == JobStatus.artisanMarkedComplete;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final job = entry.job;
    final title = job.categoryName != null && job.categoryName!.isNotEmpty
        ? '${job.categoryName} request'
        : 'Service Request';
    final (statusLabel, statusColor) = _statusPresentation(entry);

    return InkWell(
      onTap: () {
        // An already-active job belongs on the map screen — seed the
        // active-job slot and bypass /job-request entirely.
        if (_isActiveWork(job.status)) {
          ref.read(activeJobProvider.notifier).setJob(job);
          context.pushReplacement('/active-job');
          return;
        }
        // Map the artisan's job relationship to a BidStatus so the detail
        // screen shows the right banner (pending / accepted / not selected).
        final status = _bidStatusFor(entry);
        context.push(
          '/job-request',
          extra: JobRequestRouteExtra(
            job: job,
            bidStatus: status,
            submittedBidAmount: (entry.bidAmountPesewas ?? 0) / 100,
          ),
        );
      },
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
            Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: MyShopTypography.h3.copyWith(
                      fontWeight: FontWeight.w800,
                      fontSize: 15,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                _StatusPill(label: statusLabel, color: statusColor),
              ],
            ),
            const SizedBox(height: MyShopSpacing.xs),
            Row(
              children: [
                const Icon(
                  Icons.person_outline,
                  size: 14,
                  color: MyShopColors.textSecondary,
                ),
                const SizedBox(width: 4),
                Flexible(
                  child: Text(
                    job.clientName ?? 'Client',
                    style: MyShopTypography.body2,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: MyShopSpacing.sm),
                const Icon(
                  Icons.location_on_outlined,
                  size: 14,
                  color: MyShopColors.textSecondary,
                ),
                const SizedBox(width: 4),
                Flexible(
                  child: Text(
                    job.addressText ?? '',
                    style: MyShopTypography.body2,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            if (job.description.isNotEmpty) ...[
              const SizedBox(height: MyShopSpacing.sm),
              Text(
                job.description,
                style: MyShopTypography.body2,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
            const SizedBox(height: MyShopSpacing.sm),
            Row(
              children: [
                if (entry.hasBid)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: MyShopColors.primaryGold.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.gavel,
                          size: 14,
                          color: MyShopColors.primaryGold,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          entry.bidAmountDisplay.isNotEmpty
                              ? 'Your bid: ${entry.bidAmountDisplay}'
                              : 'Bid placed',
                          style: MyShopTypography.body2.copyWith(
                            color: MyShopColors.primaryGold,
                            fontWeight: FontWeight.w800,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                const Spacer(),
                if (job.createdAt != null)
                  Text(
                    _relativeTime(job.createdAt!),
                    style: MyShopTypography.caption.copyWith(
                      color: MyShopColors.textSecondary,
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  (String, Color) _statusPresentation(ArtisanJobEntry entry) {
    // An artisan-owned bid takes precedence over raw job state so the pill
    // always reflects the artisan's personal outcome.
    if (entry.bidRejected) return ('NOT SELECTED', MyShopColors.textSecondary);
    if (entry.bidAccepted) {
      switch (entry.job.status) {
        case JobStatus.confirmed:
          return ('CONFIRMED', MyShopColors.success);
        case JobStatus.artisanEnRoute:
          return ('EN ROUTE', MyShopColors.primaryGold);
        case JobStatus.arrived:
          return ('ARRIVED', MyShopColors.primaryGold);
        case JobStatus.inProgress:
          return ('IN PROGRESS', MyShopColors.primaryGold);
        case JobStatus.artisanMarkedComplete:
          return ('PENDING REVIEW', MyShopColors.warning);
        case JobStatus.pendingPayment:
          return ('AWAITING PAYMENT', MyShopColors.warning);
        case JobStatus.completed:
          return ('COMPLETED', MyShopColors.success);
        case JobStatus.cancelled:
          return ('CANCELLED', MyShopColors.error);
        case JobStatus.pendingAdmin:
        case JobStatus.adminAssigned:
        case JobStatus.open:
        case JobStatus.queued:
          return ('ACCEPTED', MyShopColors.success);
      }
    }
    switch (entry.job.status) {
      case JobStatus.pendingAdmin:
        return ('AWAITING ADMIN', MyShopColors.warning);
      case JobStatus.adminAssigned:
        // Admin routed this job — if it's to us the artisan is expected
        // to submit a quote next. If it's to someone else the bid is moot.
        return ('ADMIN ASSIGNED', MyShopColors.primaryGold);
      case JobStatus.open:
      case JobStatus.queued:
        return ('BID SENT', MyShopColors.primaryGold);
      // Bid wasn't accepted but job moved on — the client picked someone else.
      case JobStatus.confirmed:
      case JobStatus.artisanEnRoute:
      case JobStatus.arrived:
      case JobStatus.inProgress:
      case JobStatus.artisanMarkedComplete:
      case JobStatus.pendingPayment:
      case JobStatus.completed:
        return ('NOT SELECTED', MyShopColors.textSecondary);
      case JobStatus.cancelled:
        return ('CANCELLED', MyShopColors.error);
    }
  }

  /// Map the artisan's relationship to a job into a [BidStatus] the
  /// detail screen's banner understands.
  BidStatus _bidStatusFor(ArtisanJobEntry entry) {
    if (entry.bidAccepted) return BidStatus.accepted;
    if (entry.bidRejected) return BidStatus.notSelected;
    final status = entry.job.status;
    if (status == JobStatus.pendingAdmin ||
        status == JobStatus.adminAssigned ||
        status == JobStatus.open ||
        status == JobStatus.queued) {
      return BidStatus.pending;
    }
    // Bid wasn't marked rejected but the job moved on without us — treat
    // as not-selected so the banner still communicates the outcome.
    if (entry.hasBid) return BidStatus.notSelected;
    return BidStatus.none;
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: MyShopTypography.overline.copyWith(
          color: color,
          fontWeight: FontWeight.w900,
          fontSize: 10,
          letterSpacing: 0.8,
        ),
      ),
    );
  }
}

String _relativeTime(String iso) {
  final parsed = DateTime.tryParse(iso);
  if (parsed == null) return '';
  final diff = DateTime.now().toUtc().difference(parsed.toUtc());
  if (diff.inMinutes < 1) return 'now';
  if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
  if (diff.inHours < 24) return '${diff.inHours}h ago';
  if (diff.inDays == 1) return 'yesterday';
  return '${diff.inDays}d ago';
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.filter});

  final ArtisanJobFilter filter;

  @override
  Widget build(BuildContext context) {
    final (icon, message) = switch (filter) {
      ArtisanJobFilter.newRequests => (
          Icons.notifications_none,
          'No new requests yet. New jobs will land here as soon as a '
              'client posts one nearby.'
        ),
      ArtisanJobFilter.active => (
          Icons.work_off_outlined,
          'No active jobs right now. Bids you win will appear here.'
        ),
      ArtisanJobFilter.submitted => (
          Icons.gavel_outlined,
          'No pending bids. When a client posts a job nearby, place a bid '
              'to show up here.'
        ),
      ArtisanJobFilter.completed => (
          Icons.check_circle_outline,
          'No completed jobs yet.'
        ),
    };

    return Padding(
      padding: const EdgeInsets.all(32),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 56, color: MyShopColors.textSecondary),
            const SizedBox(height: MyShopSpacing.md),
            Text(
              message,
              textAlign: TextAlign.center,
              style: MyShopTypography.body1.copyWith(
                color: MyShopColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.error_outline,
              size: 56,
              color: MyShopColors.error,
            ),
            const SizedBox(height: MyShopSpacing.md),
            Text(
              message,
              textAlign: TextAlign.center,
              style: MyShopTypography.body1,
            ),
            const SizedBox(height: MyShopSpacing.md),
            ElevatedButton(
              onPressed: onRetry,
              child: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}
