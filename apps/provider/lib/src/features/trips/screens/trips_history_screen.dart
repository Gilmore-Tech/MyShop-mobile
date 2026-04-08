import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_ui/shared_ui.dart';

import '../widgets/date_range_picker_modal.dart';
import '../widgets/trip_detail_modal.dart';

/// Trips history screen with date range filter, tab filters, and trip cards.
///
/// Figma: node 219:14044
/// PRD Reference: PRD 5.4
///
/// Features: Date range selector, All/Completed/Cancelled tabs,
/// trip cards with pickup/destination/fare/duration/status,
/// monthly spending summary at bottom.
class TripsHistoryScreen extends StatefulWidget {
  const TripsHistoryScreen({super.key});

  @override
  State<TripsHistoryScreen> createState() => _TripsHistoryScreenState();
}

class _TripsHistoryScreenState extends State<TripsHistoryScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  DateTime? _rangeStart;
  DateTime? _rangeEnd;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
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

  List<_TripMock> _filteredTrips(String? statusFilter) {
    var trips = _allTrips.where((t) {
      if (!_hasFilter) return true;
      return t.tripDate.isAfter(_rangeStart!.subtract(const Duration(days: 1))) &&
          t.tripDate.isBefore(_rangeEnd!.add(const Duration(days: 1)));
    });
    if (statusFilter != null) {
      trips = trips.where((t) => t.status == statusFilter);
    }
    return trips.toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: MyShopColors.surfaceWhite,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header + date picker
            Padding(
              padding: const EdgeInsets.fromLTRB(
                MyShopSpacing.md, MyShopSpacing.md, MyShopSpacing.md, 0,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Trips', style: TextStyle(fontFamily: 'Raleway', fontSize: 18, fontWeight: FontWeight.w700, color: MyShopColors.textPrimary)),
                  GestureDetector(
                    onTap: _openDatePicker,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: MyShopColors.offWhite,
                        borderRadius: BorderRadius.circular(17),
                        border: Border.all(color: MyShopColors.divider),
                        boxShadow: const [
                          BoxShadow(color: Color(0x12171A1F), blurRadius: 2.5, offset: Offset(0, 1)),
                        ],
                      ),
                      child: Row(children: [
                        const Icon(Icons.calendar_today, size: 14, color: MyShopColors.darkSlate),
                        const SizedBox(width: 6),
                        Text(_dateLabel, style: MyShopTypography.body2.copyWith(fontWeight: FontWeight.w600, color: MyShopColors.darkSlate, fontSize: 12)),
                      ]),
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
                  boxShadow: const [BoxShadow(color: Color(0x0D000000), blurRadius: 4, offset: Offset(0, 1))],
                ),
                indicatorSize: TabBarIndicatorSize.tab,
                dividerColor: Colors.transparent,
                labelColor: MyShopColors.textPrimary,
                unselectedLabelColor: MyShopColors.textSecondary,
                labelStyle: const TextStyle(fontFamily: 'Raleway', fontSize: 13, fontWeight: FontWeight.w700),
                unselectedLabelStyle: const TextStyle(fontFamily: 'Raleway', fontSize: 13, fontWeight: FontWeight.w400),
                indicatorPadding: const EdgeInsets.all(3),
                tabs: const [Tab(text: 'All'), Tab(text: 'Completed'), Tab(text: 'Cancelled')],
              ),
            ),
            const SizedBox(height: MyShopSpacing.md),

            // Trip list
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  _TripList(trips: _filteredTrips(null)),
                  _TripList(trips: _filteredTrips('Completed')),
                  _TripList(trips: _filteredTrips('Cancelled')),
                ],
              ),
            ),

            // Monthly spending summary
            Container(
              width: double.infinity,
              margin: const EdgeInsets.all(MyShopSpacing.md),
              padding: const EdgeInsets.symmetric(horizontal: MyShopSpacing.md, vertical: 14),
              decoration: BoxDecoration(
                color: MyShopColors.darkSlate,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('MONTHLY SPENDING', style: MyShopTypography.overline.copyWith(fontSize: 9, color: Colors.white54)),
                    const Text('₵146.65', style: TextStyle(fontFamily: 'Raleway', fontSize: 22, fontWeight: FontWeight.w900, color: Colors.white)),
                  ]),
                  // Mini chart representation
                  Row(children: [
                    for (final h in [0.3, 0.5, 0.7, 0.4, 0.6, 0.9, 0.5])
                      Container(
                        width: 8, height: 40 * h,
                        margin: const EdgeInsets.only(left: 3),
                        decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2)),
                      ),
                  ]),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// Mock trip data
final _allTrips = [
  _TripMock(date: 'OCT 24, 2023 · 08:45 AM', tripDate: DateTime(2023, 10, 24), pickup: 'Manhyia Palace', destination: 'Kejetia Market, Kumasi', fare: '₵54.20', duration: '42 mins', status: 'Completed'),
  _TripMock(date: 'OCT 22, 2023 · 10:15 AM', tripDate: DateTime(2023, 10, 22), pickup: 'Baba Yara Stadium', destination: 'KNUST', fare: '₵54.20', duration: '42 mins', status: 'Completed'),
  _TripMock(date: 'OCT 18, 2023 · 02:30 PM', tripDate: DateTime(2023, 10, 18), pickup: 'Baba Yara Stadium', destination: 'KNUST', fare: '₵54.20', duration: '42 mins', status: 'Cancelled'),
];

