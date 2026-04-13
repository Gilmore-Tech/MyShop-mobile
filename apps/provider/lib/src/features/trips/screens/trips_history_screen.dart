import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_ui/shared_ui.dart';

import '../widgets/date_range_picker_modal.dart';

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

            // Empty state — no trip history endpoint wired yet
            Expanded(
              child: Center(
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
                      child: const Icon(Icons.directions_car_outlined,
                          size: 28, color: MyShopColors.textSecondary),
                    ),
                    const SizedBox(height: MyShopSpacing.md),
                    Text('No trips yet',
                        style: MyShopTypography.body1.copyWith(
                            fontWeight: FontWeight.w600,
                            color: MyShopColors.textPrimary)),
                    const SizedBox(height: MyShopSpacing.xs),
                    Text('Your completed trips will appear here',
                        style: MyShopTypography.body2.copyWith(
                            color: MyShopColors.textSecondary)),
                  ],
                ),
              ),
            ),

            // Monthly summary — zero state
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
                    Text('MONTHLY EARNINGS', style: MyShopTypography.overline.copyWith(fontSize: 9, color: Colors.white54)),
                    const Text('₵0', style: TextStyle(fontFamily: 'Raleway', fontSize: 22, fontWeight: FontWeight.w900, color: Colors.white)),
                  ]),
                  Row(children: [
                    for (final h in [0.1, 0.1, 0.1, 0.1, 0.1, 0.1, 0.1])
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

