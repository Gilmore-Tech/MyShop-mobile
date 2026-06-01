import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_ui/shared_ui.dart';

/// Date range picker bottom sheet matching Figma design.
///
/// Figma: node 235:15478
///
/// Layout:
///   - "Select Date Range" header + close button
///   - Quick-select chips: Today, Last 7 days, Last 30 days, Custom
///   - Calendar month view with range selection (gold highlight)
///   - FROM / TO display row
///   - "Apply Filter" primary button
///   - "Reset to default" text link
class DateRangePickerModal extends StatefulWidget {
  const DateRangePickerModal({
    super.key,
    required this.initialStart,
    required this.initialEnd,
  });

  final DateTime initialStart;
  final DateTime initialEnd;

  /// Show as a bottom sheet and return the selected range, or null if dismissed.
  static Future<DateTimeRange?> show(
    BuildContext context, {
    required DateTime initialStart,
    required DateTime initialEnd,
  }) {
    return showModalBottomSheet<DateTimeRange>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => DateRangePickerModal(
        initialStart: initialStart,
        initialEnd: initialEnd,
      ),
    );
  }

  @override
  State<DateRangePickerModal> createState() => _DateRangePickerModalState();
}

class _DateRangePickerModalState extends State<DateRangePickerModal> {
  late DateTime _start;
  late DateTime _end;
  late DateTime _viewMonth;
  _QuickOption _activeQuick = _QuickOption.last30;
  // Tracks whether the next day-tap should set the END of the range.
  // After picking a start, the next tap completes the range.
  bool _selectingEnd = false;

  @override
  void initState() {
    super.initState();
    _start = widget.initialStart;
    _end = widget.initialEnd;
    _viewMonth = DateTime(_start.year, _start.month);
  }