class _TripMock {
  const _TripMock({required this.date, required this.tripDate, required this.pickup, required this.destination, required this.fare, required this.duration, required this.status});
  final String date;
  final DateTime tripDate;
  final String pickup;
  final String destination;
  final String fare;
  final String duration;
  final String status;
}

class _TripList extends StatelessWidget {
  const _TripList({required this.trips});
  final List<_TripMock> trips;

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.symmetric(horizontal: MyShopSpacing.md),
      itemCount: trips.length,
      separatorBuilder: (_, __) => const SizedBox(height: MyShopSpacing.md),
      itemBuilder: (context, index) => _TripCard(trip: trips[index]),
    );
  }
}

class _TripCard extends StatelessWidget {
  const _TripCard({required this.trip});
  final _TripMock trip;

  void _showDetail(BuildContext context) {
    TripDetailModal.show(
      context,
      TripDetailData(
        tripId: '882941-NY',
        rideId: 'RID-92834',
        status: trip.status,
        date: 'Oct 24, 2023',
        timeRange: '14:20 - 14:45 (25m)',
        pickupTime: '14:20',
        pickupAddress: trip.pickup,
        dropoffTime: '14:45',
        dropoffAddress: trip.destination,
        distanceKm: '8.2 km',
        durationMins: 24,
        surgeMultiplier: '1.2x',
        baseFare: 'GH₵ 12.00',
        distanceFare: 'GH₵ 32.50',
        timeFare: 'GH₵ 6.00',
        surgeFare: 'GH₵ 9.20',
        subtotal: 'GH₵ 59.70',
        taxes: 'GH₵ 1.80',
        promoDiscount: 'GH₵ 5.00',
        totalPaid: 'GH₵ 56.50',
        commission: 'GHS 11.30',
        paymentMethod: 'Cash',
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isCancelled = trip.status == 'Cancelled';

    return GestureDetector(
      onTap: () => _showDetail(context),
      child: Container(
      padding: const EdgeInsets.all(MyShopSpacing.md),
      decoration: BoxDecoration(
        color: MyShopColors.surfaceWhite,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: MyShopColors.divider.withValues(alpha: 0.5)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Date + options
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Row(children: [
            const Icon(Icons.access_time, size: 14, color: MyShopColors.primaryGold),
            const SizedBox(width: 6),
            Text(trip.date, style: MyShopTypography.body2.copyWith(color: MyShopColors.primaryGold, fontWeight: FontWeight.w600, fontSize: 11)),
          ]),
          const Icon(Icons.more_vert, size: 18, color: MyShopColors.textSecondary),
        ]),
        const SizedBox(height: 12),

        // Pickup
        Row(children: [
          Container(width: 8, height: 8, decoration: const BoxDecoration(color: MyShopColors.textSecondary, shape: BoxShape.circle)),
          const SizedBox(width: 10),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('PICKUP', style: MyShopTypography.overline.copyWith(fontSize: 9)),
            Text(trip.pickup, style: const TextStyle(fontFamily: 'Raleway', fontSize: 14, fontWeight: FontWeight.w600, color: MyShopColors.textPrimary)),
          ]),
        ]),
        Container(width: 1, height: 12, margin: const EdgeInsets.only(left: 3.5), color: MyShopColors.divider),

        // Destination
        Row(children: [
          Container(width: 8, height: 8, decoration: BoxDecoration(color: MyShopColors.primaryGold, shape: BoxShape.circle)),
          const SizedBox(width: 10),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('DESTINATION', style: MyShopTypography.overline.copyWith(fontSize: 9, color: MyShopColors.primaryGold)),
            Text(trip.destination, style: const TextStyle(fontFamily: 'Raleway', fontSize: 14, fontWeight: FontWeight.w600, color: MyShopColors.textPrimary)),
          ]),
        ]),
        const SizedBox(height: 12),

        // Fare + Duration + Status
        Row(children: [
          Text(trip.fare, style: const TextStyle(fontFamily: 'Raleway', fontSize: 18, fontWeight: FontWeight.w900, color: MyShopColors.textPrimary)),
          const SizedBox(width: 12),
          const Icon(Icons.navigation, size: 12, color: MyShopColors.textSecondary),
          const SizedBox(width: 4),
          Text(trip.duration, style: MyShopTypography.body2),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: isCancelled ? MyShopColors.errorLight : MyShopColors.surfaceGrey,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: isCancelled ? MyShopColors.error.withValues(alpha: 0.3) : MyShopColors.divider),
            ),
            child: Text(trip.status, style: TextStyle(fontFamily: 'Raleway', fontSize: 11, fontWeight: FontWeight.w700, color: isCancelled ? MyShopColors.error : MyShopColors.textPrimary)),
          ),
        ]),
      ]),
      ),
    );
  }
}
