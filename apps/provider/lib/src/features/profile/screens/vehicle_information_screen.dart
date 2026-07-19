import 'package:api_client/api_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:shared_ui/shared_ui.dart';

import '../models/vehicle_form_state.dart';
import '../providers/provider_type_provider.dart';
import '../providers/provider_vehicle_provider.dart';
import '../widgets/vehicle_form_body.dart';

class VehicleInformationScreen extends ConsumerWidget {
  const VehicleInformationScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (ref.watch(providerTypeProvider).isArtisan) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted) context.go('/account');
      });
      return const SizedBox.shrink();
    }

    final vehicles = ref.watch(providerVehiclesProvider);
    return Scaffold(
      backgroundColor: MyShopColors.surfaceWhite,
      appBar: AppBar(
        backgroundColor: MyShopColors.surfaceWhite,
        elevation: 0,
        title: const Text('My Vehicles'),
      ),
      body: vehicles.when(
        loading: () => const _VehicleListSkeleton(),
        error: (_, __) => MyShopErrorBody(
          message: 'Could not load your vehicles',
          onRetry: () => ref.invalidate(providerVehiclesProvider),
        ),
        data: (data) => RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(providerVehiclesProvider);
            await ref.read(providerVehiclesProvider.future);
          },
          color: MyShopColors.primaryGold,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(MyShopSpacing.md),
            children: [
              if (data.legacyBackfillRequired) const _LegacyVehicleNotice(),
              if (data.legacyBackfillRequired)
                const SizedBox(height: MyShopSpacing.md),
              if (data.vehicles.isEmpty)
                const _NoVehicles()
              else
                for (final vehicle in data.vehicles) ...[
                  _VehicleCard(
                    vehicle: vehicle,
                    isSelectedOnline: data.activeVehicleId == vehicle.id,
                    onEdit: vehicle.approvalStatus.canProviderEdit(
                      removalRequested: vehicle.removalRequested,
                    )
                        ? () => _openVehicleForm(context, ref, vehicle)
                        : null,
                    onRemovalRequest: vehicle.approvalStatus !=
                                ProviderVehicleApprovalStatus.retired &&
                            !vehicle.removalRequested
                        ? () => _requestRemoval(context, ref, vehicle)
                        : null,
                    onDocuments: () => context.push('/account/documents'),
                  ),
                  const SizedBox(height: MyShopSpacing.md),
                ],
              MyShopPrimaryButton(
                label: 'Add another vehicle',
                icon: Icons.add,
                onPressed: () => _openVehicleForm(context, ref, null),
              ),
              const SizedBox(height: MyShopSpacing.xxl),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _openVehicleForm(
    BuildContext context,
    WidgetRef ref,
    ProviderVehicle? vehicle,
  ) async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => ProviderVehicleFormScreen(vehicle: vehicle),
      ),
    );
    if (changed == true) ref.invalidate(providerVehiclesProvider);
  }

  Future<void> _requestRemoval(
    BuildContext context,
    WidgetRef ref,
    ProviderVehicle vehicle,
  ) async {
    final reasonController = TextEditingController();
    String? validationError;
    final reason = await showDialog<String>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Request vehicle removal'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'An admin will review and retire this vehicle. It remains unchanged until then.',
                style: MyShopTypography.body2,
              ),
              const SizedBox(height: MyShopSpacing.md),
              MyShopTextField(
                controller: reasonController,
                label: 'Reason (optional)',
                hint: 'Why should this vehicle be removed?',
                errorText: validationError,
                onChanged: (_) => setState(() => validationError = null),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () {
                final value = reasonController.text.trim();
                if (value.isNotEmpty && value.length < 5) {
                  setState(() {
                    validationError =
                        'Use at least 5 characters or leave this blank.';
                  });
                  return;
                }
                Navigator.pop(dialogContext, value);
              },
              child: const Text('Send request'),
            ),
          ],
        ),
      ),
    );
    reasonController.dispose();
    if (reason == null || !context.mounted) return;

    try {
      await ref.read(providerVehicleServiceProvider).requestRemoval(
            vehicleId: vehicle.id,
            expectedVersion: vehicle.version,
            reason: reason,
          );
      ref.invalidate(providerVehiclesProvider);
      if (context.mounted) {
        MyShopToast.show(context, message: 'Removal request sent for review.');
      }
    } on ApiException catch (error) {
      if (error.errorCode == 'VEHICLE_CHANGED_RETRY') {
        ref.invalidate(providerVehiclesProvider);
      }
      if (context.mounted) {
        MyShopToast.show(
          context,
          message: _vehicleActionMessage(error),
          type: ToastType.error,
        );
      }
    }
  }
}

