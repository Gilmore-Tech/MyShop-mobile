import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_ui/shared_ui.dart';

/// Availability & Schedule — artisan weekly availability, shift hours,
/// and smart dispatching preferences.
///
/// PRD Reference: PRD 5.3 — provider availability & dispatch settings.
class AvailabilityScheduleScreen extends StatefulWidget {
  const AvailabilityScheduleScreen({super.key});

  @override
  State<AvailabilityScheduleScreen> createState() =>
      _AvailabilityScheduleScreenState();
}

class _AvailabilityScheduleScreenState
    extends State<AvailabilityScheduleScreen> {
  bool _systemOnline = true;
  bool _autoAccept = true;
  bool _shiftReminders = false;
  bool _quietMode = true;

  // Index 0 = Mon … 6 = Sun
  final Set<int> _activeDays = {0, 1, 2, 3, 4};

  static const _dayNames = [
    'Monday',
    'Tuesday',
    'Wednesday',
    'Thursday',
    'Friday',
    'Saturday',
    'Sunday',
  ];

  // Each day's shift hours. Stored even when the day is inactive so the user
  // can re-enable it without losing their previously set times.
  final Map<int, _ShiftHours> _hoursByDay = {
    0: const _ShiftHours(
        start: TimeOfDay(hour: 8, minute: 0),
        end: TimeOfDay(hour: 17, minute: 0)),
    1: const _ShiftHours(
        start: TimeOfDay(hour: 8, minute: 0),
        end: TimeOfDay(hour: 17, minute: 0)),
    2: const _ShiftHours(
        start: TimeOfDay(hour: 8, minute: 0),
        end: TimeOfDay(hour: 14, minute: 0)),
    3: const _ShiftHours(
        start: TimeOfDay(hour: 8, minute: 0),
        end: TimeOfDay(hour: 17, minute: 0)),
    4: const _ShiftHours(
        start: TimeOfDay(hour: 9, minute: 0),
        end: TimeOfDay(hour: 18, minute: 0)),
    5: const _ShiftHours(
        start: TimeOfDay(hour: 9, minute: 0),
        end: TimeOfDay(hour: 17, minute: 0)),
    6: const _ShiftHours(
        start: TimeOfDay(hour: 9, minute: 0),
        end: TimeOfDay(hour: 17, minute: 0)),
  };

  Future<void> _editShift(int dayIndex) async {
    final current = _hoursByDay[dayIndex]!;

    final start = await showTimePicker(
      context: context,
      initialTime: current.start,
      helpText: 'START — ${_dayNames[dayIndex].toUpperCase()}',
    );
    if (start == null || !mounted) return;

    final end = await showTimePicker(
      context: context,
      initialTime: current.end,
      helpText: 'END — ${_dayNames[dayIndex].toUpperCase()}',
    );
    if (end == null || !mounted) return;

    setState(() {
      _hoursByDay[dayIndex] = _ShiftHours(start: start, end: end);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: MyShopColors.surfaceWhite,
      body: SafeArea(
        child: Column(
          children: [
            _Header(),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(
                  MyShopSpacing.md,
                  MyShopSpacing.md,
                  MyShopSpacing.md,
                  MyShopSpacing.lg,
                ),
                children: [
                  _CurrentStatusCard(
                    online: _systemOnline,
                    onChanged: (v) => setState(() => _systemOnline = v),
                  ),
                  const SizedBox(height: MyShopSpacing.lg),
                  Row(
                    children: [
                      const Icon(
                        Icons.calendar_today_outlined,
                        size: 12,
                        color: MyShopColors.textPrimary,
                      ),
                      const SizedBox(width: MyShopSpacing.sm),
                      Expanded(
                        child: Text(
                          'Weekly Work Days',
                          style: MyShopTypography.h2.copyWith(
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      GestureDetector(
                        onTap: () => setState(() {
                          _activeDays
                            ..clear()
                            ..addAll({0, 1, 2, 3, 4});
                        }),
                        child: Text(
                          'Reset to Default',
                          style: MyShopTypography.body2.copyWith(
                            color: MyShopColors.primaryGold,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: MyShopSpacing.md),
                  _DayChipRow(
                    activeDays: _activeDays,
                    onToggle: (i) => setState(() {
                      if (_activeDays.contains(i)) {
                        _activeDays.remove(i);
                      } else {
                        _activeDays.add(i);
                      }
                    }),
                  ),
                  const SizedBox(height: MyShopSpacing.lg),
                  _StandardShiftsCard(
                    dayNames: _dayNames,
                    activeDays: _activeDays,
                    hoursByDay: _hoursByDay,
                    onEdit: _editShift,
                  ),
                  const SizedBox(height: MyShopSpacing.lg),
                  Row(
                    children: [
                      const Icon(
                        Icons.flash_on,
                        size: 12,
                        color: MyShopColors.primaryGold,
                      ),
                      const SizedBox(width: MyShopSpacing.sm),
                      Text(
                        'Smart Dispatching',
                        style: MyShopTypography.h2.copyWith(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: MyShopSpacing.md),
                  _SmartDispatchingCard(
                    autoAccept: _autoAccept,
                    shiftReminders: _shiftReminders,
                    quietMode: _quietMode,
                    onAutoAccept: (v) => setState(() => _autoAccept = v),
                    onShiftReminders: (v) =>
                        setState(() => _shiftReminders = v),
                    onQuietMode: (v) => setState(() => _quietMode = v),
                  ),
                  const SizedBox(height: MyShopSpacing.lg),
                  const _SupportFooter(),
                ],
              ),
            ),
            _SaveFooter(onTap: () {}),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Header
// ─────────────────────────────────────────────────────────────────────────────

class _Header extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(
        MyShopSpacing.sm,
        MyShopSpacing.sm,
        MyShopSpacing.md,
        MyShopSpacing.md,
      ),
      decoration: const BoxDecoration(
        color: MyShopColors.surfaceWhite,
        border: Border(bottom: BorderSide(color: MyShopColors.divider)),
      ),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back, color: MyShopColors.textPrimary),
            onPressed: () => context.pop(),
          ),
          Expanded(
            child: Text(
              'Availability & Schedule',
              style: MyShopTypography.h1.copyWith(
                fontWeight: FontWeight.w700,
                fontSize: 18,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Current status card
// ─────────────────────────────────────────────────────────────────────────────

class _CurrentStatusCard extends StatelessWidget {
  const _CurrentStatusCard({required this.online, required this.onChanged});

  final bool online;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(MyShopSpacing.md),
      decoration: BoxDecoration(
        color: MyShopColors.offWhite,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: const BoxDecoration(
                      color: MyShopColors.surfaceGrey,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.wb_sunny_outlined,
                      size: 22,
                      color: MyShopColors.textPrimary,
                    ),
                  ),
                  Positioned(
                    right: 0,
                    bottom: 0,
                    child: Container(
                      width: 11,
                      height: 11,
                      decoration: BoxDecoration(
                        color: online
                            ? MyShopColors.online
                            : MyShopColors.disabled,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: MyShopColors.surfaceWhite,
                          width: 1.5,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(width: MyShopSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Current Status',
                      style: MyShopTypography.h3.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      online ? 'SYSTEM ONLINE' : 'SYSTEM OFFLINE',
                      style: MyShopTypography.overline.copyWith(
                        color: MyShopColors.textSecondary,
                        fontWeight: FontWeight.w800,
                        fontSize: 11,
                        letterSpacing: 1.0,
                      ),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  _GoldSwitch(value: online, onChanged: onChanged),
                  const SizedBox(height: 4),
                  Text(
                    online ? 'VISIBLE' : 'HIDDEN',
                    style: MyShopTypography.overline.copyWith(
                      color: MyShopColors.primaryGold,
                      fontWeight: FontWeight.w900,
                      fontSize: 10,
                      letterSpacing: 0.8,
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: MyShopSpacing.md),
          Container(
            padding: const EdgeInsets.all(MyShopSpacing.sm + 2),
            decoration: BoxDecoration(
              color: MyShopColors.surfaceWhite,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.info_outline,
                  size: 16,
                  color: MyShopColors.textSecondary,
                ),
                const SizedBox(width: MyShopSpacing.sm),
                Expanded(
                  child: Text(
                    'You are currently receiving job requests. Your response rate is 98.4%.',
                    style: MyShopTypography.body2.copyWith(height: 1.5),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Day chip row
// ─────────────────────────────────────────────────────────────────────────────

class _DayChipRow extends StatelessWidget {
  const _DayChipRow({required this.activeDays, required this.onToggle});

  final Set<int> activeDays;
  final ValueChanged<int> onToggle;

  static const _labels = ['MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT', 'SUN'];
  static const _letters = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (int i = 0; i < 7; i++) ...[
          Expanded(
            child: _DayChip(
              label: _labels[i],
              letter: _letters[i],
              active: activeDays.contains(i),
              showDot: i == 2 && activeDays.contains(i),
              onTap: () => onToggle(i),
            ),
          ),
          if (i < 6) const SizedBox(width: 6),
        ],
      ],
    );
  }
}

class _DayChip extends StatelessWidget {
  const _DayChip({
    required this.label,
    required this.letter,
    required this.active,
    required this.showDot,
    required this.onTap,
  });

  final String label;
  final String letter;
  final bool active;
  final bool showDot;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: active ? MyShopColors.darkSlate : MyShopColors.surfaceWhite,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: active ? MyShopColors.darkSlate : MyShopColors.divider,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: MyShopTypography.caption.copyWith(
                color: active
                    ? MyShopColors.textOnDarkSlate.withValues(alpha: 0.75)
                    : MyShopColors.textSecondary,
                fontWeight: FontWeight.w800,
                fontSize: 10,
                letterSpacing: 0.6,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              letter,
              style: TextStyle(
                fontFamily: 'Raleway',
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: active
                    ? MyShopColors.textOnDarkSlate
                    : MyShopColors.textPrimary,
              ),
            ),
            const SizedBox(height: 4),
            Container(
              width: 4,
              height: 4,
              decoration: BoxDecoration(
                color: showDot ? MyShopColors.primaryGold : Colors.transparent,
                shape: BoxShape.circle,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Standard shifts card
// ─────────────────────────────────────────────────────────────────────────────

class _ShiftHours {
  const _ShiftHours({required this.start, required this.end});

  final TimeOfDay start;
  final TimeOfDay end;

  String formatRange(BuildContext context) =>
      '${start.format(context)} - ${end.format(context)}';
}

class _StandardShiftsCard extends StatelessWidget {
  const _StandardShiftsCard({
    required this.dayNames,
    required this.activeDays,
    required this.hoursByDay,
    required this.onEdit,
  });

  final List<String> dayNames;
  final Set<int> activeDays;
  final Map<int, _ShiftHours> hoursByDay;
  final ValueChanged<int> onEdit;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(MyShopSpacing.md),
      decoration: BoxDecoration(
        color: MyShopColors.surfaceWhite,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: MyShopColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'STANDARD SHIFTS',
            style: MyShopTypography.overline.copyWith(
              color: MyShopColors.textPrimary,
              fontWeight: FontWeight.w900,
              fontSize: 12,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Tap an active day to edit its hours. Toggle days above to enable or disable.',
            style: MyShopTypography.body2,
          ),
          const SizedBox(height: MyShopSpacing.md),
          for (int i = 0; i < dayNames.length; i++) ...[
            _ShiftRow(
              dayName: dayNames[i],
              hours: hoursByDay[i]!,
              isActive: activeDays.contains(i),
              onEdit: () => onEdit(i),
            ),
            if (i < dayNames.length - 1)
              const Divider(height: 1, color: MyShopColors.divider),
          ],
        ],
      ),
    );
  }
}

class _ShiftRow extends StatelessWidget {
  const _ShiftRow({
    required this.dayName,
    required this.hours,
    required this.isActive,
    required this.onEdit,
  });

  final String dayName;
  final _ShiftHours hours;
  final bool isActive;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: isActive ? onEdit : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: MyShopSpacing.md),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: MyShopColors.surfaceGrey,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                Icons.access_time,
                size: 20,
                color:
                    isActive ? MyShopColors.textPrimary : MyShopColors.disabled,
              ),
            ),
            const SizedBox(width: MyShopSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    dayName,
                    style: MyShopTypography.h3.copyWith(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: isActive
                          ? MyShopColors.textPrimary
                          : MyShopColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    isActive ? hours.formatRange(context) : 'Unavailable',
                    style: MyShopTypography.body2.copyWith(
                      color: isActive
                          ? MyShopColors.textSecondary
                          : MyShopColors.error,
                      fontWeight: isActive ? FontWeight.w400 : FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
            if (isActive) ...[
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: MyShopColors.surfaceWhite,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: MyShopColors.divider),
                ),
                child: Text(
                  'Shift 1',
                  style: MyShopTypography.body2.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(width: 4),
            ],
            IconButton(
              icon: const Icon(
                Icons.more_horiz,
                color: MyShopColors.textSecondary,
                size: 20,
              ),
              onPressed: () {},
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Smart dispatching card
// ─────────────────────────────────────────────────────────────────────────────

class _SmartDispatchingCard extends StatelessWidget {
  const _SmartDispatchingCard({
    required this.autoAccept,
    required this.shiftReminders,
    required this.quietMode,
    required this.onAutoAccept,
    required this.onShiftReminders,
    required this.onQuietMode,
  });

  final bool autoAccept;
  final bool shiftReminders;
  final bool quietMode;
  final ValueChanged<bool> onAutoAccept;
  final ValueChanged<bool> onShiftReminders;
  final ValueChanged<bool> onQuietMode;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(MyShopSpacing.md),
      decoration: BoxDecoration(
        color: MyShopColors.surfaceWhite,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: MyShopColors.divider),
      ),
      child: Column(
        children: [
          _DispatchRow(
            iconBg: MyShopColors.primaryGold,
            icon: Icons.flash_on,
            iconColor: MyShopColors.textOnPrimary,
            title: 'Auto-accept Jobs',
            subtitle:
                'Instantly accept jobs that match your preferred price and distance range.',
            value: autoAccept,
            onChanged: onAutoAccept,
          ),
          const Divider(height: 1, color: MyShopColors.divider),
          _DispatchRow(
            iconBg: MyShopColors.surfaceGrey,
            icon: Icons.notifications_none,
            iconColor: MyShopColors.textPrimary,
            title: 'Shift Reminders',
            subtitle:
                'Get notified 15 minutes before your scheduled shift begins.',
            value: shiftReminders,
            onChanged: onShiftReminders,
          ),
          const Divider(height: 1, color: MyShopColors.divider),
          _DispatchRow(
            iconBg: MyShopColors.darkSlate,
            icon: Icons.nightlight_outlined,
            iconColor: MyShopColors.textOnDarkSlate,
            title: 'Quiet Mode',
            subtitle:
                'Silence non-urgent notifications during your scheduled off-hours.',
            value: quietMode,
            onChanged: onQuietMode,
          ),
        ],
      ),
    );
  }
}

class _DispatchRow extends StatelessWidget {
  const _DispatchRow({
    required this.iconBg,
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final Color iconBg;
  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: MyShopSpacing.md),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: iconBg,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 22, color: iconColor),
          ),
          const SizedBox(width: MyShopSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: MyShopTypography.h3.copyWith(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: MyShopTypography.body2.copyWith(height: 1.45),
                ),
              ],
            ),
          ),
          const SizedBox(width: MyShopSpacing.sm),
          _GoldSwitch(value: value, onChanged: onChanged),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Gold switch (custom styled toggle)
// ─────────────────────────────────────────────────────────────────────────────

class _GoldSwitch extends StatelessWidget {
  const _GoldSwitch({required this.value, required this.onChanged});

  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Switch.adaptive(
      value: value,
      onChanged: onChanged,
      activeThumbColor: Colors.white,
      activeTrackColor: MyShopColors.primaryGold,
      inactiveThumbColor: Colors.white,
      inactiveTrackColor: MyShopColors.divider,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Support footer
// ─────────────────────────────────────────────────────────────────────────────

class _SupportFooter extends StatelessWidget {
  const _SupportFooter();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: MyShopColors.surfaceWhite,
            shape: BoxShape.circle,
            border: Border.all(color: MyShopColors.divider),
          ),
          child: const Icon(
            Icons.info_outline,
            size: 18,
            color: MyShopColors.textSecondary,
          ),
        ),
        const SizedBox(height: MyShopSpacing.sm),
        Text(
          'Need a flexible schedule? Contact support to apply for a custom artisan arrangement.',
          textAlign: TextAlign.center,
          style: MyShopTypography.body2.copyWith(height: 1.5),
        ),
        const SizedBox(height: 6),
        GestureDetector(
          onTap: () {},
          child: Text(
            'Get Help',
            style: MyShopTypography.body1.copyWith(
              color: MyShopColors.textPrimary,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Save footer
// ─────────────────────────────────────────────────────────────────────────────

class _SaveFooter extends StatelessWidget {
  const _SaveFooter({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.fromLTRB(
        MyShopSpacing.md,
        MyShopSpacing.md,
        MyShopSpacing.md,
        MyShopSpacing.md + MediaQuery.of(context).padding.bottom * 0.2,
      ),
      decoration: const BoxDecoration(
        color: MyShopColors.surfaceWhite,
        border: Border(top: BorderSide(color: MyShopColors.divider)),
      ),
      child: Column(
        children: [
          GestureDetector(
            onTap: onTap,
            child: Container(
              height: 56,
              width: double.infinity,
              decoration: BoxDecoration(
                color: MyShopColors.darkSlate,
                borderRadius: BorderRadius.circular(28),
              ),
              alignment: Alignment.center,
              child: Text(
                'Save Schedule',
                style: MyShopTypography.button.copyWith(
                  color: MyShopColors.textOnDarkSlate,
                  fontWeight: FontWeight.w800,
                  fontSize: 15,
                ),
              ),
            ),
          ),
          const SizedBox(height: MyShopSpacing.sm),
          Text(
            'Last updated: Today at 09:42 AM',
            style: MyShopTypography.body2,
          ),
        ],
      ),
    );
  }
}
