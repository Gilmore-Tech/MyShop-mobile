import 'package:api_client/api_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../../core/di/providers.dart';
import '../../../core/providers/current_location_provider.dart';
import '../../ride/providers/ride_provider.dart';
import '../emergency_dialer.dart';

// ── Screen ─────────────────────────────────────────────────────────────────────
// PRD § 4.10 — Two-step SOS confirmation to prevent accidental triggers.
// Step 1: hold-to-confirm button (3 s press).
// The completed hold records the platform SOS, requests contact/admin alerts,
// and opens the OS dialer. The user must still place the call.

class EmergencyScreen extends ConsumerStatefulWidget {
  const EmergencyScreen({
    super.key,
    this.bookingType,
    this.bookingId,
  }) : assert((bookingType == null) == (bookingId == null));

  final String? bookingType;
  final String? bookingId;

  @override
  ConsumerState<EmergencyScreen> createState() => _EmergencyScreenState();
}

class _EmergencyScreenState extends ConsumerState<EmergencyScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _holdCtrl;
  bool _sosTriggered = false;
  bool _isSending = false;
  bool _platformAlertSent = false;
  bool _policeDialOpened = false;
  int? _contactsNotified;

  @override
  void initState() {
    super.initState();
    _holdCtrl = AnimationController(
      vsync: this,
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

  void _onHoldStart() => _holdCtrl.forward();
  void _onHoldCancel() => _holdCtrl.reverse();

  /// Completing the 3-second hold IS the confirmation. No follow-up
  /// dialog — in a real emergency the user shouldn't have to tap a
  /// second "Send SOS" button before anything fires. The hold itself
  /// is the deliberate gesture that filters out pocket-taps.
  void _onHoldComplete() {
    _holdCtrl.reset();
    _triggerSos();
  }

  Future<void> _triggerSos() async {
    setState(() {
      _isSending = true;
    });

    final messenger = ScaffoldMessenger.of(context);
    final inferredRideId = ref.read(activeRideIdProvider);
    final bookingId = widget.bookingId ?? inferredRideId;
    final bookingType = widget.bookingId != null
        ? widget.bookingType
        : (inferredRideId == null ? null : 'ride');
    var position = ref.read(currentDevicePositionProvider);
    try {
      position ??=
          await ref.read(currentLocationServiceProvider).ensure().timeout(
                const Duration(seconds: 5),
                onTimeout: () => ref.read(currentDevicePositionProvider),
              );
    } catch (_) {
      position = ref.read(currentDevicePositionProvider);
    }
    var platformAlertSent = false;
    var policeDialOpened = false;
    int? contactsNotified;

    // POST the alert FIRST so the platform safety dashboard logs it
    // before we hand the phone over to the dialer (which can freeze the
    // app). Failure to record the alert doesn't block access to the police
    // dialer — surface a warning but continue.
    try {
      final result = await ref.read(safetyServiceProvider).triggerEmergency(
            bookingType: bookingType,
            bookingId: bookingId,
            latitude: position?.latitude,
            longitude: position?.longitude,
          );
      platformAlertSent = true;
      contactsNotified = (result['contactsNotified'] as num?)?.toInt();
    } on ApiException catch (e) {
      if (mounted) {
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              userSafeApiErrorMessage(
                e,
                fallback:
                    "Couldn't send the platform alert. Continue with the emergency call.",
              ),
            ),
          ),
        );
      }
    } catch (_) {
      if (mounted) {
        messenger.showSnackBar(
          const SnackBar(content: Text("Couldn't send platform alert.")),
        );
      }
    }

    try {
      policeDialOpened = await openEmergencyDialer('191');
    } catch (_) {
      policeDialOpened = false;
    }
    if (!policeDialOpened && mounted) {
      messenger.showSnackBar(
        const SnackBar(content: Text("Couldn't open the phone dialer.")),
      );
    }

    if (!mounted) return;
    setState(() {
      _isSending = false;
      _sosTriggered = true;
      _platformAlertSent = platformAlertSent;
      _policeDialOpened = policeDialOpened;
      _contactsNotified = contactsNotified;
    });
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final w = size.width;
    final h = size.height;
    final top = MediaQuery.paddingOf(context).top;
    final bot = MediaQuery.paddingOf(context).bottom;

    return Scaffold(
      backgroundColor: MyShopColors.offWhite,
      body: Column(
        children: [
          // Header
          Container(
            color: MyShopColors.surfaceWhite,
            padding: EdgeInsets.only(top: top),
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.close_rounded,
                      color: MyShopColors.textPrimary),
                  onPressed: () => context.pop(),
                ),
                Text('Emergency',
                    style: TextStyle(
                      color: MyShopColors.textPrimary,
                      fontSize: w * 0.044,
                      fontWeight: FontWeight.w700,
                    )),
              ],
            ),
          ),
          Expanded(
            child: _sosTriggered
                ? _SentState(
                    w: w,
                    h: h,
                    bot: bot,
                    platformAlertSent: _platformAlertSent,
                    policeDialOpened: _policeDialOpened,
                    contactsNotified: _contactsNotified,
                    onDone: () => context.pop(),
                  )
                : _HoldState(
                    w: w,
                    h: h,
                    bot: bot,
                    holdCtrl: _holdCtrl,
                    isSending: _isSending,
                    onStart: _onHoldStart,
                    onCancel: _onHoldCancel,
                  ),
          ),
        ],
      ),
    );
  }
}

