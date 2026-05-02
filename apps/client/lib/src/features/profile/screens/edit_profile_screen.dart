import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:shared_ui/shared_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/providers/auth_controller.dart';
import '../providers/edit_profile_provider.dart';
import '../providers/photo_upload_provider.dart';

// ── Screen ────────────────────────────────────────────────────────────────────
// PRD 4.11 — Edit full name and email. Phone requires OTP flow. KYC is separate.
// API: PUT /users/me  { fullName?, email? }

class EditProfileScreen extends ConsumerStatefulWidget {
  const EditProfileScreen({super.key});

  @override
  ConsumerState<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends ConsumerState<EditProfileScreen> {
  late final TextEditingController _nameCtrl;
  late final TextEditingController _emailCtrl;

  late final FocusNode _nameFocus;
  late final FocusNode _emailFocus;

  bool _isUploadingPhoto = false;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController();
    _emailCtrl = TextEditingController();

    _nameFocus = FocusNode();
    _emailFocus = FocusNode();

    for (final fn in [_nameFocus, _emailFocus]) {
      fn.addListener(() => setState(() {}));
    }

    WidgetsBinding.instance.addPostFrameCallback((_) => _syncControllers());
  }

  void _syncControllers() {
    final s = ref.read(editProfileProvider);
    if (_nameCtrl.text != s.fullName) _nameCtrl.text = s.fullName;
    if (_emailCtrl.text != s.email) _emailCtrl.text = s.email;
  }

  /// Profile photo flow:
  ///   1. Pick an image from camera/gallery.
  ///   2. Show it instantly via [localProfilePhotoProvider] while we upload.
  ///   3. Run the 4-step backend flow (presign → upload → confirm → persist
  ///      onto the Client row) via [profilePhotoUploadProvider].
  ///   4. On success: store the hosted URL locally + refresh the auth
  ///      profile so the rest of the app reflects it. On failure: clear
  ///      the local preview and surface the error.
  Future<void> _pickAndUploadPhoto() async {
    final file = await MediaPickerHelper.pickImage(context);
    if (file == null || !mounted) return;

    ref.read(localProfilePhotoProvider.notifier).setLocalFile(file);
    setState(() => _isUploadingPhoto = true);

    final error =
        await ref.read(profilePhotoUploadProvider.notifier).upload(file);
    if (!mounted) return;

    if (error != null) {
      ref.read(localProfilePhotoProvider.notifier).clear();
      setState(() => _isUploadingPhoto = false);
      MyShopToast.show(
        context,
        message: error,
        type: ToastType.error,
        duration: const Duration(seconds: 6),
      );
      return;
    }

    // Persist the hosted URL so the photo survives an app restart even
    // before the next /users/me fetch lands.
    final remoteUrl = ref.read(profilePhotoUploadProvider).remoteUrl;
    if (remoteUrl != null) {
      await ref
          .read(localProfilePhotoProvider.notifier)
          .setCloudinaryUrl(remoteUrl);
    }
    // Pull the updated profile so the avatar URL flows back through
    // editProfileProvider on the next rebuild.
    await ref.read(clientAuthControllerProvider.notifier).refreshProfile();
    if (!mounted) return;

    setState(() => _isUploadingPhoto = false);
    MyShopToast.show(context, message: 'Profile photo updated');
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _nameFocus.dispose();
    _emailFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final w = size.width;
    final h = size.height;

    // Sync controllers when provider state changes (e.g. initial load).
    ref.listen<EditProfileState>(editProfileProvider, (prev, next) {
      if (prev?.fullName != next.fullName && _nameCtrl.text != next.fullName) {
        _nameCtrl.text = next.fullName;
      }
      if (prev?.email != next.email && _emailCtrl.text != next.email) {
        _emailCtrl.text = next.email;
      }
      // Show toast on successful save.
      if (prev?.isSaved == false && next.isSaved == true) {
        MyShopToast.show(context, message: 'Profile saved!');
      }
    });

    final state = ref.watch(editProfileProvider);
    final photoState = ref.watch(localProfilePhotoProvider);

    return Scaffold(
      backgroundColor: MyShopColors.offWhite,
      body: Column(
        children: [
          _AppBar(w: w, h: h),
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                children: [
                  _PhotoSection(
                    avatarUrl: state.avatarUrl,
                    localFile: photoState.localFile,
                    cloudinaryUrl: photoState.cloudinaryUrl,
                    isUploading: _isUploadingPhoto,
                    onPhotoTap: _pickAndUploadPhoto,
                    w: w,
                    h: h,
                  ),
                  SizedBox(height: h * 0.028),
                  _FormCard(
                    w: w,
                    h: h,
                    state: state,
                    nameCtrl: _nameCtrl,
                    emailCtrl: _emailCtrl,
                    nameFocus: _nameFocus,
                    emailFocus: _emailFocus,
                  ),
                  if (state.emailChanged) ...[
                    SizedBox(height: h * 0.014),
                    _WarningBox(w: w, h: h),
                  ],
                  if (state.errorMessage != null) ...[
                    SizedBox(height: h * 0.014),
                    _ErrorBanner(message: state.errorMessage!, w: w, h: h),
                  ],
                  SizedBox(height: h * 0.022),
                ],
              ),
            ),
          ),
          _BottomBar(w: w, h: h, state: state),
        ],
      ),
    );
  }
}

