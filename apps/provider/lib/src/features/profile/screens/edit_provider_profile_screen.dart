import 'dart:io';

import 'package:api_client/api_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../auth/providers/auth_controller.dart';
import '../../auth/providers/current_user_provider.dart';
import '../providers/provider_type_provider.dart';
import '../providers/verification_provider.dart';

/// Edit Profile screen — editable name & email, plus read-only verification,
/// vehicle, documents, ops chat, dispute, and quick links.
///
/// Figma: node 219:13295
/// PRD Reference: PRD 5.4
class EditProviderProfileScreen extends ConsumerStatefulWidget {
  const EditProviderProfileScreen({super.key});

  @override
  ConsumerState<EditProviderProfileScreen> createState() =>
      _EditProviderProfileScreenState();
}

class _EditProviderProfileScreenState
    extends ConsumerState<EditProviderProfileScreen> {
  late final TextEditingController _nameController;
  late final TextEditingController _emailController;
  bool _isSaving = false;
  bool _hasChanges = false;
  bool _isUploadingPhoto = false;
  File? _localPhoto;

  @override
  void initState() {
    super.initState();
    final user = ref.read(currentUserProvider);
    _nameController = TextEditingController(text: user?.fullName ?? '');
    _emailController = TextEditingController(text: user?.email ?? '');
    _nameController.addListener(_onFieldChanged);
    _emailController.addListener(_onFieldChanged);
  }

  void _onFieldChanged() {
    final user = ref.read(currentUserProvider);
    final changed = _nameController.text.trim() != (user?.fullName ?? '') ||
        _emailController.text.trim() != (user?.email ?? '');
    if (changed != _hasChanges) {
      setState(() => _hasChanges = changed);
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _pickAndUploadPhoto() async {
    final file = await MediaPickerHelper.pickImage(context);
    if (file == null || !mounted) return;

    setState(() {
      _isUploadingPhoto = true;
      _localPhoto = file;
    });

    final user = ref.read(currentUserProvider);
    final providerType = user?.isDriver == true ? 'driver' : 'artisan';

    final error =
        await ref.read(documentUploadProvider.notifier).upload(
              providerType: providerType,
              documentType: DocumentType.profilePhoto,
              file: file,
            );

    if (!mounted) return;

    if (error != null) {
      setState(() {
        _isUploadingPhoto = false;
        _localPhoto = null;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error)),
      );
    } else {
      // Refresh the user profile so the new photo URL appears everywhere
      await ref.read(authControllerProvider.notifier).updateProfile(
            const UpdateProfileRequest(),
          );
      if (!mounted) return;
      setState(() => _isUploadingPhoto = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Profile photo updated')),
      );
    }
  }

  Future<void> _saveProfile() async {
    final name = _nameController.text.trim();
    final email = _emailController.text.trim();

    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Name cannot be empty')),
      );
      return;
    }

    setState(() => _isSaving = true);

    final error =
        await ref.read(authControllerProvider.notifier).updateProfile(
              UpdateProfileRequest(
                fullName: name,
                email: email.isNotEmpty ? email : null,
              ),
            );

    if (!mounted) return;
    setState(() {
      _isSaving = false;
      _hasChanges = false;
    });

    if (error != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error)),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Profile updated')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(currentUserProvider);
    final providerType = ref.watch(providerTypeProvider);
    final isDriver = providerType.isDriver;
    final dp = user?.driverProfile;
    final ap = user?.artisanProfile;
    final kycStatus = isDriver
        ? (dp?.kycStatus ?? 'pending')
        : (ap?.kycStatus ?? 'pending');
    final policeStatus = isDriver
        ? (dp?.policeCheckStatus ?? 'pending')
        : (ap?.policeCheckStatus ?? 'pending');
    final photoUrl =
        isDriver ? dp?.profilePhotoUrl : ap?.profilePhotoUrl;

    // Vehicle info (driver only)
    final vehicleName = isDriver
        ? [dp?.vehicleMake, dp?.vehicleModel]
            .where((s) => s != null && s.isNotEmpty)
            .join(' ')
        : null;
    final vehiclePlate = dp?.vehiclePlate;
    final vehicleColor = dp?.vehicleColor;

    return Scaffold(
      backgroundColor: MyShopColors.surfaceWhite,
      appBar: AppBar(
        backgroundColor: MyShopColors.surfaceWhite,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: MyShopColors.textPrimary),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: const Align(
          alignment: Alignment.centerLeft,
          child: Text('Edit Profile',
              style: TextStyle(
                  fontFamily: 'Raleway',
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: MyShopColors.textPrimary)),
        ),
        titleSpacing: 0,
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: MyShopSpacing.md),
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: kycStatus == 'approved'
                    ? MyShopColors.successLight
                    : MyShopColors.warningLight,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    kycStatus == 'approved'
                        ? Icons.check_circle_outline
                        : Icons.access_time,
                    size: 12,
                    color: kycStatus == 'approved'
                        ? MyShopColors.success
                        : MyShopColors.warning,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    'KYC ${_capitalize(kycStatus)}',
                    style: TextStyle(
                        fontFamily: 'Raleway',
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: kycStatus == 'approved'
                            ? MyShopColors.success
                            : MyShopColors.warning,
                        letterSpacing: 0.4),
                  ),
                ],
              ),
            ),
          ),
        ],
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(0.5),
          child: Divider(
              height: 0.5, thickness: 0.5, color: MyShopColors.divider),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(MyShopSpacing.md),
        children: [
          // ── 1. Identity card with editable fields ──
          _IdentityCard(
            photoUrl: photoUrl,
            localPhoto: _localPhoto,
            isUploadingPhoto: _isUploadingPhoto,
            onPhotoTap: _pickAndUploadPhoto,
            nameController: _nameController,
            emailController: _emailController,
            phone: user?.phone ?? '',
          ),
          const SizedBox(height: MyShopSpacing.md),

          // ── Save button ──
          ElevatedButton(
            onPressed: _hasChanges && !_isSaving ? _saveProfile : null,
            style: ElevatedButton.styleFrom(
              backgroundColor: MyShopColors.primaryGold,
              foregroundColor: MyShopColors.textOnPrimary,
              disabledBackgroundColor: MyShopColors.surfaceGrey,
              disabledForegroundColor: MyShopColors.textSecondary,
              minimumSize: const Size(double.infinity, 52),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
              textStyle: const TextStyle(
                  fontFamily: 'Raleway',
                  fontSize: 14,
                  fontWeight: FontWeight.w700),
            ),
            child: _isSaving
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: MyShopColors.textOnPrimary,
                    ),
                  )
                : const Text('Save Changes'),
          ),
          const SizedBox(height: MyShopSpacing.lg),

          // ── 2. Verification status ──
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('VERIFICATION STATUS',
                  style: TextStyle(
                      fontFamily: 'Raleway',
                      fontSize: 12,
                      fontWeight: FontWeight.w900,
                      color: MyShopColors.textSecondary,
                      letterSpacing: 1.0)),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: MyShopColors.surfaceGrey,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Text('Update Info',
                    style: TextStyle(
                        fontFamily: 'Raleway',
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: MyShopColors.textPrimary)),
              ),
            ],
          ),
          const SizedBox(height: MyShopSpacing.sm),
          Container(
            decoration: BoxDecoration(
              color: MyShopColors.surfaceWhite,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: MyShopColors.divider),
            ),
            child: Column(
              children: [
                _VerificationRow(
                  icon: Icons.shield_outlined,
                  title: 'SMILE IDENTITY KYC',
                  status: _capitalize(kycStatus),
                  isApproved: kycStatus == 'approved',
                ),
                const Divider(
                    height: 1,
                    thickness: 0.5,
                    color: MyShopColors.divider,
                    indent: 16,
                    endIndent: 16),
                _VerificationRow(
                  icon: Icons.balance,
                  title: 'POLICE BACKGROUND CHECK',
                  status: _capitalize(policeStatus),
                  isApproved: policeStatus == 'approved',
                ),
              ],
            ),
          ),
          const SizedBox(height: MyShopSpacing.lg),

          // ── 3. Vehicle Details (driver) or Service Categories (artisan) ──
          if (isDriver) ...[
            const Text('VEHICLE DETAILS',
                style: TextStyle(
                    fontFamily: 'Raleway',
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                    color: MyShopColors.textSecondary,
                    letterSpacing: 1.0)),
            const SizedBox(height: MyShopSpacing.sm),
            Container(
              padding: const EdgeInsets.all(MyShopSpacing.md),
              decoration: BoxDecoration(
                color: MyShopColors.surfaceWhite,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: MyShopColors.divider),
              ),
              child: vehicleName != null && vehicleName.isNotEmpty
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(children: [
                          const Icon(Icons.directions_car_outlined,
                              size: 18, color: MyShopColors.darkSlate),
                          const SizedBox(width: 8),
                          Text(
                              '$vehicleName${dp?.vehicleYear != null ? ' ${dp!.vehicleYear}' : ''}',
                              style: const TextStyle(
                                  fontFamily: 'Raleway',
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                  color: MyShopColors.textPrimary)),
                        ]),
                        const SizedBox(height: 12),
                        if (vehiclePlate != null)
                          _VehicleDetail(
                              label: 'License Plate', value: vehiclePlate),
                        if (vehicleColor != null)
                          _VehicleDetail(label: 'Color', value: vehicleColor),
                        if (dp?.licenceNumber != null)
                          _VehicleDetail(
                              label: 'Licence #', value: dp!.licenceNumber!),
                      ],
                    )
                  : Padding(
                      padding: const EdgeInsets.symmetric(vertical: 20),
                      child: Center(
                        child: Column(
                          children: [
                            const Icon(Icons.directions_car_outlined,
                                size: 32, color: MyShopColors.textSecondary),
                            const SizedBox(height: MyShopSpacing.sm),
                            Text('No vehicle added yet',
                                style: MyShopTypography.body2.copyWith(
                                    color: MyShopColors.textSecondary)),
                          ],
                        ),
                      ),
                    ),
            ),
          ] else ...[
            const Text('SERVICE CATEGORIES',
                style: TextStyle(
                    fontFamily: 'Raleway',
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                    color: MyShopColors.textSecondary,
                    letterSpacing: 1.0)),
            const SizedBox(height: MyShopSpacing.sm),
            Container(
              padding: const EdgeInsets.all(MyShopSpacing.md),
              decoration: BoxDecoration(
                color: MyShopColors.surfaceWhite,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: MyShopColors.divider),
              ),
              child: ap?.serviceCategories != null &&
                      ap!.serviceCategories!.isNotEmpty
                  ? Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: ap.serviceCategories!
                          .map((c) => Chip(
                                label: Text(c.category.name),
                                backgroundColor: MyShopColors.surfaceGrey,
                                labelStyle: MyShopTypography.body2.copyWith(
                                    fontWeight: FontWeight.w600),
                              ))
                          .toList(),
                    )
                  : Padding(
                      padding: const EdgeInsets.symmetric(vertical: 20),
                      child: Center(
                        child: Column(
                          children: [
                            const Icon(Icons.work_outline,
                                size: 32, color: MyShopColors.textSecondary),
                            const SizedBox(height: MyShopSpacing.sm),
                            Text('No categories set',
                                style: MyShopTypography.body2.copyWith(
                                    color: MyShopColors.textSecondary)),
                          ],
                        ),
                      ),
                    ),
            ),
          ],
          const SizedBox(height: MyShopSpacing.lg),

          // ── 4. Quick links ──
          Row(children: [
            Expanded(
                child: _QuickLink(
                    icon: Icons.help_outline, label: 'HELP CENTER')),
            const SizedBox(width: MyShopSpacing.md),
            Expanded(
                child: _QuickLink(
                    icon: Icons.open_in_new, label: 'LEGAL & TERMS')),
          ]),
          const SizedBox(height: MyShopSpacing.xxl),
        ],
      ),
    );
  }
}