class ProviderVehicleFormScreen extends ConsumerWidget {
  const ProviderVehicleFormScreen({super.key, required this.vehicle});

  final ProviderVehicle? vehicle;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final categories = ref.watch(providerVehicleRideCategoriesProvider);
    final initial = vehicle == null
        ? const VehicleFormState()
        : VehicleFormState(
            make: vehicle!.make,
            model: vehicle!.model,
            year: vehicle!.year.toString(),
            plate: vehicle!.plate,
            color: vehicle!.color,
            rideCategoryIds:
                vehicle!.rideCategories.map((value) => value.id).toSet(),
          );

    return Scaffold(
      backgroundColor: MyShopColors.surfaceWhite,
      appBar: AppBar(
        backgroundColor: MyShopColors.surfaceWhite,
        elevation: 0,
        title: Text(vehicle == null ? 'Add Vehicle' : 'Edit Vehicle'),
      ),
      body: categories.when(
        loading: () => const _VehicleListSkeleton(),
        error: (_, __) => MyShopErrorBody(
          message: 'Could not load ride categories',
          onRetry: () => ref.invalidate(providerVehicleRideCategoriesProvider),
        ),
        data: (choices) {
          if (choices.isEmpty) {
            return MyShopErrorBody(
              message: 'No ride categories are available',
              subtitle: 'Try again later or contact support.',
              onRetry: () =>
                  ref.invalidate(providerVehicleRideCategoriesProvider),
            );
          }
          return VehicleFormBody(
            initialValue: initial,
            categories: choices
                .map(
                  (choice) => VehicleCategoryChoice(
                    id: choice.id,
                    name: choice.name,
                    description: choice.description,
                  ),
                )
                .toList(growable: false),
            submitLabel:
                vehicle == null ? 'Submit for approval' : 'Save changes',
            onSubmit: (draft) async {
              final input = ProviderVehicleInput(
                make: draft.make.trim(),
                model: draft.model.trim(),
                year: int.parse(draft.year.trim()),
                plate: draft.normalizedPlate,
                color: draft.color.trim(),
                rideCategoryIds: draft.rideCategoryIds.toList(growable: false),
              );
              try {
                if (vehicle == null) {
                  await ref
                      .read(providerVehicleServiceProvider)
                      .createVehicle(input);
                } else {
                  await ref.read(providerVehicleServiceProvider).updateVehicle(
                        vehicleId: vehicle!.id,
                        expectedVersion: vehicle!.version,
                        input: input,
                      );
                }
                ref.invalidate(providerVehiclesProvider);
                if (context.mounted) Navigator.pop(context, true);
                return null;
              } on ApiException catch (error) {
                if (error.errorCode == 'VEHICLE_CHANGED_RETRY') {
                  ref.invalidate(providerVehiclesProvider);
                }
                return _vehicleActionMessage(error);
              }
            },
          );
        },
      ),
    );
  }
}

class _VehicleCard extends StatelessWidget {
  const _VehicleCard({
    required this.vehicle,
    required this.isSelectedOnline,
    required this.onEdit,
    required this.onRemovalRequest,
    required this.onDocuments,
  });

