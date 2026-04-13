import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../auth/providers/current_user_provider.dart';
import '../providers/verification_provider.dart';

/// Vehicle Information screen — driver-only.
///
/// Figma: node 306:24056
///
/// Layout: hero card with vehicle name + plate, technical specs grid,
/// compliance & docs cards, regulation notice, upload CTA.
class VehicleInformationScreen extends ConsumerWidget {
  const VehicleInformationScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider);
    final dp = user?.driverProfile;
    final completion = ref.watch(profileCompletionProvider);
    final vehicleName = [dp?.vehicleMake, dp?.vehicleModel]
        .where((s) => s != null && s.isNotEmpty)
        .join(' ');
    final plate = dp?.vehiclePlate ?? '--';
    final year = dp?.vehicleYear ?? '--';
    final color = dp?.vehicleColor ?? '--';
    final hasVehicle = dp?.vehicleMake != null;
    return Scaffold(
      backgroundColor: MyShopColors.surfaceWhite,
      appBar: AppBar(
        backgroundColor: MyShopColors.surfaceWhite,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: MyShopColors.textPrimary),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: const Text('Vehicle Info',
            style: TextStyle(
                fontFamily: 'Raleway',
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: MyShopColors.textPrimary)),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: MyShopSpacing.md),
            child: OutlinedButton.icon(
              onPressed: () => context.push('/account/vehicle/edit'),
              icon: const Icon(Icons.edit, size: 14),
              label: const Text('Edit'),
              style: OutlinedButton.styleFrom(
                foregroundColor: MyShopColors.textPrimary,
                side: const BorderSide(color: MyShopColors.divider),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8)),
                textStyle: const TextStyle(
                    fontFamily: 'Raleway',
                    fontSize: 12,
                    fontWeight: FontWeight.w700),
              ),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(MyShopSpacing.md),
        children: [
          // Vehicle hero
          Container(
            height: 180,
            decoration: BoxDecoration(
              color: MyShopColors.surfaceGrey,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Stack(
              children: [
                const Positioned.fill(
                  child: Center(
                    child: Icon(Icons.directions_car,
                        size: 96, color: MyShopColors.disabled),
                  ),
                ),
                Positioned(
                  top: MyShopSpacing.md,
                  right: MyShopSpacing.md,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: MyShopColors.success,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Text('Active',
                        style: TextStyle(
                            fontFamily: 'Raleway',
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: Colors.white)),
                  ),
                ),
                Positioned(
                  left: MyShopSpacing.md,
                  bottom: MyShopSpacing.md,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(hasVehicle ? vehicleName : 'No vehicle added',
                          style: const TextStyle(
                              fontFamily: 'Raleway',
                              fontSize: 22,
                              fontWeight: FontWeight.w900,
                              color: MyShopColors.textPrimary)),
                      const SizedBox(height: 4),
                      Row(children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: MyShopColors.darkSlate,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(plate,
                              style: const TextStyle(
                                  fontFamily: 'Raleway',
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.white)),
                        ),
                      ]),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: MyShopSpacing.lg),

          // Technical specs
          Row(children: [
            const Icon(Icons.directions_car_outlined,
                size: 16, color: MyShopColors.textSecondary),
            const SizedBox(width: 6),
            const Text('Technical Specs',
                style: TextStyle(
                    fontFamily: 'Raleway',
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: MyShopColors.textPrimary)),
          ]),
          const SizedBox(height: MyShopSpacing.sm),
          Row(children: [
            Expanded(child: _SpecCard(icon: Icons.palette_outlined, label: 'COLOR', value: color)),
            const SizedBox(width: 8),
            Expanded(child: _SpecCard(icon: Icons.directions_car_outlined, label: 'MAKE', value: dp?.vehicleMake ?? '--')),
          ]),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(child: _SpecCard(icon: Icons.calendar_today_outlined, label: 'YEAR', value: year)),
            const SizedBox(width: 8),
            Expanded(child: _SpecCard(icon: Icons.badge_outlined, label: 'MODEL', value: dp?.vehicleModel ?? '--')),
          ]),
          const SizedBox(height: MyShopSpacing.lg),

          // Compliance & Docs
          Container(
            padding: const EdgeInsets.all(MyShopSpacing.md),
            decoration: BoxDecoration(
              color: MyShopColors.surfaceWhite,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: MyShopColors.divider),
            ),
            child: Column(children: [
              Row(children: [
                const Icon(Icons.description_outlined,
                    size: 16, color: MyShopColors.textSecondary),
                const SizedBox(width: 6),
                const Text('Compliance & Docs',
                    style: TextStyle(
                        fontFamily: 'Raleway',
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: MyShopColors.textPrimary)),
                const Spacer(),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                      color: MyShopColors.surfaceGrey,
                      borderRadius: BorderRadius.circular(10)),
                  child: Text('2 Active',
                      style: MyShopTypography.body2.copyWith(
                          fontSize: 10, fontWeight: FontWeight.w700)),
                ),
              ]),
              const SizedBox(height: 12),
              _ComplianceDoc(
                icon: Icons.shield_outlined,
                iconBg: MyShopColors.successLight,
                iconColor: MyShopColors.success,
                title: 'Commercial Insurance',
                expiry: 'Expires: Oct 12, 2025',
                status: 'Valid',
                statusColor: MyShopColors.success,
              ),
              const SizedBox(height: 8),
              _ComplianceDoc(
                icon: Icons.description_outlined,
                iconBg: MyShopColors.warningLight,
                iconColor: MyShopColors.warning,
                title: 'Vehicle Registration',
                expiry: 'Expires: Mar 04, 2024',
                status: 'Expiring Soon',
                statusColor: MyShopColors.warning,
              ),
            ]),
          ),
          const SizedBox(height: MyShopSpacing.lg),

          // Regulation notice
          Container(
            padding: const EdgeInsets.all(MyShopSpacing.md),
            decoration: BoxDecoration(
              color: MyShopColors.primaryGoldLight,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                  color: MyShopColors.primaryGold.withValues(alpha: 0.3)),
            ),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Icon(Icons.info_outline,
                  size: 18, color: MyShopColors.primaryGold),
              const SizedBox(width: 8),
              Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                    const Text('Regulation Notice',
                        style: TextStyle(
                            fontFamily: 'Raleway',
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: MyShopColors.textPrimary)),
                    const SizedBox(height: 2),
                    Text(
                        'In accordance with Ghana GPRTU guidelines, all commercial vehicles must undergo quarterly safety inspections. Your next inspection is due in 14 days.',
                        style: MyShopTypography.body2
                            .copyWith(fontSize: 11, height: 1.4)),
                    const SizedBox(height: 6),
                    Row(children: [
                      Text('Schedule Inspection',
                          style: MyShopTypography.body2.copyWith(
                              fontSize: 11,
                              color: MyShopColors.primaryGold,
                              fontWeight: FontWeight.w700)),
                      const Icon(Icons.chevron_right,
                          size: 14, color: MyShopColors.primaryGold),
                    ]),
                  ])),
            ]),
          ),
          const SizedBox(height: MyShopSpacing.lg),

          ElevatedButton.icon(
            onPressed: () async {
              final file =
                  await MediaPickerHelper.pickDocumentWithCamera(context);
              if (file != null && context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content:
                        Text('Selected: ${file.path.split('/').last}'),
                  ),
                );
              }
            },
            icon: const Icon(Icons.add, size: 16),
            label: const Text('Upload New Document'),
            style: ElevatedButton.styleFrom(
              backgroundColor: MyShopColors.darkSlate,
              foregroundColor: MyShopColors.textOnPrimary,
              minimumSize: const Size(double.infinity, 52),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
              textStyle: const TextStyle(
                  fontFamily: 'Raleway',
                  fontSize: 14,
                  fontWeight: FontWeight.w700),
            ),
          ),
          const SizedBox(height: 8),
          Center(
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(
                completion.isComplete
                    ? Icons.check_circle
                    : Icons.info_outline,
                size: 14,
                color: completion.isComplete
                    ? MyShopColors.success
                    : MyShopColors.primaryGold,
              ),
              const SizedBox(width: 4),
              Text('Profile ${completion.percentage}% complete',
                  style: MyShopTypography.body2.copyWith(fontSize: 11)),
            ]),
          ),
          const SizedBox(height: MyShopSpacing.xxl),
        ],
      ),
    );
  }
}

