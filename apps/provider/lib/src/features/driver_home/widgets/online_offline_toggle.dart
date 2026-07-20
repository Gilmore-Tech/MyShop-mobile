import 'package:api_client/api_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../../core/di/providers.dart';
import '../../../core/providers/availability_controller.dart';
import '../../../core/providers/provider_status_provider.dart';
import '../../../core/widgets/background_location_disclosure.dart';
import '../../../core/widgets/availability_restore_notice.dart';
import '../../auth/providers/auth_controller.dart';
import '../../profile/providers/verification_provider.dart';
import '../../profile/providers/provider_type_provider.dart';
import '../../profile/utils/vehicle_eligibility_copy.dart';
import '../../profile/widgets/incomplete_profile_sheet.dart';

/// Segmented Online/Offline toggle at the top of the bottom sheet.
///
/// - Two segments: "Online" (left) and "Offline" (right)
/// - Animated sliding indicator behind the active segment
/// - Green accent when online, grey when offline
/// - Locked (non-interactive) when driver status is busy
/// - Gated by profile completion — shows missing items sheet when incomplete
/// - While going online, the Online segment swaps its bolt icon for a spinner
///   so the user sees the verification + availability checks in flight.
class OnlineOfflineToggle extends ConsumerStatefulWidget {
  const OnlineOfflineToggle({super.key});

  @override
  ConsumerState<OnlineOfflineToggle> createState() =>
      _OnlineOfflineToggleState();
}

class _OnlineOfflineToggleState extends ConsumerState<OnlineOfflineToggle> {
  bool _isGoingOnline = false;

  @override
  Widget build(BuildContext context) {
    final status = ref.watch(providerStatusProvider);
    final isOnline = status.isOnline || status.isBusy;
    final isLocked = status.isBusy || _isGoingOnline;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const AvailabilityRestoreNoticeBanner(),
        Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: MyShopSpacing.md,
            vertical: MyShopSpacing.sm,
          ),
          child: Opacity(
            opacity: status.isBusy ? 0.5 : 1.0,
            child: GestureDetector(
              onTap: isLocked ? null : () => _handleToggle(isOnline),
              child: Container(
                height: 48,
                decoration: BoxDecoration(
                  color: MyShopColors.surfaceGrey,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Stack(
                  children: [
                    // Animated sliding indicator
                    AnimatedAlign(
                      alignment: isOnline
                          ? Alignment.centerLeft
                          : Alignment.centerRight,
                      duration: const Duration(milliseconds: 200),
                      curve: Curves.easeInOut,
                      child: Container(
                        width: MediaQuery.of(context).size.width / 2 -
                            MyShopSpacing.md -
                            2,
                        height: 44,
                        margin: const EdgeInsets.all(2),
                        decoration: BoxDecoration(
                          color: isOnline
                              ? MyShopColors.online
                              : MyShopColors.darkSlate,
                          borderRadius: BorderRadius.circular(10),
                          boxShadow: [
                            BoxShadow(
                              color: (isOnline
                                      ? MyShopColors.online
                                      : MyShopColors.darkSlate)
                                  .withValues(alpha: 0.3),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                      ),
                    ),

                    // Labels row
                    Row(
                      children: [
                        // Online segment
                        Expanded(
                          child: Center(
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                _OnlineSegmentLeading(
                                  isActive: isOnline,
                                  isWorking: _isGoingOnline,
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  _isGoingOnline ? 'Checking…' : 'Online',
                                  style: TextStyle(
                                    fontFamily: 'Raleway',
                                    fontSize: 14,
                                    fontWeight: FontWeight.w700,
                                    color: isOnline || _isGoingOnline
                                        ? MyShopColors.textOnPrimary
                                        : MyShopColors.textSecondary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),

                        // Offline segment
                        Expanded(
                          child: Center(
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.power_settings_new,
                                  size: 18,
                                  color: !isOnline
                                      ? MyShopColors.textOnPrimary
                                      : MyShopColors.textSecondary,
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  'Offline',
                                  style: TextStyle(
                                    fontFamily: 'Raleway',
                                    fontSize: 14,
                                    fontWeight: FontWeight.w700,
                                    color: !isOnline
                                        ? MyShopColors.textOnPrimary
                                        : MyShopColors.textSecondary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _handleToggle(bool isOnline) async {
    final availability = ref.read(availabilityControllerProvider);

    // Going offline: wait for the authoritative server transition so an
    // active-work rejection or network failure cannot falsely show offline.
    if (isOnline) {
      final error = await availability.goOffline();
      if (error != null && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(error)),
        );
      }
      return;
    }

    setState(() => _isGoingOnline = true);
    try {
      // Force a fresh read of both the verification docs and the user
      // profile before deciding completeness. The home screen warms the
      // verification provider once on mount and Riverpod caches it for the
      // session; without invalidating, an approval (or vehicle/photo
      // update) that happened server-side mid-session never reaches the
      // toggle and the user sees a stale "incomplete profile" sheet.
      ref.invalidate(verificationStatusProvider);
      await Future.wait<void>([
        ref
            .read(verificationStatusProvider.future)
            .then<void>((_) {})
            .catchError((_) {}),
        ref
            .read(authControllerProvider.notifier)
            .refreshProfile()
            .then<void>((_) {})
            .catchError((_) {}),
      ]);

      final completion = ref.read(profileCompletionProvider);
      if (!mounted) return;

      if (completion.verificationUnavailable) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(completion.missing.first)),
        );
        return;
      }

      if (!completion.isComplete) {
        showIncompleteProfileSheet(context, completion: completion);
        return;
      }

      String? selectedVehicleId;
      if (!ref.read(providerTypeProvider).isArtisan) {
        selectedVehicleId = await _selectVehicleForOnline();
        if (selectedVehicleId == null || !mounted) return;
      }

      final disclosureAccepted =
          await confirmBackgroundLocationDisclosure(context);
      if (!disclosureAccepted || !mounted) return;

      final error = await availability.goOnline(
        backgroundLocationDisclosureAccepted: true,
        vehicleId: selectedVehicleId,
      );
      if (error != null && mounted) {
        final recoveryShown = await showLocationRecoveryIfNeeded(context);
        if (!recoveryShown && mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(error)));
        }
      }
    } finally {
      if (mounted) setState(() => _isGoingOnline = false);
    }
  }

  Future<String?> _selectVehicleForOnline() async {
    ProviderVehiclePreflight preflight;
    try {
      preflight =
          await ref.read(providerAvailabilityServiceProvider).getMyVehicles();
    } on ApiException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(friendlyAvailabilityApiError(error))),
        );
      }
      return null;
    } on FormatException {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              "We couldn't verify your vehicles. Refresh and try again.",
            ),
          ),
        );
      }
      return null;
    }

    if (!mounted) return null;
    return showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => VehicleSelectionSheet(preflight: preflight),
    );
  }
}

class VehicleSelectionSheet extends StatefulWidget {
  const VehicleSelectionSheet({super.key, required this.preflight});