  void _selectQuick(_QuickOption option) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    setState(() {
      _activeQuick = option;
      _selectingEnd = false;
      switch (option) {
        case _QuickOption.today:
          _start = today;
          _end = today;
        case _QuickOption.last7:
          _start = today.subtract(const Duration(days: 6));
          _end = today;
        case _QuickOption.last30:
          _start = today.subtract(const Duration(days: 29));
          _end = today;
        case _QuickOption.custom:
          break;
      }
      _viewMonth = DateTime(_start.year, _start.month);
    });
  }

  void _onDayTap(DateTime day) {
    setState(() {
      _activeQuick = _QuickOption.custom;
      if (!_selectingEnd) {
        // First tap: set start, clear end, await second tap
        _start = day;
        _end = day;
        _selectingEnd = true;
      } else {
        // Second tap: set end (or reset start if tapped before current start)
        if (day.isBefore(_start)) {
          _start = day;
          _end = day;
          // Stay in selectingEnd so the next tap can complete the range
        } else {
          _end = day;
          _selectingEnd = false;
        }
      }
    });
  }

  void _prevMonth() {
    setState(() {
      _viewMonth = DateTime(_viewMonth.year, _viewMonth.month - 1);
    });
  }

  void _nextMonth() {
    setState(() {
      _viewMonth = DateTime(_viewMonth.year, _viewMonth.month + 1);
    });
  }

  void _apply() {
    Navigator.of(context).pop(DateTimeRange(start: _start, end: _end));
  }

  void _reset() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    setState(() {
      _activeQuick = _QuickOption.last30;
      _start = today.subtract(const Duration(days: 29));
      _end = today;
      _viewMonth = DateTime(_start.year, _start.month);
    });
  }

  @override
  Widget build(BuildContext context) {
    final maxHeight = MediaQuery.of(context).size.height * 0.9;
    return Container(
      constraints: BoxConstraints(maxHeight: maxHeight),
      decoration: const BoxDecoration(
        color: MyShopColors.surfaceWhite,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Select Date Range',
                    style: TextStyle(
                      fontFamily: 'Raleway',
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      color: MyShopColors.textPrimary,
                    ),
                  ),
                  GestureDetector(
                    onTap: () => Navigator.of(context).pop(),
                    child: const Icon(Icons.close,
                        size: 22, color: MyShopColors.textSecondary),
                  ),
                ],
              ),
              const SizedBox(height: MyShopSpacing.lg),

              // Quick-select chips
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _Chip(
                      label: 'Today',
                      isActive: _activeQuick == _QuickOption.today,
                      onTap: () => _selectQuick(_QuickOption.today)),
                  _Chip(
                      label: 'Last 7 days',
                      isActive: _activeQuick == _QuickOption.last7,
                      onTap: () => _selectQuick(_QuickOption.last7)),
                  _Chip(
                      label: 'Last 30 days',
                      isActive: _activeQuick == _QuickOption.last30,
                      onTap: () => _selectQuick(_QuickOption.last30)),
                  _Chip(
                      label: 'Custom',
                      isActive: _activeQuick == _QuickOption.custom,
                      onTap: () => _selectQuick(_QuickOption.custom)),
                ],
              ),
              const SizedBox(height: MyShopSpacing.lg),

              // Calendar
              _CalendarView(
                viewMonth: _viewMonth,
                start: _start,
                end: _end,
                onDayTap: _onDayTap,
                onPrevMonth: _prevMonth,
                onNextMonth: _nextMonth,
              ),
              const SizedBox(height: MyShopSpacing.lg),

              // FROM / TO row
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('FROM',
                            style: MyShopTypography.overline
                                .copyWith(fontSize: 10, letterSpacing: 0.5)),
                        const SizedBox(height: 4),
                        Text(
                          DateFormat('MMM d, yyyy').format(_start),
                          style: const TextStyle(
                            fontFamily: 'Raleway',
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: MyShopColors.textPrimary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('TO',
                            style: MyShopTypography.overline
                                .copyWith(fontSize: 10, letterSpacing: 0.5)),
                        const SizedBox(height: 4),
                        Text(
                          DateFormat('MMM d, yyyy').format(_end),
                          style: const TextStyle(
                            fontFamily: 'Raleway',
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: MyShopColors.textPrimary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: MyShopSpacing.lg),

              // Apply button
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _apply,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: MyShopColors.darkSlate,
                    foregroundColor: MyShopColors.textOnPrimary,
                    minimumSize: const Size(0, 52),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16)),
                    textStyle: const TextStyle(
                      fontFamily: 'Raleway',
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  child: const Text('Apply Filter'),
                ),
              ),
              const SizedBox(height: MyShopSpacing.sm),

              // Reset link
              Center(
                child: TextButton(
                  onPressed: _reset,
                  child: Text(
                    'Reset to default',
                    style: MyShopTypography.body2.copyWith(
                      color: MyShopColors.textSecondary,
                      decoration: TextDecoration.underline,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: MyShopSpacing.sm),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Quick Option Enum ──────────────────────────────────────────────────────

enum _QuickOption { today, last7, last30, custom }

// ─── Quick Chip ─────────────────────────────────────────────────────────────

class _Chip extends StatelessWidget {
  const _Chip({
    required this.label,
    required this.isActive,
    required this.onTap,
  });

  final String label;
  final bool isActive;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 34,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(
          color:
              isActive ? MyShopColors.primaryGold : MyShopColors.surfaceWhite,
          borderRadius: BorderRadius.circular(17),
          border: Border.all(
            color: isActive ? MyShopColors.primaryGold : MyShopColors.divider,
          ),
        ),
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              fontFamily: 'Raleway',
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: isActive
                  ? MyShopColors.textOnPrimary
                  : MyShopColors.textPrimary,
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Calendar View ──────────────────────────────────────────────────────────

class _CalendarView extends StatelessWidget {
  const _CalendarView({
    required this.viewMonth,
    required this.start,
    required this.end,
    required this.onDayTap,
    required this.onPrevMonth,
    required this.onNextMonth,
  });

  final DateTime viewMonth;
  final DateTime start;
  final DateTime end;
  final ValueChanged<DateTime> onDayTap;
  final VoidCallback onPrevMonth;
  final VoidCallback onNextMonth;

  @override
  Widget build(BuildContext context) {
    final monthLabel = DateFormat('MMMM yyyy').format(viewMonth);
    final firstDay = DateTime(viewMonth.year, viewMonth.month, 1);
    final daysInMonth = DateTime(viewMonth.year, viewMonth.month + 1, 0).day;
    // Sunday = 0 offset in the grid (Figma calendar starts on Sunday)
    final startWeekday = firstDay.weekday % 7;

    return Container(
      padding: const EdgeInsets.all(MyShopSpacing.md),
      decoration: BoxDecoration(
        color: MyShopColors.surfaceGrey,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          // Month nav header
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                monthLabel,
                style: const TextStyle(
                  fontFamily: 'Raleway',
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: MyShopColors.textPrimary,
                ),
              ),
              Row(
                children: [
                  GestureDetector(
                    onTap: onPrevMonth,
                    child: const Icon(Icons.chevron_left,
                        size: 22, color: MyShopColors.textSecondary),
                  ),
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: onNextMonth,
                    child: const Icon(Icons.chevron_right,
                        size: 22, color: MyShopColors.textSecondary),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: MyShopSpacing.md),

          // Day-of-week headers
          Row(
            children: ['S', 'M', 'T', 'W', 'T', 'F', 'S']
                .map((d) => Expanded(
                      child: Center(
                        child: Text(
                          d,
                          style: TextStyle(
                            fontFamily: 'Raleway',
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: MyShopColors.textSecondary,
                          ),
                        ),
                      ),
                    ))
                .toList(),
          ),
          const SizedBox(height: 8),

          // Day grid
          ...List.generate(_rowCount(startWeekday, daysInMonth), (row) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                children: List.generate(7, (col) {
                  final dayIndex = row * 7 + col - startWeekday + 1;
                  if (dayIndex < 1 || dayIndex > daysInMonth) {
                    return const Expanded(child: SizedBox(height: 36));
                  }
                  final date =
                      DateTime(viewMonth.year, viewMonth.month, dayIndex);
                  return Expanded(
                      child: _DayCell(
                    day: dayIndex,
                    date: date,
                    start: start,
                    end: end,
                    onTap: () => onDayTap(date),
                  ));
                }),
              ),
            );
          }),
        ],
      ),
    );
  }

  int _rowCount(int startWeekday, int daysInMonth) {
    return ((startWeekday + daysInMonth + 6) / 7).floor();
  }
}

