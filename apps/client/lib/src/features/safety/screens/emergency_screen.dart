import 'package:flutter/material.dart';
import 'package:shared_ui/shared_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

// ── Screen ─────────────────────────────────────────────────────────────────────
// PRD § 4.10 — Two-step SOS confirmation to prevent accidental triggers.
// Step 1: hold-to-confirm button (3 s press).
// Step 2: confirm dialog → calls 191 (Ghana Police) + notifies emergency contacts.
// EDD: POST /v1/safety/sos  { bookingId?, location }
//      Auto-dials 191 via url_launcher.

class EmergencyScreen extends ConsumerStatefulWidget {
  const EmergencyScreen({super.key});

  @override
  ConsumerState<EmergencyScreen> createState() => _EmergencyScreenState();
}

class _EmergencyScreenState extends ConsumerState<EmergencyScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _holdCtrl;
  bool _sosTriggered = false;
  bool _isSending    = false;

  @override
  void initState() {
    super.initState();
    _holdCtrl = AnimationController(
      vsync:    this,
      duration: const Duration(seconds: 3),
    )..addStatusListener((s) {
        if (s == AnimationStatus.completed) _onHoldComplete();
      });
  }

  @override
  void dispose() {
    _holdCtrl.dispose();
    super.dispose();
  }

  void _onHoldStart()    => _holdCtrl.forward();
  void _onHoldCancel()   => _holdCtrl.reverse();
  void _onHoldComplete() => _showConfirmDialog();

  void _showConfirmDialog() {
    _holdCtrl.reset();
    showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _ConfirmDialog(
        w: MediaQuery.sizeOf(context).width,
        onConfirm: _triggerSos,
        onCancel:  () => Navigator.pop(context),
      ),
    );
  }

  Future<void> _triggerSos() async {
    Navigator.pop(context); // close dialog
    setState(() { _isSending = true; });
    // TODO: POST /v1/safety/sos { location }
    // TODO: url_launcher → tel:191
    await Future.delayed(const Duration(milliseconds: 800));
    if (!mounted) return;
    setState(() { _isSending = false; _sosTriggered = true; });
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final w    = size.width;
    final h    = size.height;
    final top  = MediaQuery.paddingOf(context).top;
    final bot  = MediaQuery.paddingOf(context).bottom;

    return Scaffold(
      backgroundColor: MyShopColors.offWhite,
      body: Column(
        children: [
          // Header
          Container(
            color:   MyShopColors.surfaceWhite,
            padding: EdgeInsets.only(top: top),
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.close_rounded, color: MyShopColors.textPrimary),
                  onPressed: () => context.pop(),
                ),
                Text('Emergency',
                    style: TextStyle(
                      color:      MyShopColors.textPrimary,
                      fontSize:   w * 0.044,
                      fontWeight: FontWeight.w700,
                    )),
              ],
            ),
          ),
          Expanded(
            child: _sosTriggered
                ? _SentState(w: w, h: h, bot: bot,
                    onDone: () => context.pop())
                : _HoldState(
                    w:          w,
                    h:          h,
                    bot:        bot,
                    holdCtrl:   _holdCtrl,
                    isSending:  _isSending,
                    onStart:    _onHoldStart,
                    onCancel:   _onHoldCancel,
                  ),
          ),
        ],
      ),
    );
  }
}

// ── Hold state ─────────────────────────────────────────────────────────────────

class _HoldState extends StatelessWidget {
  final double             w, h, bot;
  final AnimationController holdCtrl;
  final bool               isSending;
  final VoidCallback       onStart;
  final VoidCallback       onCancel;