class _SpecCard extends StatelessWidget {
  const _SpecCard(
      {required this.icon, required this.label, required this.value});
  final IconData icon;
  final String label;
  final String value;
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: MyShopColors.surfaceWhite,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: MyShopColors.divider),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(icon, size: 14, color: MyShopColors.textSecondary),
          const SizedBox(width: 4),
          Text(label, style: MyShopTypography.overline.copyWith(fontSize: 9)),
        ]),
        const SizedBox(height: 6),
        Text(value,
            style: const TextStyle(
                fontFamily: 'Raleway',
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: MyShopColors.textPrimary)),
      ]),
    );
  }
}

class _ComplianceDoc extends StatelessWidget {
  const _ComplianceDoc({
    required this.icon,
    required this.iconBg,
    required this.iconColor,
    required this.title,
    required this.expiry,
    required this.status,
    required this.statusColor,
  });
  final IconData icon;
  final Color iconBg;
  final Color iconColor;
  final String title;
  final String expiry;
  final String status;
  final Color statusColor;
  @override
  Widget build(BuildContext context) {
    return Row(children: [
      Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
              color: iconBg, borderRadius: BorderRadius.circular(8)),
          child: Icon(icon, size: 16, color: iconColor)),
      const SizedBox(width: 10),
      Expanded(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title,
            style: const TextStyle(
                fontFamily: 'Raleway',
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: MyShopColors.textPrimary)),
        Row(children: [
          const Icon(Icons.access_time,
              size: 11, color: MyShopColors.textSecondary),
          const SizedBox(width: 4),
          Text(expiry, style: MyShopTypography.caption.copyWith(fontSize: 10)),
        ]),
      ])),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
            color: statusColor.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(6)),
        child: Text(status,
            style: TextStyle(
                fontFamily: 'Raleway',
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: statusColor)),
      ),
      const SizedBox(width: 4),
      Text('View',
          style: MyShopTypography.body2.copyWith(
              fontSize: 11,
              color: MyShopColors.primaryGold,
              fontWeight: FontWeight.w700)),
    ]);
  }
}