  final ProviderVehiclePreflight preflight;

  @override
  State<VehicleSelectionSheet> createState() => _VehicleSelectionSheetState();
}

class _VehicleSelectionSheetState extends State<VehicleSelectionSheet> {
  String? _selectedVehicleId;

  @override
  Widget build(BuildContext context) {
    final vehicles = widget.preflight.vehicles;
    final hasEligibleVehicle = vehicles.any((vehicle) => vehicle.eligible);

    return Padding(
      padding: EdgeInsets.fromLTRB(
        MyShopSpacing.lg,
        MyShopSpacing.lg,
        MyShopSpacing.lg,
        MediaQuery.viewInsetsOf(context).bottom + MyShopSpacing.lg,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Select your vehicle',
            style: TextStyle(
              fontFamily: 'Raleway',
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: MyShopColors.textPrimary,
            ),
          ),
          const SizedBox(height: MyShopSpacing.xs),
          const Text(
            'Choose the one vehicle you will use during this online session.',
            style: TextStyle(color: MyShopColors.textSecondary),
          ),
          const SizedBox(height: MyShopSpacing.md),
          if (vehicles.isEmpty)
            _VehicleUnavailableNotice(
              legacyBackfillRequired: widget.preflight.legacyBackfillRequired,
              vehicles: vehicles,
            )
          else ...[
            if (!hasEligibleVehicle) ...[
              _VehicleUnavailableNotice(
                legacyBackfillRequired: widget.preflight.legacyBackfillRequired,
                vehicles: vehicles,
              ),
              const SizedBox(height: MyShopSpacing.sm),
            ],
            Flexible(
              child: RadioGroup<String>(
                groupValue: _selectedVehicleId,
                onChanged: (value) {
                  if (value != null) {
                    setState(() => _selectedVehicleId = value);
                  }
                },
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: vehicles.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (_, index) {
                    final vehicle = vehicles[index];
                    final details = [
                      if (vehicle.plate != null) vehicle.plate!,
                      if (vehicle.year != null) vehicle.year.toString(),
                      if (vehicle.color != null) vehicle.color!,
                    ].join(' • ');
                    return RadioListTile<String>(
                      value: vehicle.id,
                      enabled: vehicle.eligible,
                      title: Text(
                        vehicle.displayName,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      subtitle: Text(
                        vehicle.eligible
                            ? (details.isEmpty
                                ? 'Eligible to go online'
                                : details)
                            : [
                                if (details.isNotEmpty) details,
                                vehicleEligibilitySummary(
                                  vehicle.reasonCodes,
                                ),
                              ].join('\n'),
                      ),
                      activeColor: MyShopColors.online,
                    );
                  },
                ),
              ),
            ),
          ],
          const SizedBox(height: MyShopSpacing.md),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _selectedVehicleId == null
                  ? null
                  : () => Navigator.of(context).pop(_selectedVehicleId),
              child: const Text('Use this vehicle'),
            ),
          ),
        ],
      ),
    );
  }
}

class _VehicleUnavailableNotice extends StatelessWidget {
  const _VehicleUnavailableNotice({
    required this.legacyBackfillRequired,
    required this.vehicles,
  });

  final bool legacyBackfillRequired;
  final List<ProviderVehicleSummary> vehicles;

  @override
  Widget build(BuildContext context) {
    final reason = vehicles.isEmpty
        ? legacyBackfillRequired
            ? 'Your existing vehicle record must be updated by support before you can go online.'
            : 'No vehicle is available for this driver profile.'
        : 'No vehicle can go online yet. Review each vehicle’s blockers below.';
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(MyShopSpacing.md),
      decoration: BoxDecoration(
        color: MyShopColors.errorLight,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(reason, style: const TextStyle(color: MyShopColors.error)),
    );
  }
}

class _OnlineSegmentLeading extends StatelessWidget {
  const _OnlineSegmentLeading({
    required this.isActive,
    required this.isWorking,
  });

  final bool isActive;
  final bool isWorking;

  @override
  Widget build(BuildContext context) {
    if (isWorking) {
      return const SizedBox(
        width: 18,
        height: 18,
        child: CircularProgressIndicator(
          strokeWidth: 2,
          valueColor: AlwaysStoppedAnimation<Color>(MyShopColors.textOnPrimary),
        ),
      );
    }
    return Icon(
      Icons.bolt,
      size: 18,
      color: isActive ? MyShopColors.textOnPrimary : MyShopColors.textSecondary,
    );
  }
}