// ─── Identity Card ──────────────────────────────────────────────────────────

class _IdentityCard extends StatelessWidget {
  const _IdentityCard({
    required this.nameController,
    required this.emailController,
    required this.phone,
    required this.onPhotoTap,
    this.photoUrl,
    this.localPhoto,
    this.isUploadingPhoto = false,
  });

  final TextEditingController nameController;
  final TextEditingController emailController;
  final String phone;
  final String? photoUrl;
  final File? localPhoto;
  final bool isUploadingPhoto;
  final VoidCallback onPhotoTap;

  @override
  Widget build(BuildContext context) {
    // Show local file first (instant feedback), fall back to network URL
    final ImageProvider? avatarImage = localPhoto != null
        ? FileImage(localPhoto!)
        : photoUrl != null
            ? NetworkImage(photoUrl!)
            : null;

    return Container(
      decoration: BoxDecoration(
        color: MyShopColors.surfaceWhite,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: MyShopColors.divider),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          Container(height: 6, color: MyShopColors.darkSlate),
          Padding(
            padding: const EdgeInsets.all(MyShopSpacing.md),
            child: Column(
              children: [
                // Avatar
                Center(
                  child: GestureDetector(
                    onTap: isUploadingPhoto ? null : onPhotoTap,
                    child: Stack(
                      children: [
                        CircleAvatar(
                          radius: 40,
                          backgroundColor: const Color(0xFFFCEAE1),
                          backgroundImage: avatarImage,
                          child: avatarImage == null
                              ? const Icon(Icons.person,
                                  size: 40, color: MyShopColors.textSecondary)
                              : null,
                        ),
                        if (isUploadingPhoto)
                          Positioned.fill(
                            child: Container(
                              decoration: BoxDecoration(
                                color: Colors.black38,
                                shape: BoxShape.circle,
                              ),
                              child: const Center(
                                child: SizedBox(
                                  width: 24,
                                  height: 24,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2.5,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        Positioned(
                          bottom: 0,
                          right: 0,
                          child: Container(
                            width: 28,
                            height: 28,
                            decoration: BoxDecoration(
                              color: MyShopColors.primaryGold,
                              shape: BoxShape.circle,
                              border: Border.all(
                                  color: MyShopColors.surfaceWhite, width: 2),
                            ),
                            child: const Icon(Icons.camera_alt,
                                size: 14, color: Colors.white),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: MyShopSpacing.lg),

                // Full Name field
                _ProfileField(
                  label: 'Full Name',
                  controller: nameController,
                  icon: Icons.person_outline,
                ),
                const SizedBox(height: MyShopSpacing.md),

                // Email field
                _ProfileField(
                  label: 'Email',
                  controller: emailController,
                  icon: Icons.email_outlined,
                  keyboardType: TextInputType.emailAddress,
                ),
                const SizedBox(height: MyShopSpacing.md),

                // Phone (read-only)
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: MyShopSpacing.md, vertical: 14),
                  decoration: BoxDecoration(
                    color: MyShopColors.surfaceGrey,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.phone_outlined,
                          size: 18, color: MyShopColors.textSecondary),
                      const SizedBox(width: 12),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Phone',
                              style: MyShopTypography.body2.copyWith(
                                  fontSize: 11,
                                  color: MyShopColors.textSecondary)),
                          Text(phone,
                              style: const TextStyle(
                                  fontFamily: 'Raleway',
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                  color: MyShopColors.textPrimary)),
                        ],
                      ),
                      const Spacer(),
                      const Icon(Icons.lock_outline,
                          size: 14, color: MyShopColors.textSecondary),
                    ],
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

// ─── Profile text field ─────────────────────────────────────────────────────

class _ProfileField extends StatelessWidget {
  const _ProfileField({
    required this.label,
    required this.controller,
    required this.icon,
    this.keyboardType,
  });

  final String label;
  final TextEditingController controller;
  final IconData icon;
  final TextInputType? keyboardType;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      style: const TextStyle(
        fontFamily: 'Raleway',
        fontSize: 14,
        fontWeight: FontWeight.w700,
        color: MyShopColors.textPrimary,
      ),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: MyShopTypography.body2.copyWith(
            fontSize: 12, color: MyShopColors.textSecondary),
        prefixIcon: Icon(icon, size: 18, color: MyShopColors.textSecondary),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: MyShopColors.divider),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: MyShopColors.divider),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide:
              const BorderSide(color: MyShopColors.primaryGold, width: 1.5),
        ),
      ),
    );
  }
}

// ─── Verification Row ───────────────────────────────────────────────────────

class _VerificationRow extends StatelessWidget {
  const _VerificationRow({
    required this.icon,
    required this.title,
    required this.status,
    required this.isApproved,
  });
  final IconData icon;
  final String title;
  final String status;
  final bool isApproved;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(MyShopSpacing.md),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: isApproved
                  ? MyShopColors.successLight
                  : MyShopColors.warningLight,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon,
                size: 18,
                color: isApproved
                    ? MyShopColors.success
                    : MyShopColors.warning),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(
                        fontFamily: 'Raleway',
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: MyShopColors.textSecondary,
                        letterSpacing: 0.5)),
                const SizedBox(height: 2),
                Text(status,
                    style: const TextStyle(
                        fontFamily: 'Raleway',
                        fontSize: 14,
                        fontWeight: FontWeight.w900,
                        color: MyShopColors.textPrimary)),
              ],
            ),
          ),
          Container(
            width: 22,
            height: 22,
            decoration: BoxDecoration(
              color: isApproved
                  ? MyShopColors.successLight
                  : MyShopColors.surfaceGrey,
              shape: BoxShape.circle,
              border: Border.all(
                  color: isApproved
                      ? MyShopColors.success
                      : MyShopColors.divider),
            ),
            child: Icon(
              isApproved ? Icons.check : Icons.access_time,
              size: 14,
              color: isApproved
                  ? MyShopColors.success
                  : MyShopColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Vehicle Detail row ─────────────────────────────────────────────────────

class _VehicleDetail extends StatelessWidget {
  const _VehicleDetail({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: MyShopTypography.body2.copyWith(
                  fontSize: 13, color: MyShopColors.textSecondary)),
          Text(value,
              style: const TextStyle(
                  fontFamily: 'Raleway',
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: MyShopColors.textPrimary)),
        ],
      ),
    );
  }
}

// ─── Quick link tile ────────────────────────────────────────────────────────

class _QuickLink extends StatelessWidget {
  const _QuickLink({required this.icon, required this.label});
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 18),
      decoration: BoxDecoration(
        color: MyShopColors.surfaceWhite,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: MyShopColors.divider),
      ),
      child: Column(
        children: [
          Icon(icon, size: 22, color: MyShopColors.textPrimary),
          const SizedBox(height: 6),
          Text(label,
              style: const TextStyle(
                  fontFamily: 'Raleway',
                  fontSize: 11,
                  fontWeight: FontWeight.w900,
                  color: MyShopColors.textPrimary,
                  letterSpacing: 0.6)),
        ],
      ),
    );
  }
}

// ─── Helpers ────────────────────────────────────────────────────────────────

String _capitalize(String s) {
  if (s.isEmpty) return s;
  return s[0].toUpperCase() + s.substring(1);
}