// ── App Bar ───────────────────────────────────────────────────────────────────

class _AppBar extends StatelessWidget {
  final double w, h;
  const _AppBar({required this.w, required this.h});

  @override
  Widget build(BuildContext context) {
    final topPad = MediaQuery.paddingOf(context).top;
    return Container(
      color: MyShopColors.surfaceWhite,
      padding: EdgeInsets.only(
        top: topPad + h * 0.010,
        bottom: h * 0.017,
        left: w * 0.041,
        right: w * 0.041,
      ),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => Navigator.of(context).maybePop(),
            behavior: HitTestBehavior.opaque,
            child: Padding(
              padding: EdgeInsets.only(right: w * 0.031),
              child: Icon(Icons.arrow_back,
                  size: w * 0.056, color: MyShopColors.textPrimary),
            ),
          ),
          Text(
            'Edit Profile',
            style: TextStyle(
              fontSize: w * 0.051,
              fontWeight: FontWeight.w700,
              color: MyShopColors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Photo Section ─────────────────────────────────────────────────────────────

class _PhotoSection extends StatelessWidget {
  final String? avatarUrl;
  final File? localFile;
  final String? cloudinaryUrl;
  final bool isUploading;
  final VoidCallback onPhotoTap;
  final double w, h;

  const _PhotoSection({
    required this.avatarUrl,
    required this.localFile,
    required this.cloudinaryUrl,
    required this.isUploading,
    required this.onPhotoTap,
    required this.w,
    required this.h,
  });

  @override
  Widget build(BuildContext context) {
    // Priority: local file (instant preview) → persisted Cloudinary URL → backend URL
    final displayUrl = cloudinaryUrl ?? avatarUrl;

    return Container(
      color: MyShopColors.surfaceWhite,
      width: double.infinity,
      padding: EdgeInsets.symmetric(vertical: h * 0.028),
      child: Column(
        children: [
          Stack(
            alignment: Alignment.bottomRight,
            children: [
              // Avatar
              Container(
                width: w * 0.256,
                height: w * 0.256,
                decoration: const BoxDecoration(
                  color: MyShopColors.primaryGoldLight,
                  shape: BoxShape.circle,
                ),
                child: ClipOval(
                  child: isUploading
                      ? const Center(
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: MyShopColors.primaryGold,
                          ),
                        )
                      : localFile != null
                          ? Image.file(localFile!, fit: BoxFit.cover)
                          : displayUrl != null && displayUrl.isNotEmpty
                              ? CachedNetworkImage(
                                  imageUrl: displayUrl,
                                  fit: BoxFit.cover,
                                  placeholder: (_, __) => const Center(
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: MyShopColors.primaryGold,
                                    ),
                                  ),
                                  errorWidget: (_, __, ___) => Icon(
                                    Icons.person_rounded,
                                    size: w * 0.154,
                                    color: const Color(0xFF78909C),
                                  ),
                                )
                              : Icon(
                                  Icons.person_rounded,
                                  size: w * 0.154,
                                  color: const Color(0xFF78909C),
                                ),
                ),
              ),
              // Camera badge
              GestureDetector(
                onTap: isUploading ? null : onPhotoTap,
                child: Container(
                  width: w * 0.082,
                  height: w * 0.082,
                  decoration: BoxDecoration(
                    color: isUploading
                        ? MyShopColors.darkSlate.withValues(alpha: 0.5)
                        : MyShopColors.darkSlate,
                    shape: BoxShape.circle,
                    border: Border.all(
                        color: MyShopColors.surfaceWhite, width: 2.5),
                  ),
                  child: Icon(Icons.photo_camera_rounded,
                      size: w * 0.041, color: MyShopColors.surfaceWhite),
                ),
              ),
            ],
          ),
          SizedBox(height: h * 0.011),
          GestureDetector(
            onTap: isUploading ? null : onPhotoTap,
            behavior: HitTestBehavior.opaque,
            child: Text(
              isUploading ? 'Uploading...' : 'Change Profile Photo',
              style: TextStyle(
                fontSize: w * 0.033,
                fontWeight: FontWeight.w500,
                color: isUploading
                    ? MyShopColors.textHint
                    : MyShopColors.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Form Card ─────────────────────────────────────────────────────────────────

class _FormCard extends ConsumerWidget {
  final double w, h;
  final EditProfileState state;
  final TextEditingController nameCtrl, emailCtrl;
  final FocusNode nameFocus, emailFocus;

  const _FormCard({
    required this.w,
    required this.h,
    required this.state,
    required this.nameCtrl,
    required this.emailCtrl,
    required this.nameFocus,
    required this.emailFocus,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(editProfileProvider.notifier);

    return Container(
      color: MyShopColors.surfaceWhite,
      padding: EdgeInsets.symmetric(
        horizontal: w * 0.041,
        vertical: h * 0.022,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Full Name ──────────────────────────────────────────────────────
          _FieldLabel(label: 'FULL NAME', w: w),
          SizedBox(height: h * 0.008),
          _ProfileInput(
            controller: nameCtrl,
            focusNode: nameFocus,
            isActive: nameFocus.hasFocus,
            hintText: 'Enter your full name',
            onChanged: notifier.updateFullName,
            w: w,
            h: h,
          ),
          SizedBox(height: h * 0.019),

          // ── Email ──────────────────────────────────────────────────────────
          Row(
            children: [
              _FieldLabel(label: 'EMAIL', w: w),
              const Spacer(),
              if (state.emailChanged)
                GestureDetector(
                  onTap: () => MyShopToast.show(
                    context,
                    message: 'Email verification by OTP is on the way. '
                        "We'll send a code to the new address as soon as the flow ships.",
                    duration: const Duration(seconds: 5),
                  ),
                  behavior: HitTestBehavior.opaque,
                  child: Text(
                    'VERIFY',
                    style: TextStyle(
                      fontSize: w * 0.028,
                      fontWeight: FontWeight.w800,
                      color: MyShopColors.primaryGold,
                      letterSpacing: 0.6,
                    ),
                  ),
                ),
            ],
          ),
          SizedBox(height: h * 0.008),
          _ProfileInput(
            controller: emailCtrl,
            focusNode: emailFocus,
            isActive: emailFocus.hasFocus || state.emailChanged,
            hintText: 'Enter your email',
            keyboardType: TextInputType.emailAddress,
            onChanged: notifier.updateEmail,
            w: w,
            h: h,
          ),
          SizedBox(height: h * 0.019),

          // ── Phone Number (read-only) ───────────────────────────────────────
          _FieldLabel(label: 'PHONE NUMBER', w: w),
          SizedBox(height: h * 0.008),
          _ReadOnlyField(
            value: state.phoneNumber,
            hint: 'Phone number',
            badge: _StatusBadge.verified,
            note: 'Contact support to change your phone number',
            w: w,
            h: h,
          ),
          SizedBox(height: h * 0.019),

          // ── Ghana Card KYC status (read-only) ─────────────────────────────
          _FieldLabel(label: 'GHANA CARD', w: w),
          SizedBox(height: h * 0.008),
          _ReadOnlyField(
            value: state.ghanaCardVerified
                ? 'Identity verified'
                : 'Not yet verified',
            hint: 'Ghana Card status',
            badge: state.ghanaCardVerified
                ? _StatusBadge.verified
                : _StatusBadge.pending,
            note: state.ghanaCardVerified
                ? null
                : 'Complete KYC verification to verify your identity',
            w: w,
            h: h,
          ),
        ],
      ),
    );
  }
}

// ── Read-Only Field ───────────────────────────────────────────────────────────

enum _StatusBadge { verified, pending }

class _ReadOnlyField extends StatelessWidget {
  final String value;
  final String hint;
  final _StatusBadge badge;
  final String? note;
  final double w, h;

  const _ReadOnlyField({
    required this.value,
    required this.hint,
    required this.badge,
    required this.w,
    required this.h,
    this.note,
  });

  @override
  Widget build(BuildContext context) {
    final isVerified = badge == _StatusBadge.verified;
    final badgeColor = isVerified ? MyShopColors.success : MyShopColors.warning;
    final badgeBg =
        isVerified ? MyShopColors.successLight : MyShopColors.warningLight;
    final badgeLabel = isVerified ? 'Verified' : 'Pending';
    final badgeIcon =
        isVerified ? Icons.verified_rounded : Icons.access_time_rounded;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          decoration: BoxDecoration(
            color: MyShopColors.surfaceGrey,
            borderRadius: BorderRadius.circular(w * 0.021),
            border: Border.all(color: MyShopColors.divider),
          ),
          padding: EdgeInsets.symmetric(
            horizontal: w * 0.041,
            vertical: h * 0.017,
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  value.isNotEmpty ? value : hint,
                  style: TextStyle(
                    fontSize: w * 0.036,
                    fontWeight: FontWeight.w400,
                    color: value.isNotEmpty
                        ? MyShopColors.textPrimary
                        : MyShopColors.textHint,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: badgeBg,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(badgeIcon, size: 12, color: badgeColor),
                    const SizedBox(width: 4),
                    Text(badgeLabel,
                        style: TextStyle(
                          fontSize: w * 0.026,
                          fontWeight: FontWeight.w700,
                          color: badgeColor,
                        )),
                  ],
                ),
              ),
            ],
          ),
        ),
        if (note != null) ...[
          SizedBox(height: h * 0.005),
          Padding(
            padding: EdgeInsets.only(left: w * 0.012),
            child: Text(
              note!,
              style: TextStyle(
                fontSize: w * 0.028,
                color: MyShopColors.textSecondary,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

// ── Field Label ───────────────────────────────────────────────────────────────

class _FieldLabel extends StatelessWidget {
  final String label;
  final double w;
  const _FieldLabel({required this.label, required this.w});

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: TextStyle(
        fontSize: w * 0.023,
        fontWeight: FontWeight.w900,
        color: MyShopColors.textSecondary,
        letterSpacing: 0.7,
      ),
    );
  }
}

// ── Profile Input ─────────────────────────────────────────────────────────────

class _ProfileInput extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final bool isActive;
  final String hintText;
  final TextInputType keyboardType;
  final ValueChanged<String> onChanged;
  final double w, h;

  const _ProfileInput({
    required this.controller,
    required this.focusNode,
    required this.isActive,
    required this.hintText,
    required this.onChanged,
    required this.w,
    required this.h,
    this.keyboardType = TextInputType.text,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      decoration: BoxDecoration(
        color: isActive ? MyShopColors.surfaceWhite : MyShopColors.surfaceGrey,
        borderRadius: BorderRadius.circular(w * 0.021),
        border: Border.all(
          color: isActive ? MyShopColors.primaryGold : MyShopColors.divider,
          width: isActive ? 1.5 : 1.0,
        ),
      ),
      child: TextField(
        controller: controller,
        focusNode: focusNode,
        keyboardType: keyboardType,
        onChanged: onChanged,
        style: TextStyle(
          fontSize: w * 0.036,
          fontWeight: FontWeight.w400,
          color: MyShopColors.textPrimary,
        ),
        decoration: InputDecoration(
          hintText: hintText,
          hintStyle:
              TextStyle(fontSize: w * 0.036, color: MyShopColors.textHint),
          contentPadding: EdgeInsets.symmetric(
            horizontal: w * 0.041,
            vertical: h * 0.017,
          ),
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
          disabledBorder: InputBorder.none,
          errorBorder: InputBorder.none,
          focusedErrorBorder: InputBorder.none,
        ),
      ),
    );
  }
}

// ── Warning Box ───────────────────────────────────────────────────────────────

class _WarningBox extends StatelessWidget {
  final double w, h;
  const _WarningBox({required this.w, required this.h});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: w * 0.041),
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: w * 0.038,
          vertical: h * 0.017,
        ),
        decoration: BoxDecoration(
          color: MyShopColors.primaryGoldLight,
          borderRadius: BorderRadius.circular(w * 0.026),
          border: Border.all(color: MyShopColors.primaryGold, width: 1.5),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: EdgeInsets.only(top: h * 0.002),
              child: Icon(Icons.verified_user_outlined,
                  size: w * 0.051, color: MyShopColors.primaryGold),
            ),
            SizedBox(width: w * 0.026),
            Expanded(
              child: RichText(
                text: TextSpan(
                  style: TextStyle(
                    fontSize: w * 0.031,
                    height: 1.45,
                    color: MyShopColors.textSecondary,
                  ),
                  children: const [
                    TextSpan(
                      text: 'Warning: ',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                    TextSpan(
                      text: 'Changing your email requires a one-time '
                          'verification code for account security.',
                      style: TextStyle(fontStyle: FontStyle.italic),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Error Banner ──────────────────────────────────────────────────────────────

class _ErrorBanner extends StatelessWidget {
  final String message;
  final double w, h;
  const _ErrorBanner({required this.message, required this.w, required this.h});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: w * 0.041),
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: w * 0.038,
          vertical: h * 0.015,
        ),
        decoration: BoxDecoration(
          color: MyShopColors.errorLight,
          borderRadius: BorderRadius.circular(w * 0.026),
          border:
              Border.all(color: MyShopColors.error.withAlpha(80), width: 1.5),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: EdgeInsets.only(top: h * 0.002),
              child: Icon(Icons.error_outline_rounded,
                  size: w * 0.046, color: MyShopColors.error),
            ),
            SizedBox(width: w * 0.026),
            Expanded(
              child: Text(
                message,
                style: TextStyle(
                  fontSize: w * 0.031,
                  height: 1.45,
                  color: MyShopColors.error,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Bottom Bar ────────────────────────────────────────────────────────────────

class _BottomBar extends ConsumerWidget {
  final double w, h;
  final EditProfileState state;
  const _BottomBar({required this.w, required this.h, required this.state});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bottomPad = MediaQuery.paddingOf(context).bottom;

    return Container(
      decoration: const BoxDecoration(
        color: MyShopColors.surfaceWhite,
        border: Border(top: BorderSide(color: MyShopColors.divider)),
      ),
      padding: EdgeInsets.only(
        left: w * 0.041,
        right: w * 0.041,
        top: h * 0.017,
        bottom: bottomPad + h * 0.017,
      ),
      child: Row(
        children: [
          // Cancel
          Expanded(
            child: GestureDetector(
              onTap: () => Navigator.of(context).maybePop(),
              behavior: HitTestBehavior.opaque,
              child: Container(
                height: h * 0.066,
                decoration: BoxDecoration(
                  color: MyShopColors.surfaceWhite,
                  borderRadius: BorderRadius.circular(w * 0.031),
                  border: Border.all(color: MyShopColors.divider, width: 1.5),
                ),
                child: Center(
                  child: Text(
                    'Cancel',
                    style: TextStyle(
                      fontSize: w * 0.038,
                      fontWeight: FontWeight.w600,
                      color: MyShopColors.textPrimary,
                    ),
                  ),
                ),
              ),
            ),
          ),
          SizedBox(width: w * 0.031),

          // Save Changes
          Expanded(
            child: SizedBox(
              height: h * 0.066,
              child: ElevatedButton(
                onPressed: state.canSave
                    ? () => ref.read(editProfileProvider.notifier).saveChanges()
                    : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: MyShopColors.darkSlate,
                  disabledBackgroundColor: MyShopColors.surfaceGrey,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(w * 0.031),
                  ),
                ),
                child: state.isSaving
                    ? SizedBox(
                        width: w * 0.046,
                        height: w * 0.046,
                        child: const CircularProgressIndicator(
                          strokeWidth: 2,
                          color: MyShopColors.surfaceWhite,
                        ),
                      )
                    : Text(
                        state.isSaved ? 'Saved ✓' : 'Save Changes',
                        style: TextStyle(
                          fontSize: w * 0.038,
                          fontWeight: FontWeight.w600,
                          color: MyShopColors.surfaceWhite,
                        ),
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