  final ProviderVehicle vehicle;
  final bool isSelectedOnline;
  final VoidCallback? onEdit;
  final VoidCallback? onRemovalRequest;
  final VoidCallback onDocuments;

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
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: MyShopColors.surfaceGrey,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.directions_car,
                  color: MyShopColors.darkSlate,
                ),
              ),
              const SizedBox(width: MyShopSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(vehicle.displayName, style: MyShopTypography.h3),
                    const SizedBox(height: 2),
                    Text(
                      '${vehicle.plate} · ${vehicle.color} · ${vehicle.year}',
                      style: MyShopTypography.body2,
                    ),
                  ],
                ),
              ),
              _VehicleStatusBadge(status: vehicle.approvalStatus),
            ],
          ),
          if (isSelectedOnline) ...[
            const SizedBox(height: MyShopSpacing.sm),
            Text(
              'Selected for the current online session',
              style: MyShopTypography.caption.copyWith(
                color: MyShopColors.success,
              ),
            ),
          ],
          if (vehicle.rejectionReason case final rejection?) ...[
            const SizedBox(height: MyShopSpacing.md),
            _NoticeBox(
              message: rejection,
              color: MyShopColors.error,
              background: MyShopColors.errorLight,
            ),
          ],
          if (vehicle.removalRequested) ...[
            const SizedBox(height: MyShopSpacing.md),
            _NoticeBox(
              message:
                  'Removal requested ${DateFormat('dd MMM yyyy, HH:mm').format(vehicle.retirementRequestedAt!.toLocal())}. The vehicle remains unchanged until an admin retires it.${vehicle.retirementRequestReason == null ? '' : '\n${vehicle.retirementRequestReason}'}',
              color: MyShopColors.warning,
              background: MyShopColors.warningLight,
            ),
          ],
          if (vehicle.pendingRevision case final revision?) ...[
            const SizedBox(height: MyShopSpacing.md),
            _NoticeBox(
              message:
                  'An admin change (${revision.make} ${revision.model}, ${revision.plate}) is awaiting ${revision.status == ProviderVehicleApprovalStatus.pendingCoordinator ? 'Coordinator review' : 'Regional Manager review'}. Your approved vehicle details remain active until final approval.',
              color: MyShopColors.info,
              background: MyShopColors.infoLight,
            ),
          ],
          const SizedBox(height: MyShopSpacing.md),
          Text('Ride categories', style: MyShopTypography.body1),
          const SizedBox(height: MyShopSpacing.sm),
          for (final category in vehicle.rideCategories)
            Padding(
              padding: const EdgeInsets.only(bottom: MyShopSpacing.sm),
              child: Row(
                children: [
                  Expanded(child: Text(category.name)),
                  Text(
                    category.status.label,
                    style: MyShopTypography.caption.copyWith(
                      color: category.status.color,
                    ),
                  ),
                ],
              ),
            ),
          if (!vehicle.eligible && vehicle.reasonCodes.isNotEmpty) ...[
            const SizedBox(height: MyShopSpacing.sm),
            for (final reason in vehicle.reasonCodes)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  '• ${_eligibilityMessage(reason)}',
                  style: MyShopTypography.body2.copyWith(
                    color: MyShopColors.textSecondary,
                  ),
                ),
              ),
          ],
          const Divider(height: MyShopSpacing.lg),
          Wrap(
            spacing: MyShopSpacing.sm,
            runSpacing: MyShopSpacing.sm,
            children: [
              OutlinedButton.icon(
                onPressed: onDocuments,
                icon: const Icon(Icons.description_outlined, size: 18),
                label: const Text('Documents'),
              ),
              if (onEdit != null)
                OutlinedButton.icon(
                  onPressed: onEdit,
                  icon: const Icon(Icons.edit_outlined, size: 18),
                  label: const Text('Edit'),
                ),
              if (onRemovalRequest != null)
                TextButton(
                  onPressed: onRemovalRequest,
                  child: const Text('Request removal'),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _VehicleStatusBadge extends StatelessWidget {
  const _VehicleStatusBadge({required this.status});

  final ProviderVehicleApprovalStatus status;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: status.background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        status.label,
        style: MyShopTypography.caption.copyWith(
          color: status.color,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _NoticeBox extends StatelessWidget {
  const _NoticeBox({
    required this.message,
    required this.color,
    required this.background,
  });

  final String message;
  final Color color;
  final Color background;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(MyShopSpacing.sm),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        message,
        style: MyShopTypography.body2.copyWith(color: color),
      ),
    );
  }
}

class _LegacyVehicleNotice extends StatelessWidget {
  const _LegacyVehicleNotice();

  @override
  Widget build(BuildContext context) {
    return const _NoticeBox(
      message:
          'Your previous vehicle or vehicle documents need an admin-assisted migration. Contact support before trying to go online; the app will not guess document ownership.',
      color: MyShopColors.warning,
      background: MyShopColors.warningLight,
    );
  }
}

class _NoVehicles extends StatelessWidget {
  const _NoVehicles();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: MyShopSpacing.xxl),
      child: Column(
        children: [
          const Icon(
            Icons.directions_car_outlined,
            size: 64,
            color: MyShopColors.disabled,
          ),
          const SizedBox(height: MyShopSpacing.md),
          Text('No vehicles added', style: MyShopTypography.h3),
          const SizedBox(height: MyShopSpacing.sm),
          Text(
            'Add a vehicle and its ride categories for Coordinator and Regional Manager review.',
            textAlign: TextAlign.center,
            style: MyShopTypography.body2,
          ),
          const SizedBox(height: MyShopSpacing.xl),
        ],
      ),
    );
  }
}