  const _HoldState({
    required this.w,
    required this.h,
    required this.bot,
    required this.holdCtrl,
    required this.isSending,
    required this.onStart,
    required this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
          w * 0.07, h * 0.04, w * 0.07, bot + h * 0.04),
      child: Column(
        children: [
          // Info panel
          Container(
            padding: EdgeInsets.all(w * 0.04),
            decoration: BoxDecoration(
              color:        MyShopColors.errorLight,
              borderRadius: BorderRadius.circular(12),
              border:       Border.all(color: MyShopColors.error.withAlpha(60)),
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    const Icon(Icons.warning_amber_rounded,
                        color: MyShopColors.error, size: 22),
                    SizedBox(width: w * 0.024),
                    Expanded(
                      child: Text('Use in genuine emergencies only',
                          style: TextStyle(
                            color:      MyShopColors.error,
                            fontSize:   w * 0.036,
                            fontWeight: FontWeight.w700,
                          )),
                    ),
                  ],
                ),
                SizedBox(height: h * 0.010),
                Text(
                  'Triggering SOS will call 191 (Ghana Police), share your '
                  'live location, and alert your emergency contacts.',
                  style: TextStyle(
                      color:    MyShopColors.error.withAlpha(180),
                      fontSize: w * 0.031,
                      height:   1.5),
                ),
              ],
            ),
          ),
          const Spacer(),
          // Hold button
          Text('Hold for 3 seconds to trigger SOS',
              textAlign: TextAlign.center,
              style: TextStyle(
                  color:    MyShopColors.textSecondary,
                  fontSize: w * 0.034)),
          SizedBox(height: h * 0.032),
          AnimatedBuilder(
            animation: holdCtrl,
            builder: (_, __) {
              return GestureDetector(
                onTapDown:  (_) => onStart(),
                onTapUp:    (_) => onCancel(),
                onTapCancel: onCancel,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    SizedBox(
                      width:  w * 0.50,
                      height: w * 0.50,
                      child: CircularProgressIndicator(
                        value:      holdCtrl.value,
                        strokeWidth: 6,
                        color:      MyShopColors.error,
                        backgroundColor: MyShopColors.error.withAlpha(30),
                      ),
                    ),
                    Container(
                      width:  w * 0.42,
                      height: w * 0.42,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: holdCtrl.value > 0
                            ? MyShopColors.error
                            : MyShopColors.errorLight,
                        border: Border.all(
                            color: MyShopColors.error, width: 2),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.sos_rounded,
                              color: holdCtrl.value > 0
                                  ? Colors.white
                                  : MyShopColors.error,
                              size: w * 0.092),
                          const SizedBox(height: 4),
                          Text('SOS',
                              style: TextStyle(
                                color:      holdCtrl.value > 0
                                    ? Colors.white
                                    : MyShopColors.error,
                                fontSize:   w * 0.040,
                                fontWeight: FontWeight.w900,
                              )),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
          const Spacer(),
          // Quick-dial row
          _QuickDialRow(w: w, h: h),
        ],
      ),
    );
  }
}

// ── Confirm dialog ─────────────────────────────────────────────────────────────

class _ConfirmDialog extends StatelessWidget {
  final double       w;
  final VoidCallback onConfirm;
  final VoidCallback onCancel;

  const _ConfirmDialog({
    required this.w,
    required this.onConfirm,
    required this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16)),
      contentPadding: EdgeInsets.all(w * 0.05),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: EdgeInsets.all(w * 0.04),
            decoration: const BoxDecoration(
                color: MyShopColors.errorLight, shape: BoxShape.circle),
            child: const Icon(Icons.sos_rounded,
                color: MyShopColors.error, size: 40),
          ),
          SizedBox(height: w * 0.040),
          Text('Trigger SOS?',
              style: TextStyle(
                color:      MyShopColors.textPrimary,
                fontSize:   w * 0.048,
                fontWeight: FontWeight.w800,
              )),
          SizedBox(height: w * 0.020),
          Text(
            'This will immediately call 191 and alert your emergency contacts '
            'with your live location.',
            textAlign: TextAlign.center,
            style: TextStyle(
                color:    MyShopColors.textSecondary,
                fontSize: w * 0.034,
                height:   1.5),
          ),
          SizedBox(height: w * 0.040),
          SizedBox(
            width:  double.infinity,
            height: w * 0.130,
            child: ElevatedButton(
              onPressed: onConfirm,
              style: ElevatedButton.styleFrom(
                backgroundColor: MyShopColors.error,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
                elevation: 0,
              ),
              child: Text('Yes, call 191 now',
                  style: TextStyle(
                      fontSize:   w * 0.040,
                      fontWeight: FontWeight.w700)),
            ),
          ),
          SizedBox(height: w * 0.020),
          TextButton(
            onPressed: onCancel,
            child: Text('Cancel',
                style: TextStyle(
                    color:    MyShopColors.textSecondary,
                    fontSize: w * 0.036)),
          ),
        ],
      ),
    );
  }
}