// ── Hold state ─────────────────────────────────────────────────────────────────

class _HoldState extends StatelessWidget {
  final double w, h, bot;
  final AnimationController holdCtrl;
  final bool isSending;
  final VoidCallback onStart;
  final VoidCallback onCancel;

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
      padding:
          EdgeInsets.fromLTRB(w * 0.07, h * 0.04, w * 0.07, bot + h * 0.04),
      child: Column(
        children: [
          // Info panel
          Container(
            padding: EdgeInsets.all(w * 0.04),
            decoration: BoxDecoration(
              color: MyShopColors.errorLight,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: MyShopColors.error.withAlpha(60)),
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
                            color: MyShopColors.error,
                            fontSize: w * 0.036,
                            fontWeight: FontWeight.w700,
                          )),
                    ),
                  ],
                ),
                SizedBox(height: h * 0.010),
                Text(
                  'Triggering SOS records your live location, requests alerts for '
                  'saved emergency contacts, and opens the Ghana Police 191 dialer. '
                  'You must still tap Call in the phone app.',
                  style: TextStyle(
                      color: MyShopColors.error.withAlpha(180),
                      fontSize: w * 0.031,
                      height: 1.5),
                ),
              ],
            ),
          ),
          const Spacer(),
          // Hold button
          Text('Hold for 3 seconds to trigger SOS',
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: MyShopColors.textSecondary, fontSize: w * 0.034)),
          SizedBox(height: h * 0.032),
          AnimatedBuilder(
            animation: holdCtrl,
            builder: (_, __) {
              return GestureDetector(
                onTapDown: (_) => onStart(),
                onTapUp: (_) => onCancel(),
                onTapCancel: onCancel,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    SizedBox(
                      width: w * 0.50,
                      height: w * 0.50,
                      child: CircularProgressIndicator(
                        value: holdCtrl.value,
                        strokeWidth: 6,
                        color: MyShopColors.error,
                        backgroundColor: MyShopColors.error.withAlpha(30),
                      ),
                    ),
                    Container(
                      width: w * 0.42,
                      height: w * 0.42,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: holdCtrl.value > 0
                            ? MyShopColors.error
                            : MyShopColors.errorLight,
                        border: Border.all(color: MyShopColors.error, width: 2),
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
                                color: holdCtrl.value > 0
                                    ? Colors.white
                                    : MyShopColors.error,
                                fontSize: w * 0.040,
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

// Old `_ConfirmDialog` removed — the 3-second hold itself IS the
// confirmation. Asking the user to tap a second "Send SOS" button in
// a panic moment was bad UX.

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
                color: MyShopColors.textSecondary, fontSize: w * 0.030)),
        SizedBox(height: h * 0.012),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _DialBtn(
                label: 'Police\n191',
                phoneNumber: '191',
                color: MyShopColors.error,
                icon: Icons.local_police_rounded,
                w: w),
            SizedBox(width: w * 0.060),
            _DialBtn(
                label: 'Ambulance\n112',
                phoneNumber: '112',
                color: MyShopColors.success,
                icon: Icons.local_hospital_rounded,
                w: w),
            SizedBox(width: w * 0.060),
            _DialBtn(
                label: 'Fire\n112',
                phoneNumber: '112',
                color: MyShopColors.warning,
                icon: Icons.local_fire_department_rounded,
                w: w),
          ],
        ),
      ],
    );
  }
}