class _VehicleListSkeleton extends StatelessWidget {
  const _VehicleListSkeleton();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(MyShopSpacing.md),
      children: List.generate(
        3,
        (_) => Container(
          height: 150,
          margin: const EdgeInsets.only(bottom: MyShopSpacing.md),
          decoration: BoxDecoration(
            color: MyShopColors.surfaceGrey,
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
    );
  }
}

extension on ProviderVehicleApprovalStatus {
  String get label => switch (this) {
        ProviderVehicleApprovalStatus.pendingCoordinator =>
          'Awaiting Coordinator',
        ProviderVehicleApprovalStatus.coordinatorApproved => 'Awaiting RM',
        ProviderVehicleApprovalStatus.approved => 'Approved',
        ProviderVehicleApprovalStatus.rejected => 'Rejected',
        ProviderVehicleApprovalStatus.retired => 'Retired',
      };

  Color get color => switch (this) {
        ProviderVehicleApprovalStatus.approved => MyShopColors.success,
        ProviderVehicleApprovalStatus.rejected ||
        ProviderVehicleApprovalStatus.retired =>
          MyShopColors.error,
        _ => MyShopColors.warning,
      };

  Color get background => switch (this) {
        ProviderVehicleApprovalStatus.approved => MyShopColors.successLight,
        ProviderVehicleApprovalStatus.rejected ||
        ProviderVehicleApprovalStatus.retired =>
          MyShopColors.errorLight,
        _ => MyShopColors.warningLight,
      };

  bool canProviderEdit({required bool removalRequested}) =>
      this != ProviderVehicleApprovalStatus.approved &&
      this != ProviderVehicleApprovalStatus.retired &&
      !removalRequested;
}

extension on ProviderVehicleCategoryStatus {
  String get label => switch (this) {
        ProviderVehicleCategoryStatus.pending => 'Pending review',
        ProviderVehicleCategoryStatus.approved => 'Approved',
        ProviderVehicleCategoryStatus.rejected => 'Rejected',
      };