// ── Quick dial row ─────────────────────────────────────────────────────────────

class _QuickDialRow extends StatelessWidget {
  final double w, h;
  const _QuickDialRow({required this.w, required this.h});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text('Quick access',
            style: TextStyle(
                color:    MyShopColors.textSecondary,
                fontSize: w * 0.030)),
        SizedBox(height: h * 0.012),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _DialBtn(
                label: 'Police\n191',
                color: MyShopColors.error,
                icon:  Icons.local_police_rounded,
                w:     w),
            SizedBox(width: w * 0.060),
            _DialBtn(
                label: 'Ambulance\n193',
                color: MyShopColors.success,
                icon:  Icons.local_hospital_rounded,
                w:     w),
            SizedBox(width: w * 0.060),
            _DialBtn(
                label: 'Fire\n192',
                color: MyShopColors.warning,
                icon:  Icons.local_fire_department_rounded,
                w:     w),
          ],
        ),
      ],
    );
  }
}

class _DialBtn extends StatelessWidget {
  final String label;
  final Color  color;
  final IconData icon;
  final double w;

  const _DialBtn({
    required this.label,
    required this.color,
    required this.icon,
    required this.w,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        // TODO: url_launcher → tel:number
      },
      child: Column(
        children: [
          Container(
            width:  w * 0.16,
            height: w * 0.16,
            decoration: BoxDecoration(
              color:  color.withAlpha(18),
              shape:  BoxShape.circle,
              border: Border.all(color: color.withAlpha(80)),
            ),
            child: Icon(icon, color: color, size: w * 0.068),
          ),
          SizedBox(height: w * 0.016),
          Text(label,
              textAlign: TextAlign.center,
              style: TextStyle(
                color:      color,
                fontSize:   w * 0.026,
                fontWeight: FontWeight.w700,
                height:     1.3,
              )),
        ],
      ),
    );
  }
}

// ── Sent state ─────────────────────────────────────────────────────────────────

class _SentState extends StatelessWidget {
  final double       w, h, bot;
  final VoidCallback onDone;

  const _SentState({
    required this.w,
    required this.h,
    required this.bot,
    required this.onDone,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
          w * 0.08, 0, w * 0.08, bot + h * 0.04),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width:  w * 0.24,
            height: w * 0.24,
            decoration: const BoxDecoration(
                color: MyShopColors.successLight, shape: BoxShape.circle),
            child: const Icon(Icons.check_circle_outline_rounded,
                color: MyShopColors.success, size: 60),
          ),
          SizedBox(height: h * 0.032),
          Text('SOS Sent',
              style: TextStyle(
                color:      MyShopColors.textPrimary,
                fontSize:   w * 0.060,
                fontWeight: FontWeight.w800,
              )),
          SizedBox(height: h * 0.012),
          Text(
            'Your emergency contacts have been alerted with your live '
            'location. Help is on the way.',
            textAlign: TextAlign.center,
            style: TextStyle(
                color:    MyShopColors.textSecondary,
                fontSize: w * 0.036,
                height:   1.6),
          ),
          SizedBox(height: h * 0.048),
          SizedBox(
            width:  double.infinity,
            height: h * 0.066,
            child: ElevatedButton(
              onPressed: onDone,
              style: ElevatedButton.styleFrom(
                backgroundColor: MyShopColors.primaryGold,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
                elevation: 0,
              ),
              child: Text('Done',
                  style: TextStyle(
                      fontSize:   w * 0.042,
                      fontWeight: FontWeight.w700)),
            ),
          ),
        ],
      ),
    );
  }
}
