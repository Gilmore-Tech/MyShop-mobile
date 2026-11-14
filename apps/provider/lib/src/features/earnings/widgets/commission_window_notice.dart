import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_models/shared_models.dart';
import 'package:shared_ui/shared_ui.dart';

class CommissionWindowNotice extends StatefulWidget {
  const CommissionWindowNotice({super.key, required this.window});

  final CommissionPaymentWindow window;

  @override
  State<CommissionWindowNotice> createState() => _CommissionWindowNoticeState();
}

class _CommissionWindowNoticeState extends State<CommissionWindowNotice> {
  Timer? _deadlineTimer;

  @override
  void initState() {
    super.initState();
    _scheduleDeadline();
  }

  @override
  void didUpdateWidget(CommissionWindowNotice oldWidget) {
    super.didUpdateWidget(oldWidget);
    _scheduleDeadline();
  }

  void _scheduleDeadline() {
    _deadlineTimer?.cancel();
    final remaining = widget.window.dueAt.difference(DateTime.now());
    if (remaining > Duration.zero) {
      _deadlineTimer = Timer(remaining, () {
        if (mounted) setState(() {});
      });
    }
  }

  @override
  void dispose() {
    _deadlineTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final window = widget.window;
    final overdue = window.overdue || !DateTime.now().isBefore(window.dueAt);
    final localDue = window.dueAt.toLocal();
    final localizations = MaterialLocalizations.of(context);
    final deadline = '${localizations.formatFullDate(localDue)} at '
        '${localizations.formatTimeOfDay(TimeOfDay.fromDateTime(localDue))}';
    final amount = (window.outstandingPesewas / 100).toStringAsFixed(2);
    return Semantics(
      liveRegion: true,
      child: Container(
        key: const Key('commission-window-notice'),
        padding: const EdgeInsets.all(MyShopSpacing.md),
        decoration: BoxDecoration(
          color: MyShopColors.surfaceGrey,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          overdue
              ? 'Your ${window.windowHours}-hour commission payment window has ended. '
                  'Pay all GH₵ $amount owed before going online or accepting new work.'
              : 'Commission payment due: $deadline. '
                  'Pay all GH₵ $amount owed within your ${window.windowHours}-hour window '
                  'to keep access to new work. Partial payments do not extend the deadline.',
          style: TextStyle(
            color: overdue ? MyShopColors.error : MyShopColors.textPrimary,
            fontSize: 14,
          ),
        ),
      ),
    );
  }
}
