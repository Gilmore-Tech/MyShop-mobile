import 'package:api_client/api_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_ui/shared_ui.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/di/providers.dart';
import '../../artisan_home/providers/active_job_provider.dart';
import '../../driver_home/providers/ride_request_provider.dart';
import '../../profile/providers/provider_type_provider.dart';

/// Same two-step emergency as client (PRD 9.1.1).
///
/// 1. Driver/artisan presses + HOLDS the big red button for 3 seconds.
///    Accidental taps are filtered out — only a deliberate hold opens
///    the confirm dialog.
/// 2. The completed hold fires `POST /v1/emergency` with any available active
///    booking and GPS context, then opens `tel:191`. The user must still place the call. The alert fires
///    FIRST because handing off to the dialer can freeze the Flutter
///    isolate momentarily — losing the alert at that instant defeats
///    the whole feature.
///
/// `bookingType` is derived from the active role: drivers send `'ride'`,
/// artisans send `'job'`. The active booking id comes from the role's
/// in-flight notifier. A missing booking or GPS fix never suppresses the
/// platform alert.
class ProviderEmergencyScreen extends ConsumerStatefulWidget {
  const ProviderEmergencyScreen({super.key});

  @override
  ConsumerState<ProviderEmergencyScreen> createState() =>
      _ProviderEmergencyScreenState();
}

class _ProviderEmergencyScreenState
    extends ConsumerState<ProviderEmergencyScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _holdCtrl;
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

  /// Completing the 3-second hold IS the confirmation — no follow-up
  /// dialog. The hold itself is the deliberate gesture that filters out
  /// pocket-taps; making the user tap a second "Send SOS" button before
  /// anything actually fires is a real risk in a real emergency. Fire
  /// the platform alert and open the 191 dialer immediately.
  void _onHoldComplete() {
    _holdCtrl.reset();
    _triggerSos();
  }

  Future<void> _triggerSos() async {
    setState(() => _isSending = true);
    final messenger = ScaffoldMessenger.of(context);

    // Active booking + booking type from the role.
    final role = ref.read(providerTypeProvider);
    final isDriver = role.isDriver;
    final bookingType = isDriver ? 'ride' : 'job';
    final bookingId = isDriver
        ? ref.read(activeRideProvider).ride?.id
        : ref.read(activeJobProvider).job?.id;
    var platformAlertSent = false;
    var policeDialOpened = false;
    int? contactsNotified;

    // GPS — geolocator is fast on a fresh fix; if it errors we still
    // open the 191 dialer below. Use 5s timeout so we don't hang the user.
    Position? pos;
    try {
      pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 5),
        ),
      );
    } catch (_) {
      pos = await Geolocator.getLastKnownPosition();
    }

    try {
      final result = await ref.read(safetyServiceProvider).triggerEmergency(
            bookingType: bookingId == null ? null : bookingType,
            bookingId: bookingId,
            latitude: pos?.latitude,
            longitude: pos?.longitude,
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

    final dialUri = Uri.parse('tel:191');
    if (await canLaunchUrl(dialUri)) {
      policeDialOpened =
          await launchUrl(dialUri, mode: LaunchMode.externalApplication);
    } else if (mounted) {
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
    final w = MediaQuery.sizeOf(context).width;
    return Scaffold(
      backgroundColor: MyShopColors.offWhite,
      appBar: AppBar(
        backgroundColor: MyShopColors.surfaceWhite,
        elevation: 0,
        foregroundColor: MyShopColors.textPrimary,
        title: const Text(
          'Emergency',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
        leading: IconButton(
          icon: const Icon(Icons.close_rounded),
          onPressed: () => context.pop(),
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(MyShopSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: MyShopSpacing.lg),
              const Text(
                'Hold the button for 3 seconds to raise an SOS.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: MyShopColors.textPrimary,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'We will share your live location with MyShop support and '
                'open the Ghana Police Service 191 dialer. You must still tap '
                'Call in the phone app.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  color: MyShopColors.textSecondary,
                  height: 1.4,
                ),
              ),
              const Spacer(),
              Center(
                child: GestureDetector(
                  onTapDown: _isSending || _sosTriggered
                      ? null
                      : (_) => _onHoldStart(),
                  onTapUp: (_) => _onHoldCancel(),
                  onTapCancel: _onHoldCancel,
                  child: AnimatedBuilder(
                    animation: _holdCtrl,
                    builder: (_, __) {
                      final progress = _holdCtrl.value;
                      final size = w * 0.55;
                      return Stack(
                        alignment: Alignment.center,
                        children: [
                          SizedBox(
                            width: size,
                            height: size,
                            child: CircularProgressIndicator(
                              value: progress,
                              strokeWidth: 6,
                              backgroundColor:
                                  MyShopColors.error.withValues(alpha: 0.15),
                              valueColor: const AlwaysStoppedAnimation<Color>(
                                MyShopColors.error,
                              ),
                            ),
                          ),
                          Container(
                            width: size * 0.78,
                            height: size * 0.78,
                            decoration: BoxDecoration(
                              color: MyShopColors.error,
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color:
                                      MyShopColors.error.withValues(alpha: 0.4),
                                  blurRadius: 24,
                                  offset: const Offset(0, 8),
                                ),
                              ],
                            ),
                            child: Center(
                              child: _isSending
                                  ? const CircularProgressIndicator(
                                      strokeWidth: 3,
                                      valueColor: AlwaysStoppedAnimation<Color>(
                                          Colors.white),
                                    )
                                  : Text(
                                      _sosTriggered ? 'SENT' : 'HOLD\nSOS',
                                      textAlign: TextAlign.center,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontFamily: 'Raleway',
                                        fontSize: 22,
                                        fontWeight: FontWeight.w900,
                                        letterSpacing: 1.5,
                                        height: 1.05,
                                      ),
                                    ),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
              ),
              const Spacer(),
              if (_sosTriggered)
                Container(
                  padding: const EdgeInsets.all(MyShopSpacing.md),
                  decoration: BoxDecoration(
                    color: (_platformAlertSent
                            ? MyShopColors.success
                            : MyShopColors.error)
                        .withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: (_platformAlertSent
                              ? MyShopColors.success
                              : MyShopColors.error)
                          .withValues(alpha: 0.4),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        _platformAlertSent
                            ? Icons.check_circle_rounded
                            : Icons.warning_amber_rounded,
                        color: _platformAlertSent
                            ? MyShopColors.success
                            : MyShopColors.error,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          _sosStatusText(),
                          style: const TextStyle(
                            color: MyShopColors.textPrimary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: MyShopSpacing.md),
            ],
          ),
        ),
      ),
    );
  }

  String _sosStatusText() {
    final dialStatus = _policeDialOpened
        ? 'The police dialer was opened.'
        : 'The police dialer did not open; call 191 manually.';
    if (!_platformAlertSent) {
      return 'The MyShop platform alert was not confirmed. $dialStatus';
    }
    if (_contactsNotified == null) {
      return 'MyShop recorded your SOS. Contact-provider status was not returned. $dialStatus';
    }
    if (_contactsNotified == 0) {
      return 'MyShop recorded your SOS. No contact SMS was accepted by the messaging provider. $dialStatus';
    }
    final label = _contactsNotified == 1 ? 'contact' : 'contacts';
    return 'MyShop recorded your SOS. The messaging provider accepted an SMS request for $_contactsNotified emergency $label; handset delivery is not guaranteed. $dialStatus';
  }
}