// ─── Day Cell ───────────────────────────────────────────────────────────────

class _DayCell extends StatelessWidget {
  const _DayCell({
    required this.day,
    required this.date,
    required this.start,
    required this.end,
    required this.onTap,
  });

  final int day;
  final DateTime date;
  final DateTime start;
  final DateTime end;
  final VoidCallback onTap;

  bool get _isStart => _sameDay(date, start);
  bool get _isEnd => _sameDay(date, end);
  bool get _isInRange =>
      date.isAfter(start.subtract(const Duration(days: 1))) &&
      date.isBefore(end.add(const Duration(days: 1)));
  bool get _isEdge => _isStart || _isEnd;

  static bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  @override
  Widget build(BuildContext context) {
    final inRange = _isInRange;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 36,
        decoration: BoxDecoration(
          color: _isEdge
              ? MyShopColors.primaryGold
              : inRange
                  ? MyShopColors.primaryGoldLight
                  : Colors.transparent,
          borderRadius: BorderRadius.horizontal(
            left: _isStart || !inRange ? const Radius.circular(8) : Radius.zero,
            right: _isEnd || !inRange ? const Radius.circular(8) : Radius.zero,
          ),
        ),
        child: Center(
          child: Text(
            '$day',
            style: TextStyle(
              fontFamily: 'Raleway',
              fontSize: 14,
              fontWeight: _isEdge ? FontWeight.w700 : FontWeight.w500,
              color: _isEdge
                  ? MyShopColors.textOnPrimary
                  : MyShopColors.textPrimary,
            ),
          ),
        ),
      ),
    );
  }
}
