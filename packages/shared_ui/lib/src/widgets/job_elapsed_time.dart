import 'dart:async';

import 'package:flutter/material.dart';

import '../theme/myshop_colors.dart';
import '../theme/myshop_radius.dart';
import '../theme/myshop_spacing.dart';
// Radius token: jobs use the standard `card` radius for surface chips so
// the elapsed-time pill matches the rest of the active-job panel.
import '../theme/myshop_typography.dart';

/// Live elapsed-time display for an in-progress job — shows
/// `HH:MM:SS` (or `MM:SS` under an hour) ticking once per second from
/// [startedAt]. When [endedAt] is non-null the timer freezes at the
/// final duration; this is what the completion summary reads.
///
/// The widget is timestamp-driven, not duration-driven: passing the
/// absolute `startedAt` (rather than a running counter) makes it
/// resilient to backgrounding and rebuilds — every tick recomputes
/// `now - startedAt` from scratch, so the user sees the correct elapsed
/// time even after the OS pauses the app for a minute and re-mounts it.
///
/// Returns an empty `SizedBox` if [startedAt] is null. That's the
/// default state until the backend stamps `started_at` on the job, so
/// callers can drop this widget directly into the layout without a
/// surrounding `if (job.startedAt != null)` guard.
class JobElapsedTime extends StatefulWidget {
  const JobElapsedTime({
    super.key,
    required this.startedAt,
    this.endedAt,
    this.label = 'Time on job',
    this.compact = false,
  });

  /// When work began. Null = no timer to show; the widget renders a
  /// zero-size box so it can sit conditionally in any layout.
  final DateTime? startedAt;

  /// When work ended. Non-null freezes the displayed duration at
  /// `endedAt - startedAt` and stops the ticker. Used by the
  /// completion summary to show the final on-the-job time.
  final DateTime? endedAt;

  /// Caption above the time (e.g. "Time on job", "Final duration").
  final String label;

  /// Compact mode drops the surrounding card and renders a single
  /// inline `label · 00:12:34` row — useful inside narrow rows like
  /// the client's tracking bottom-sheet pill.
  final bool compact;

  @override
  State<JobElapsedTime> createState() => _JobElapsedTimeState();
}

class _JobElapsedTimeState extends State<JobElapsedTime> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _maybeStartTicker();
  }

  @override
  void didUpdateWidget(covariant JobElapsedTime oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Restart the ticker if the start/end timestamps changed — a fresh
    // job in the same screen mount, or the job just settled and the
    // ticker should freeze.
    if (oldWidget.startedAt != widget.startedAt ||
        oldWidget.endedAt != widget.endedAt) {
      _timer?.cancel();
      _timer = null;
      _maybeStartTicker();
    }
  }

  void _maybeStartTicker() {
    // Only tick while the work is ongoing — once `endedAt` is set, the
    // displayed duration is fixed, so a periodic rebuild is wasted work.
    if (widget.startedAt == null || widget.endedAt != null) return;
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() {});
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Duration get _elapsed {
    final start = widget.startedAt;
    if (start == null) return Duration.zero;
    final end = widget.endedAt ?? DateTime.now();
    final delta = end.difference(start);
    // Guard against clock skew where `now` is briefly before `startedAt`
    // (device clock drift / NTP sync). Negative durations would render
    // as "-01:23" which is alarming.
    return delta.isNegative ? Duration.zero : delta;
  }

  String _format(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    if (h > 0) return '${h.toString().padLeft(2, '0')}:$m:$s';
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    if (widget.startedAt == null) return const SizedBox.shrink();
    final time = _format(_elapsed);
    final isFrozen = widget.endedAt != null;

    if (widget.compact) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isFrozen ? Icons.check_circle_outline : Icons.timer_outlined,
            size: 16,
            color: isFrozen ? MyShopColors.success : MyShopColors.primaryGold,
          ),
          const SizedBox(width: 6),
          Text(
            widget.label,
            style: MyShopTypography.body2.copyWith(
              color: MyShopColors.textSecondary,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            time,
            style: MyShopTypography.body1.copyWith(
              color: MyShopColors.textPrimary,
              fontWeight: FontWeight.w800,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      );
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: MyShopSpacing.md,
        vertical: MyShopSpacing.sm + 2,
      ),
      decoration: BoxDecoration(
        color: isFrozen
            ? MyShopColors.success.withValues(alpha: 0.10)
            : MyShopColors.primaryGold.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(MyShopRadius.card),
        border: Border.all(
          color: (isFrozen ? MyShopColors.success : MyShopColors.primaryGold)
              .withValues(alpha: 0.25),
        ),
      ),
      child: Row(
        children: [
          Icon(
            isFrozen ? Icons.check_circle_outline : Icons.timer_outlined,
            size: 18,
            color: isFrozen ? MyShopColors.success : MyShopColors.primaryGold,
          ),
          const SizedBox(width: MyShopSpacing.sm),
          Expanded(
            child: Text(
              widget.label,
              style: MyShopTypography.overline.copyWith(
                color: MyShopColors.textSecondary,
              ),
            ),
          ),
          Text(
            time,
            style: MyShopTypography.h3.copyWith(
              color: MyShopColors.textPrimary,
              fontWeight: FontWeight.w800,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}
