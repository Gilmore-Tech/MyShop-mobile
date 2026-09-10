import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_ui/shared_ui.dart';

String formatPromoDateTime(DateTime value) =>
    DateFormat('d MMM yyyy, h:mm a').format(value.toLocal());

String? promoCountdownLabel({
  required DateTime now,
  DateTime? startsAt,
  DateTime? endsAt,
}) {
  final localNow = now.toLocal();
  final localStart = startsAt?.toLocal();
  final localEnd = endsAt?.toLocal();

  if (localStart != null && localNow.isBefore(localStart)) {
    return 'Starts in ${_durationLabel(localStart.difference(localNow))}';
  }
  if (localEnd != null && localNow.isBefore(localEnd)) {
    return '${_durationLabel(localEnd.difference(localNow))} left';
  }
  if (localEnd != null) return 'Ended';
  return null;
}

String _durationLabel(Duration duration) {
  final seconds = duration.inSeconds.clamp(0, 1 << 31);
  final days = seconds ~/ Duration.secondsPerDay;
  final hours = (seconds % Duration.secondsPerDay) ~/ Duration.secondsPerHour;
  final minutes =
      (seconds % Duration.secondsPerHour) ~/ Duration.secondsPerMinute;
  final remainingSeconds = seconds % Duration.secondsPerMinute;

  if (days > 0) return '${days}d ${hours}h ${minutes}m';
  if (hours > 0) return '${hours}h ${minutes}m';
  if (minutes > 0) return '${minutes}m ${remainingSeconds}s';
  return '${remainingSeconds}s';
}

class PromoCountdownLabel extends StatefulWidget {
  const PromoCountdownLabel({
    super.key,
    this.startsAt,
    this.endsAt,
    this.compact = false,
  });

  final DateTime? startsAt;
  final DateTime? endsAt;
  final bool compact;

  @override
  State<PromoCountdownLabel> createState() => _PromoCountdownLabelState();
}

class _PromoCountdownLabelState extends State<PromoCountdownLabel> {
  Timer? _timer;
  DateTime _now = DateTime.now();

  @override
  void initState() {
    super.initState();
    _scheduleTick();
  }

  @override
  void didUpdateWidget(covariant PromoCountdownLabel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.startsAt != widget.startsAt ||
        oldWidget.endsAt != widget.endsAt) {
      _now = DateTime.now();
      _scheduleTick();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _scheduleTick() {
    _timer?.cancel();
    final boundary = _nextBoundary;
    if (boundary == null || !_now.isBefore(boundary)) return;
    final remaining = boundary.difference(_now);
    final interval = remaining <= const Duration(hours: 1)
        ? const Duration(seconds: 1)
        : const Duration(minutes: 1);
    _timer = Timer(interval, () {
      if (!mounted) return;
      setState(() => _now = DateTime.now());
      _scheduleTick();
    });
  }

  DateTime? get _nextBoundary {
    final start = widget.startsAt;
    if (start != null && _now.isBefore(start)) return start;
    return widget.endsAt;
  }

  @override
  Widget build(BuildContext context) {
    final label = promoCountdownLabel(
      now: _now,
      startsAt: widget.startsAt,
      endsAt: widget.endsAt,
    );
    if (label == null) return const SizedBox.shrink();

    final ended = label == 'Ended';
    final colour =
        ended ? MyShopColors.textSecondary : MyShopColors.primaryGoldDark;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          ended ? Icons.event_busy_rounded : Icons.timer_outlined,
          size: widget.compact ? 14 : 16,
          color: colour,
        ),
        const SizedBox(width: 5),
        Flexible(
          child: Text(
            label,
            key: const Key('promo-countdown-label'),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: colour,
              fontSize: widget.compact ? 12 : 14,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ],
    );
  }
}