class _DialBtn extends StatelessWidget {
  final String label;
  final String phoneNumber;
  final Color color;
  final IconData icon;
  final double w;

  const _DialBtn({
    required this.label,
    required this.phoneNumber,
    required this.color,
    required this.icon,
    required this.w,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () async {
        final messenger = ScaffoldMessenger.of(context);
        var opened = false;
        try {
          opened = await openEmergencyDialer(phoneNumber);
        } catch (_) {
          opened = false;
        }
        if (!opened && context.mounted) {
          messenger.showSnackBar(
            SnackBar(
                content: Text(
                    "Couldn't open the dialer. Call $phoneNumber manually.")),
          );
        }
      },
      child: Column(
        children: [
          Container(
            width: w * 0.16,
            height: w * 0.16,
            decoration: BoxDecoration(
              color: color.withAlpha(18),
              shape: BoxShape.circle,
              border: Border.all(color: color.withAlpha(80)),
            ),
            child: Icon(icon, color: color, size: w * 0.068),
          ),
          SizedBox(height: w * 0.016),
          Text(label,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: color,
                fontSize: w * 0.026,
                fontWeight: FontWeight.w700,
                height: 1.3,
              )),
        ],
      ),
    );
  }
}

// ── Sent state ─────────────────────────────────────────────────────────────────

class _SentState extends StatelessWidget {
  final double w, h, bot;
  final bool platformAlertSent;
  final bool policeDialOpened;
  final int? contactsNotified;
  final VoidCallback onDone;

  const _SentState({
    required this.w,
    required this.h,
    required this.bot,
    required this.platformAlertSent,
    required this.policeDialOpened,
    required this.contactsNotified,
    required this.onDone,
  });

  String get _statusText {
    final dialStatus = policeDialOpened
        ? 'The police dialer was opened.'
        : 'The police dialer did not open; call 191 manually.';
    if (!platformAlertSent) {
      return 'The MyShop platform alert was not confirmed. $dialStatus';
    }
    if (contactsNotified == null) {
      return 'MyShop recorded your SOS. Contact-provider status was not returned. $dialStatus';
    }
    if (contactsNotified == 0) {
      return 'MyShop recorded your SOS. No contact SMS was accepted by the messaging provider. $dialStatus';
    }
    final label = contactsNotified == 1 ? 'contact' : 'contacts';
    return 'MyShop recorded your SOS. The messaging provider accepted an SMS request for $contactsNotified emergency $label; handset delivery is not guaranteed. $dialStatus';
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(w * 0.08, 0, w * 0.08, bot + h * 0.04),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: w * 0.24,
            height: w * 0.24,
            decoration: BoxDecoration(
              color: platformAlertSent
                  ? MyShopColors.successLight
                  : MyShopColors.errorLight,
              shape: BoxShape.circle,
            ),
            child: Icon(
              platformAlertSent
                  ? Icons.check_circle_outline_rounded
                  : Icons.warning_amber_rounded,
              color:
                  platformAlertSent ? MyShopColors.success : MyShopColors.error,
              size: 60,
            ),
          ),
          SizedBox(height: h * 0.032),
          Text(platformAlertSent ? 'SOS Sent' : 'Platform Alert Not Sent',
              style: TextStyle(
                color: MyShopColors.textPrimary,
                fontSize: w * 0.060,
                fontWeight: FontWeight.w800,
              )),
          SizedBox(height: h * 0.012),
          Text(
            _statusText,
            textAlign: TextAlign.center,
            style: TextStyle(
                color: MyShopColors.textSecondary,
                fontSize: w * 0.036,
                height: 1.6),
          ),
          SizedBox(height: h * 0.048),
          SizedBox(
            width: double.infinity,
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
                      fontSize: w * 0.042, fontWeight: FontWeight.w700)),
            ),
          ),
        ],
      ),
    );
  }
}
