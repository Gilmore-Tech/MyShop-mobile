import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:shared_models/shared_models.dart';
import 'package:shared_ui/shared_ui.dart';

import '../providers/driver_trips_provider.dart';
import '../widgets/date_range_picker_modal.dart';
import '../widgets/trip_detail_modal.dart';

/// Trips history screen with date range filter, tab filters, and trip
/// cards. Trips come from [driverTripsProvider] (`GET /rides`); the
/// All/Completed/Cancelled tabs and the date range are pure client-side
/// filters over that list — small enough to keep in memory.
///
/// Figma: node 219:14044
/// PRD Reference: PRD 5.4
class TripsHistoryScreen extends ConsumerStatefulWidget {
  const TripsHistoryScreen({super.key});

  @override
  ConsumerState<TripsHistoryScreen> createState() => _TripsHistoryScreenState();
}

class _TripsHistoryScreenState extends ConsumerState<TripsHistoryScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  DateTime? _rangeStart;
  DateTime? _rangeEnd;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this)
      ..addListener(() => setState(() {}));
  }

  bool get _hasFilter => _rangeStart != null && _rangeEnd != null;

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  String get _dateLabel {
    if (!_hasFilter) return 'All History';
    final fmt = DateFormat('MMM dd');
    final yearFmt = DateFormat('MMM dd, yyyy');
    final start = _rangeStart!;
    final end = _rangeEnd!;
    if (start.year == end.year) {
      return '${fmt.format(start)} - ${yearFmt.format(end)}';
    }
    return '${yearFmt.format(start)} - ${yearFmt.format(end)}';
  }

  Future<void> _openDatePicker() async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final result = await DateRangePickerModal.show(
      context,
      initialStart: _rangeStart ?? today.subtract(const Duration(days: 29)),
      initialEnd: _rangeEnd ?? today,
    );
    if (result != null) {
      setState(() {
        _rangeStart = result.start;
        _rangeEnd = result.end;
      });
    }
  }

  /// Date used to bucket each trip. Completed trips fall in the day they
  /// finished; cancelled trips in the day they were cancelled; everything
  /// else falls back to creation time so we never lose a row.
  DateTime _bucketDate(Ride ride) =>
      ride.completedAt ?? ride.cancelledAt ?? ride.createdAt;

  Iterable<Ride> _applyFilters(Iterable<Ride> rides) {
    Iterable<Ride> out = rides;
    // Tab filter
    final tabIndex = _tabController.index;
    if (tabIndex == 1) {
      out = out.where((r) => r.status == RideStatus.completed);
    } else if (tabIndex == 2) {
      out = out.where((r) => r.status == RideStatus.cancelled);
    } else {
      // All — exclude in-flight rides; the active-ride screen owns those.
      out = out.where(
        (r) =>
            r.status == RideStatus.completed ||
            r.status == RideStatus.cancelled,
      );
    }
    // Date range filter (inclusive on both ends — local-day boundaries).
    if (_hasFilter) {
      final start = DateTime(
        _rangeStart!.year,
        _rangeStart!.month,
        _rangeStart!.day,
      );
      final endExclusive = DateTime(
        _rangeEnd!.year,
        _rangeEnd!.month,
        _rangeEnd!.day + 1,
      );
      out = out.where((r) {
        final at = _bucketDate(r).toLocal();
        return !at.isBefore(start) && at.isBefore(endExclusive);
      });
    }
    return out;
  }

  /// Sum of the inclusive trip fares. A promo ride's discounted client charge
  /// (which can be 0) must not shrink the driver's trip-value strip; the
  /// platform covers the discount and any access charge is already included.
  int _sumPesewas(Iterable<Ride> rides) {
    var total = 0;
    for (final r in rides) {
      total += r.tripFarePesewas;
    }
    return total;
  }

  /// Daily totals (oldest → newest, capped at 7) for the bottom mini-chart.
  /// Rendered as relative bar heights so we don't need to fetch a separate
  /// time series.
  List<double> _last7DaysHeights(List<Ride> completed) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final perDay = List<int>.filled(7, 0);
    for (final r in completed) {
      final at = _bucketDate(r).toLocal();
      final dayKey = DateTime(at.year, at.month, at.day);
      final delta = today.difference(dayKey).inDays;
      if (delta < 0 || delta >= 7) continue;
      perDay[6 - delta] += r.tripFarePesewas;
    }
    final maxVal =
        perDay.fold<int>(0, (m, v) => v > m ? v : m).clamp(1, 1 << 30);
    return [for (final v in perDay) (v / maxVal).clamp(0.05, 1.0)];
  }

  String _formatGhs(int pesewas) {
    final ghs = (pesewas / 100).floor();
    if (ghs < 1000) return '₵$ghs';
    final str = ghs.toString();
    final buffer = StringBuffer('₵');
    for (var i = 0; i < str.length; i++) {
      if (i > 0 && (str.length - i) % 3 == 0) buffer.write(',');
      buffer.write(str[i]);
    }
    return buffer.toString();
  }

  @override
  Widget build(BuildContext context) {
    final tripsAsync = ref.watch(driverTripsProvider);

    return Scaffold(
      backgroundColor: MyShopColors.surfaceWhite,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header + date picker
            Padding(
              padding: const EdgeInsets.fromLTRB(
                MyShopSpacing.md,
                MyShopSpacing.md,
                MyShopSpacing.md,
                0,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Trips',
                    style: TextStyle(
                      fontFamily: 'Raleway',
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: MyShopColors.textPrimary,
                    ),
                  ),
                  GestureDetector(
                    onTap: _openDatePicker,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: MyShopColors.offWhite,
                        borderRadius: BorderRadius.circular(17),
                        border: Border.all(color: MyShopColors.divider),
                        boxShadow: const [
                          BoxShadow(
                            color: Color(0x12171A1F),
                            blurRadius: 2.5,
                            offset: Offset(0, 1),
                          ),
                        ],
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.calendar_today,
                            size: 14,
                            color: MyShopColors.darkSlate,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            _dateLabel,
                            style: MyShopTypography.body2.copyWith(
                              fontWeight: FontWeight.w600,
                              color: MyShopColors.darkSlate,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: MyShopSpacing.md),

            // Tab bar
            Container(
              margin: const EdgeInsets.symmetric(horizontal: MyShopSpacing.md),
              decoration: BoxDecoration(
                color: MyShopColors.surfaceGrey,
                borderRadius: BorderRadius.circular(12),
              ),
              child: TabBar(
                controller: _tabController,
                indicator: BoxDecoration(
                  color: MyShopColors.surfaceWhite,
                  borderRadius: BorderRadius.circular(10),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x0D000000),
                      blurRadius: 4,
                      offset: Offset(0, 1),
                    ),
                  ],
                ),
                indicatorSize: TabBarIndicatorSize.tab,
                dividerColor: Colors.transparent,
                labelColor: MyShopColors.textPrimary,
                unselectedLabelColor: MyShopColors.textSecondary,
                labelStyle: const TextStyle(
                  fontFamily: 'Raleway',
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
                unselectedLabelStyle: const TextStyle(
                  fontFamily: 'Raleway',
                  fontSize: 13,
                  fontWeight: FontWeight.w400,
                ),
                indicatorPadding: const EdgeInsets.all(3),
                tabs: const [
                  Tab(text: 'All'),
                  Tab(text: 'Completed'),
                  Tab(text: 'Cancelled'),
                ],
              ),
            ),
            const SizedBox(height: MyShopSpacing.md),

            Expanded(
              child: tripsAsync.when(
                loading: () => const _TripsSkeleton(),
                error: (_, __) => _TripsErrorState(
                  onRetry: () => ref.invalidate(driverTripsProvider),
                ),
                data: (trips) {
                  final filtered = _applyFilters(trips).toList()
                    ..sort((a, b) => _bucketDate(b).compareTo(_bucketDate(a)));
                  if (filtered.isEmpty) return const _TripsEmptyState();
                  return RefreshIndicator(
                    onRefresh: () async => ref.invalidate(driverTripsProvider),
                    child: ListView.separated(
                      padding: const EdgeInsets.symmetric(
                        horizontal: MyShopSpacing.md,
                        vertical: 4,
                      ),
                      itemCount: filtered.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (context, i) {
                        final trip = filtered[i];
                        return _TripCard(
                          trip: trip,
                          onTap: () => TripDetailModal.show(
                            context,
                            _rideToTripDetailData(trip),
                          ),
                        );
                      },
                    ),
                  );
                },
              ),
            ),

            // Monthly summary — sum of last 30d completed fares with a
            // 7-day mini-chart of relative daily totals.
            tripsAsync.maybeWhen(
              data: (trips) {
                final now = DateTime.now();
                final cutoff = now.subtract(const Duration(days: 30));
                final completed = trips
                    .where(
                      (r) =>
                          r.status == RideStatus.completed &&
                          _bucketDate(r).isAfter(cutoff),
                    )
                    .toList();
                final monthlyTotal = _sumPesewas(completed);
                final heights = _last7DaysHeights(completed);
                return Container(
                  width: double.infinity,
                  margin: const EdgeInsets.all(MyShopSpacing.md),
                  padding: const EdgeInsets.symmetric(
                    horizontal: MyShopSpacing.md,
                    vertical: 14,
                  ),
                  decoration: BoxDecoration(
                    color: MyShopColors.darkSlate,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'LAST 30 DAYS',
                            style: MyShopTypography.overline.copyWith(
                              fontSize: 9,
                              color: Colors.white54,
                            ),
                          ),
                          Text(
                            _formatGhs(monthlyTotal),
                            style: const TextStyle(
                              fontFamily: 'Raleway',
                              fontSize: 22,
                              fontWeight: FontWeight.w900,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ),
                      Row(
                        children: [
                          for (final h in heights)
                            Container(
                              width: 8,
                              height: 40 * h,
                              margin: const EdgeInsets.only(left: 3),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(
                                  alpha: h < 0.1 ? 0.2 : 0.7,
                                ),
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                );
              },
              orElse: () => const SizedBox.shrink(),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Trip card ───────────────────────────────────────────────────────────────

class _TripCard extends StatelessWidget {
  const _TripCard({required this.trip, this.onTap});

  final Ride trip;

  /// Tapping a card opens [TripDetailModal] with the mapped trip detail.
  /// Optional so the widget remains testable without a real navigator.
  final VoidCallback? onTap;

  Color get _statusColor {
    switch (trip.status) {
      case RideStatus.completed:
        return MyShopColors.success;
      case RideStatus.cancelled:
        return MyShopColors.error;
      default:
        return MyShopColors.textSecondary;
    }
  }

  String get _statusLabel {
    switch (trip.status) {
      case RideStatus.completed:
        return 'COMPLETED';
      case RideStatus.cancelled:
        return 'CANCELLED';
      default:
        return trip.status.name.toUpperCase();
    }
  }

  String _dateLabel(DateTime at) {
    final local = at.toLocal();
    final hh = local.hour.toString().padLeft(2, '0');
    final mm = local.minute.toString().padLeft(2, '0');
    final fmt = DateFormat('d MMM');
    return '${fmt.format(local)} · $hh:$mm';
  }

  @override
  Widget build(BuildContext context) {
    final at = trip.completedAt ?? trip.cancelledAt ?? trip.createdAt;
    final distance = trip.actualDistanceKm ?? trip.estimatedDistanceKm;
    final duration = trip.actualDurationMins ?? trip.estimatedDurationMins;
    // InkWell needs a Material ancestor for ripple feedback. We borrow the
    // card's own background so the ripple stays inside the rounded border.
    return Material(
      color: MyShopColors.surfaceWhite,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.all(MyShopSpacing.md),
          decoration: BoxDecoration(
            color: MyShopColors.surfaceWhite,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: MyShopColors.divider),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      _dateLabel(at),
                      style: MyShopTypography.body2.copyWith(fontSize: 11),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: _statusColor.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      _statusLabel,
                      style: TextStyle(
                        fontFamily: 'Raleway',
                        fontSize: 9,
                        fontWeight: FontWeight.w900,
                        color: _statusColor,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              _TripPoint(
                color: MyShopColors.darkSlate,
                address:
                    trip.pickupAddress.isEmpty ? 'Pickup' : trip.pickupAddress,
              ),
              Container(
                margin: const EdgeInsets.only(left: 5, top: 2, bottom: 2),
                width: 2,
                height: 14,
                color: MyShopColors.divider,
              ),
              _TripPoint(
                color: MyShopColors.primaryGold,
                address: trip.dropoffAddress.isEmpty
                    ? 'Destination'
                    : trip.dropoffAddress,
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  if (distance > 0)
                    _MetaChip(
                      icon: Icons.straighten,
                      label: '${distance.toStringAsFixed(1)} km',
                    ),
                  if (distance > 0) const SizedBox(width: 8),
                  if (duration > 0)
                    _MetaChip(icon: Icons.access_time, label: '$duration mins'),
                  const Spacer(),
                  // Fare is only meaningful when the ride actually completed —
                  // cancelled rides never charged the rider, so showing a number
                  // here reads as "you earned this" which is misleading. We
                  // surface a dash for non-completed terminal states instead.
                  if (trip.status == RideStatus.completed)
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          // Inclusive provider fare, not the promo-discounted
                          // client charge.
                          trip.tripFareDisplay,
                          style: const TextStyle(
                            fontFamily: 'Raleway',
                            fontSize: 16,
                            fontWeight: FontWeight.w900,
                            color: MyShopColors.textPrimary,
                          ),
                        ),
                        if ((trip.toll?.amountPesewas ?? 0) > 0)
                          Text(
                            '${trip.toll!.label} included',
                            style: const TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.w600,
                              color: MyShopColors.textSecondary,
                            ),
                          ),
                      ],
                    )
                  else
                    const Text(
                      '—',
                      style: TextStyle(
                        fontFamily: 'Raleway',
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: MyShopColors.textSecondary,
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TripPoint extends StatelessWidget {
  const _TripPoint({required this.color, required this.address});

  final Color color;
  final String address;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 12,
          height: 12,
          margin: const EdgeInsets.only(top: 3),
          decoration: BoxDecoration(
            color: Colors.transparent,
            border: Border.all(color: color, width: 2),
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            address,
            style: const TextStyle(
              fontFamily: 'Raleway',
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: MyShopColors.textPrimary,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

class _MetaChip extends StatelessWidget {
  const _MetaChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: MyShopColors.surfaceGrey,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: MyShopColors.textSecondary),
          const SizedBox(width: 4),
          Text(
            label,
            style: const TextStyle(
              fontFamily: 'Raleway',
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: MyShopColors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Empty / loading / error states ───────────────────────────────────────

class _TripsEmptyState extends StatelessWidget {
  const _TripsEmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: MyShopColors.surfaceGrey,
              borderRadius: BorderRadius.circular(28),
            ),
            child: const Icon(
              Icons.directions_car_outlined,
              size: 28,
              color: MyShopColors.textSecondary,
            ),
          ),
          const SizedBox(height: MyShopSpacing.md),
          Text(
            'No trips here',
            style: MyShopTypography.body1.copyWith(
              fontWeight: FontWeight.w600,
              color: MyShopColors.textPrimary,
            ),
          ),
          const SizedBox(height: MyShopSpacing.xs),
          Text(
            'Try a different filter or pull to refresh',
            style: MyShopTypography.body2.copyWith(
              color: MyShopColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

class _TripsErrorState extends StatelessWidget {
  const _TripsErrorState({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.error_outline_rounded,
            size: 36,
            color: MyShopColors.error,
          ),
          const SizedBox(height: 8),
          Text(
            "Couldn't load your trips",
            style: MyShopTypography.body1.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 12),
          OutlinedButton(onPressed: onRetry, child: const Text('Retry')),
        ],
      ),
    );
  }
}

class _TripsSkeleton extends StatelessWidget {
  const _TripsSkeleton();

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.symmetric(
        horizontal: MyShopSpacing.md,
        vertical: 4,
      ),
      itemCount: 4,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (_, __) => Container(
        height: 130,
        decoration: BoxDecoration(
          color: MyShopColors.shimmerBase,
          borderRadius: BorderRadius.circular(14),
        ),
      ),
    );
  }
}

// ─── Ride → TripDetailData mapping ──────────────────────────────────────────
//
// TripDetailModal was designed for a rich snapshot (per-line fare breakdown,
// commission split). The list endpoint only carries the Ride summary, so the
// breakdown lines fall back to '—'. The modal still surfaces what matters:
// status, route, distance/duration, full fare, client payment, discounts and
// any settlement fields carried by the list snapshot. Cancelled trips render
// the "No fare collected" notice
// added earlier, so the placeholder breakdown lines never reach the user.
//
// When we add a `GET /rides/:id/snapshot` endpoint, swap this for a fetch +
// fuller mapping; the modal's contract doesn't change.

TripDetailData _rideToTripDetailData(Ride r) {
  final at = r.completedAt ?? r.cancelledAt ?? r.createdAt;
  final local = at.toLocal();
  final dateFmt = DateFormat('d MMM yyyy');
  final timeFmt = DateFormat('HH:mm');

  final pickupAt = r.pickedUpAt ?? r.acceptedAt ?? r.createdAt;
  final dropAt = r.completedAt ?? r.cancelledAt ?? pickupAt;

  String fmtTime(DateTime t) => timeFmt.format(t.toLocal());
  String fmtPesewas(int pesewas) => 'GHS ${(pesewas / 100).toStringAsFixed(2)}';

  final isCompleted = r.status == RideStatus.completed;
  final statusLabel = switch (r.status) {
    RideStatus.completed => 'Completed',
    RideStatus.cancelled => 'Cancelled',
    _ => r.status.name[0].toUpperCase() + r.status.name.substring(1),
  };

  // Distance + duration prefer the actual values (post-ride) over the
  // estimate so completed trips show what really happened.
  final distance = r.actualDistanceKm ?? r.estimatedDistanceKm;
  final duration = r.actualDurationMins ?? r.estimatedDurationMins;
  final clientPaidPesewas = r.collectFromClientPesewas ?? r.totalPaidPesewas;
  final providerCommissionPesewas = r.providerCommissionPesewas;
  final providerEarningsPesewas = r.settledProviderEarningsPesewas;
  final providerSettlementBasisPesewas =
      r.settledProviderSettlementBasisPesewas;

  return TripDetailData(
    tripId: 'TRP-${r.id.substring(0, 8).toUpperCase()}',
    rideId: r.id,
    status: statusLabel,
    date: dateFmt.format(local),
    timeRange: '${fmtTime(pickupAt)} – ${fmtTime(dropAt)}',
    pickupTime: fmtTime(pickupAt),
    pickupAddress: r.pickupAddress.isEmpty ? 'Pickup' : r.pickupAddress,
    dropoffTime: fmtTime(dropAt),
    dropoffAddress: r.dropoffAddress.isEmpty ? 'Destination' : r.dropoffAddress,
    // Coords for the map preview come from `GET /rides/:id` inside the
    // modal — the list endpoint can't project PostGIS geometry so the
    // Ride model arrives here with lat/lng=0. The modal handles the
    // fetch + placeholder.
    distanceKm: distance.toStringAsFixed(1),
    durationMins: duration,
    surgeMultiplier: '${r.surgeMultiplier.toStringAsFixed(1)}x',
    // Component lines are placeholders — the detail GET fills them in. Raw
    // monetary fields below retain their server meaning for truthful fallback.
    baseFare: '—',
    distanceFare: '—',
    timeFare: '—',
    surgeFare: r.hasSurge ? '—' : 'GHS 0.00',
    subtotal: isCompleted ? r.tripFareDisplay : '—',
    taxes: '—',
    promoDiscount: r.promoApplied && r.promoDiscountPesewas != null
        ? '- GHS ${((r.promoDiscountPesewas ?? 0) / 100).toStringAsFixed(2)}'
        : '—',
    totalPaid: isCompleted && clientPaidPesewas != null
        ? fmtPesewas(clientPaidPesewas)
        : '—',
    commission: providerCommissionPesewas == null
        ? 'Pending'
        : fmtPesewas(providerCommissionPesewas),
    paymentMethod: _formatPaymentMethod(r.paymentMethod),
    tripFarePesewas: isCompleted ? r.tripFarePesewas : null,
    clientPaidPesewas: isCompleted ? clientPaidPesewas : null,
    promoDiscountPesewas: r.promoDiscountPesewas,
    loyaltyDiscountPesewas: r.loyaltyDiscountPesewas,
    providerCommissionPesewas: providerCommissionPesewas,
    providerEarningsPesewas: providerEarningsPesewas,
    providerSettlementBasisPesewas: providerSettlementBasisPesewas,
    financialsFinal: r.financialsFinal,
    commissionIsEffective: r.effectiveCommissionPesewas != null,
    toll: r.toll,
  );
}

/// Human-friendly payment method label for the detail modal footer.
/// Mirrors the labels the client app uses on the pre-booking sheet so the
/// same trip reads consistently across surfaces.
String _formatPaymentMethod(String raw) {
  switch (raw) {
    case 'cash':
      return 'Cash';
    case 'momo_mtn':
      return 'MTN MoMo';
    case 'momo_telecel':
      return 'Telecel MoMo';
    case 'momo_airteltigo':
      return 'AirtelTigo MoMo';
    case 'card':
      return 'Card';
    default:
      return raw.isEmpty
          ? 'Unknown'
          : raw[0].toUpperCase() + raw.substring(1).replaceAll('_', ' ');
  }
}