  Color get color => switch (this) {
        ProviderVehicleCategoryStatus.pending => MyShopColors.warning,
        ProviderVehicleCategoryStatus.approved => MyShopColors.success,
        ProviderVehicleCategoryStatus.rejected => MyShopColors.error,
      };
}

String _vehicleActionMessage(ApiException error) => switch (error.errorCode) {
      'VEHICLE_PLATE_IN_USE' =>
        'That registration plate is already assigned to another active vehicle.',
      'VEHICLE_CHANGED_RETRY' =>
        'This vehicle changed on another screen. Reload it before trying again.',
      'VEHICLE_ALREADY_APPROVED' =>
        'An approved vehicle can only be changed by an authorized admin.',
      'INVALID_RIDE_CATEGORY' =>
        'A selected ride category is no longer available. Reload and try again.',
      _ when error.isNetworkError =>
        'No internet connection. Check your network and try again.',
      _ => 'We could not save this vehicle. Please try again.',
    };

String _eligibilityMessage(String reason) => switch (reason) {
      'PROVIDER_APPROVAL_REQUIRED' ||
      'RM_FINAL_APPROVAL_REQUIRED' =>
        'Final provider approval is required.',
      'VEHICLE_NOT_AVAILABLE' =>
        'This vehicle is not approved and available yet.',
      'VEHICLE_RIDE_CATEGORY_NOT_APPROVED' =>
        'At least one active ride category must be approved for this vehicle.',
      'DOCUMENT_MISSING_GHANA_CARD' => 'Upload your Ghana Card.',
      'DOCUMENT_NOT_APPROVED_GHANA_CARD' =>
        'Your Ghana Card is awaiting approval or was rejected.',
      'DOCUMENT_MISSING_DRIVERS_LICENCE' => "Upload your driver's licence.",
      'DOCUMENT_NOT_APPROVED_DRIVERS_LICENCE' =>
        "Your driver's licence is awaiting approval or was rejected.",
      'DOCUMENT_EXPIRY_MISSING_DRIVERS_LICENCE' =>
        "Add the expiry date on your driver's licence.",
      'DOCUMENT_EXPIRED_DRIVERS_LICENCE' =>
        "Your driver's licence has expired.",
      'DOCUMENT_MISSING_PROFILE_PHOTO' => 'Upload a profile photo.',
      'DOCUMENT_NOT_APPROVED_PROFILE_PHOTO' =>
        'Your profile photo is awaiting approval or was rejected.',
      'VEHICLE_DOCUMENT_MISSING_ROADWORTHINESS' =>
        'Upload this vehicle’s roadworthiness certificate.',
      'VEHICLE_DOCUMENT_NOT_APPROVED_ROADWORTHINESS' =>
        'This vehicle’s roadworthiness certificate is awaiting approval or was rejected.',
      'VEHICLE_DOCUMENT_EXPIRY_MISSING_ROADWORTHINESS' =>
        'Add the roadworthiness certificate expiry date.',
      'VEHICLE_DOCUMENT_EXPIRED_ROADWORTHINESS' =>
        'This vehicle’s roadworthiness certificate has expired.',
      'VEHICLE_DOCUMENT_MISSING_INSURANCE' =>
        'Upload this vehicle’s insurance certificate.',
      'VEHICLE_DOCUMENT_NOT_APPROVED_INSURANCE' =>
        'This vehicle’s insurance certificate is awaiting approval or was rejected.',
      'VEHICLE_DOCUMENT_EXPIRY_MISSING_INSURANCE' =>
        'Add the insurance certificate expiry date.',
      'VEHICLE_DOCUMENT_EXPIRED_INSURANCE' =>
        'This vehicle’s insurance certificate has expired.',
      'DOCUMENT_REPLACEMENT_GRACE_EXPIRED' =>
        'A document replacement grace period has ended.',
      'LEGACY_VEHICLE_BACKFILL_REQUIRED' =>
        'Contact support to migrate your previous vehicle records.',
      _ => 'This vehicle is not eligible. Refresh or contact support.',
    };
