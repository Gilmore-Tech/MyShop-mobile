import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/edit_profile_provider.dart';

// ── Design tokens ─────────────────────────────────────────────────────────────
const _surfaceWhite  = Color(0xFFFFFFFF);
const _surfaceGrey   = Color(0xFFF3F5F6);
const _offWhite      = Color(0xFFF6F7F8);
const _textPrimary   = Color(0xFF161A1D);
const _textSecondary = Color(0xFF555E68);
const _textHint      = Color(0xFFBDBDBD);
const _gold          = Color(0xFFF5A623);
const _goldLight     = Color(0xFFFFF8EC);
const _darkSlate     = Color(0xFF46535D);
const _divider       = Color(0xFFE0E0E0);

// ── Screen ────────────────────────────────────────────────────────────────────
// PRD 4.11 — Edit full name, email, phone, Ghana Card.
// Changing email or phone triggers OTP verification before the change is
// persisted (EDD § Auth Module).
// Ghana Card is AES-256 encrypted at application layer — never logged.
// API: PUT /v1/users/me

class EditProfileScreen extends ConsumerStatefulWidget {
  const EditProfileScreen({super.key});

  @override
  ConsumerState<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends ConsumerState<EditProfileScreen> {
  late final TextEditingController _nameCtrl;
  late final TextEditingController _emailCtrl;
  late final TextEditingController _phoneCtrl;
  late final TextEditingController _ghanaCtrl;

  late final FocusNode _nameFocus;
  late final FocusNode _emailFocus;
  late final FocusNode _phoneFocus;
  late final FocusNode _ghanaFocus;

  @override
  void initState() {
    super.initState();
    _nameCtrl  = TextEditingController();
    _emailCtrl = TextEditingController();
    _phoneCtrl = TextEditingController();
    _ghanaCtrl = TextEditingController();

    _nameFocus  = FocusNode();
    _emailFocus = FocusNode();
    _phoneFocus = FocusNode();
    _ghanaFocus = FocusNode();

    // Rebuild on focus change so borders animate correctly.
    for (final fn in [_nameFocus, _emailFocus, _phoneFocus, _ghanaFocus]) {
      fn.addListener(() => setState(() {}));
    }

    // Sync controllers once the provider has loaded initial values.
    WidgetsBinding.instance.addPostFrameCallback((_) => _syncControllers());
  }

  void _syncControllers() {
    final s = ref.read(editProfileProvider);
    if (_nameCtrl.text  != s.fullName)     _nameCtrl.text  = s.fullName;
    if (_emailCtrl.text != s.email)        _emailCtrl.text = s.email;
    if (_phoneCtrl.text != s.phoneNumber)  _phoneCtrl.text = s.phoneNumber;
    if (_ghanaCtrl.text != s.ghanaCard)    _ghanaCtrl.text = s.ghanaCard;
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _phoneCtrl.dispose();
    _ghanaCtrl.dispose();
    _nameFocus.dispose();
    _emailFocus.dispose();
    _phoneFocus.dispose();
    _ghanaFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final w    = size.width;
    final h    = size.height;

    // Sync controllers whenever provider state changes (e.g. after initial load).
    ref.listen<EditProfileState>(editProfileProvider, (prev, next) {
      if (prev?.fullName    != next.fullName    && _nameCtrl.text  != next.fullName)    _nameCtrl.text  = next.fullName;
      if (prev?.email       != next.email       && _emailCtrl.text != next.email)       _emailCtrl.text = next.email;
      if (prev?.phoneNumber != next.phoneNumber && _phoneCtrl.text != next.phoneNumber) _phoneCtrl.text = next.phoneNumber;
      if (prev?.ghanaCard   != next.ghanaCard   && _ghanaCtrl.text != next.ghanaCard)   _ghanaCtrl.text = next.ghanaCard;
    });

    final state = ref.watch(editProfileProvider);

    return Scaffold(
      backgroundColor: _offWhite,
      body: Column(
        children: [
          _AppBar(w: w, h: h),
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                children: [
                  // ── Photo section ──
                  _PhotoSection(w: w, h: h),
                  SizedBox(height: h * 0.028),

                  // ── Form ──
                  _FormCard(
                    w: w,
                    h: h,
                    state: state,
                    nameCtrl:  _nameCtrl,
                    emailCtrl: _emailCtrl,
                    phoneCtrl: _phoneCtrl,
                    ghanaCtrl: _ghanaCtrl,
                    nameFocus:  _nameFocus,
                    emailFocus: _emailFocus,
                    phoneFocus: _phoneFocus,
                    ghanaFocus: _ghanaFocus,
                  ),

                  // ── Warning box ──
                  if (state.showVerificationWarning) ...[
                    SizedBox(height: h * 0.014),
                    _WarningBox(w: w, h: h),
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
  final double w;
  final double h;
  const _AppBar({required this.w, required this.h});

  @override
  Widget build(BuildContext context) {
    final topPad = MediaQuery.paddingOf(context).top;
    return Container(
      color: _surfaceWhite,
      padding: EdgeInsets.only(
        top:    topPad + h * 0.010,
        bottom: h * 0.017,
        left:   w * 0.041,
        right:  w * 0.041,
      ),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => Navigator.of(context).maybePop(),
            behavior: HitTestBehavior.opaque,
            child: Padding(
              padding: EdgeInsets.only(right: w * 0.031),
              child: Icon(Icons.arrow_back,
                  size: w * 0.056, color: _textPrimary),
            ),
          ),
          Text(
            'Edit Profile',
            style: TextStyle(
              fontSize:   w * 0.051,
              fontWeight: FontWeight.w700,
              color:      _textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Photo Section ─────────────────────────────────────────────────────────────

class _PhotoSection extends StatelessWidget {
  final double w;
  final double h;
  const _PhotoSection({required this.w, required this.h});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: _surfaceWhite,
      width: double.infinity,
      padding: EdgeInsets.symmetric(vertical: h * 0.028),
      child: Column(
        children: [
          // Avatar + camera badge
          Stack(
            alignment: Alignment.bottomRight,
            children: [
              // Avatar circle with goldLight tint background
              Container(
                width:  w * 0.256,
                height: w * 0.256,
                decoration: BoxDecoration(
                  color:  _goldLight,
                  shape:  BoxShape.circle,
                ),
                child: ClipOval(
                  child: Icon(
                    Icons.person_rounded,
                    size:  w * 0.154,
                    color: const Color(0xFF78909C),
                  ),
                ),
              ),
              // Camera badge
              GestureDetector(
                onTap: () {
                  // TODO: image_picker — pick/capture new profile photo
                },
                child: Container(
                  width:  w * 0.082,
                  height: w * 0.082,
                  decoration: BoxDecoration(
                    color:  _darkSlate,
                    shape:  BoxShape.circle,
                    border: Border.all(color: _surfaceWhite, width: 2.5),
                  ),
                  child: Icon(
                    Icons.photo_camera_rounded,
                    size:  w * 0.041,
                    color: _surfaceWhite,
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: h * 0.011),

          // Change photo text link
          GestureDetector(
            onTap: () {
              // TODO: image_picker
            },
            behavior: HitTestBehavior.opaque,
            child: Text(
              'Change Profile Photo',
              style: TextStyle(
                fontSize:   w * 0.033,
                fontWeight: FontWeight.w500,
                color:      _textSecondary,
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
  final double                 w;
  final double                 h;
  final EditProfileState       state;
  final TextEditingController  nameCtrl;
  final TextEditingController  emailCtrl;
  final TextEditingController  phoneCtrl;
  final TextEditingController  ghanaCtrl;
  final FocusNode              nameFocus;
  final FocusNode              emailFocus;
  final FocusNode              phoneFocus;
  final FocusNode              ghanaFocus;

  const _FormCard({
    required this.w,
    required this.h,
    required this.state,
    required this.nameCtrl,
    required this.emailCtrl,
    required this.phoneCtrl,
    required this.ghanaCtrl,
    required this.nameFocus,
    required this.emailFocus,
    required this.phoneFocus,
    required this.ghanaFocus,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(editProfileProvider.notifier);

    return Container(
      color: _surfaceWhite,
      padding: EdgeInsets.symmetric(
        horizontal: w * 0.041,
        vertical:   h * 0.022,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Full Name ──
          _FieldLabel(label: 'FULL NAME', w: w),
          SizedBox(height: h * 0.008),
          _ProfileInput(
            controller: nameCtrl,
            focusNode:  nameFocus,
            isActive:   nameFocus.hasFocus,
            hintText:   'Enter your full name',
            onChanged:  notifier.updateFullName,
            w: w,
            h: h,
          ),
          SizedBox(height: h * 0.019),

          // ── Email ──
          Row(
            children: [
              _FieldLabel(label: 'EMAIL', w: w),
              const Spacer(),
              if (state.emailChanged)
                GestureDetector(
                  onTap: () {
                    // TODO: navigate to OTP verification screen for email change
                  },
                  behavior: HitTestBehavior.opaque,
                  child: Text(
                    'VERIFY',
                    style: TextStyle(
                      fontSize:      w * 0.028,
                      fontWeight:    FontWeight.w800,
                      color:         _gold,
                      letterSpacing: 0.6,
                    ),
                  ),
                ),
            ],
          ),
          SizedBox(height: h * 0.008),
          _ProfileInput(
            controller:  emailCtrl,
            focusNode:   emailFocus,
            isActive:    emailFocus.hasFocus || state.emailChanged,
            hintText:    'Enter your email',
            keyboardType: TextInputType.emailAddress,
            onChanged:   notifier.updateEmail,
            w: w,
            h: h,
          ),
          SizedBox(height: h * 0.019),

          // ── Phone Number ──
          _FieldLabel(label: 'PHONE NUMBER', w: w),
          SizedBox(height: h * 0.008),
          _ProfileInput(
            controller:  phoneCtrl,
            focusNode:   phoneFocus,
            isActive:    phoneFocus.hasFocus,
            hintText:    '0XX XXX XXXX',
            keyboardType: TextInputType.phone,
            onChanged:   notifier.updatePhoneNumber,
            w: w,
            h: h,
          ),
          SizedBox(height: h * 0.019),

          // ── Ghana Card ──
          _FieldLabel(label: 'GHANA CARD', w: w),
          SizedBox(height: h * 0.008),
          _ProfileInput(
            controller: ghanaCtrl,
            focusNode:  ghanaFocus,
            isActive:   ghanaFocus.hasFocus,
            hintText:   'GHA-XXXXXXXXX-X',
            onChanged:  notifier.updateGhanaCard,
            w: w,
            h: h,
          ),
        ],
      ),
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
        fontSize:      w * 0.023,
        fontWeight:    FontWeight.w900,
        color:         _textSecondary,
        letterSpacing: 0.7,
      ),
    );
  }
}

// ── Profile Input ─────────────────────────────────────────────────────────────

class _ProfileInput extends StatelessWidget {
  final TextEditingController  controller;
  final FocusNode              focusNode;
  final bool                   isActive;
  final String                 hintText;
  final TextInputType          keyboardType;
  final ValueChanged<String>   onChanged;
  final double                 w;
  final double                 h;

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
        color:        isActive ? _surfaceWhite : _surfaceGrey,
        borderRadius: BorderRadius.circular(w * 0.021),
        border: Border.all(
          color: isActive ? _gold : _divider,
          width: isActive ? 1.5 : 1.0,
        ),
      ),
      child: TextField(
        controller:    controller,
        focusNode:     focusNode,
        keyboardType:  keyboardType,
        onChanged:     onChanged,
        style: TextStyle(
          fontSize:   w * 0.036,
          fontWeight: FontWeight.w400,
          color:      _textPrimary,
        ),
        decoration: InputDecoration(
          hintText:  hintText,
          hintStyle: TextStyle(
            fontSize: w * 0.036,
            color:    _textHint,
          ),
          contentPadding: EdgeInsets.symmetric(
            horizontal: w * 0.041,
            vertical:   h * 0.017,
          ),
          border:               InputBorder.none,
          enabledBorder:        InputBorder.none,
          focusedBorder:        InputBorder.none,
          disabledBorder:       InputBorder.none,
          errorBorder:          InputBorder.none,
          focusedErrorBorder:   InputBorder.none,
        ),
      ),
    );
  }
}

// ── Warning Box ───────────────────────────────────────────────────────────────
// Shown when email or phone has been changed.
// OTP required before the update is persisted (EDD § Auth Module).

class _WarningBox extends StatelessWidget {
  final double w;
  final double h;
  const _WarningBox({required this.w, required this.h});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: w * 0.041),
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: w * 0.038,
          vertical:   h * 0.017,
        ),
        decoration: BoxDecoration(
          color:        _goldLight,
          borderRadius: BorderRadius.circular(w * 0.026),
          border:       Border.all(color: _gold, width: 1.5),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Shield icon
            Padding(
              padding: EdgeInsets.only(top: h * 0.002),
              child: Icon(
                Icons.verified_user_outlined,
                size:  w * 0.051,
                color: _gold,
              ),
            ),
            SizedBox(width: w * 0.026),

            // Warning text
            Expanded(
              child: RichText(
                text: TextSpan(
                  style: TextStyle(
                    fontSize: w * 0.031,
                    height:   1.45,
                    color:    _textSecondary,
                  ),
                  children: const [
                    TextSpan(
                      text: 'Warning: ',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                    TextSpan(
                      text: 'Changing your email or phone requires '
                            'a one-time verification code for account security.',
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

// ── Bottom Bar ────────────────────────────────────────────────────────────────

class _BottomBar extends ConsumerWidget {
  final double           w;
  final double           h;
  final EditProfileState state;
  const _BottomBar(
      {required this.w, required this.h, required this.state});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bottomPad = MediaQuery.paddingOf(context).bottom;

    return Container(
      decoration: const BoxDecoration(
        color:  _surfaceWhite,
        border: Border(top: BorderSide(color: _divider)),
      ),
      padding: EdgeInsets.only(
        left:   w * 0.041,
        right:  w * 0.041,
        top:    h * 0.017,
        bottom: bottomPad + h * 0.017,
      ),
      child: Row(
        children: [
          // ── Cancel ──
          Expanded(
            child: GestureDetector(
              onTap: () => Navigator.of(context).maybePop(),
              behavior: HitTestBehavior.opaque,
              child: Container(
                height: h * 0.066,
                decoration: BoxDecoration(
                  color:        _surfaceWhite,
                  borderRadius: BorderRadius.circular(w * 0.031),
                  border:       Border.all(color: _divider, width: 1.5),
                ),
                child: Center(
                  child: Text(
                    'Cancel',
                    style: TextStyle(
                      fontSize:   w * 0.038,
                      fontWeight: FontWeight.w600,
                      color:      _textPrimary,
                    ),
                  ),
                ),
              ),
            ),
          ),
          SizedBox(width: w * 0.031),

          // ── Save Changes ──
          Expanded(
            child: SizedBox(
              height: h * 0.066,
              child: ElevatedButton(
                onPressed: state.canSave
                    ? () => ref
                        .read(editProfileProvider.notifier)
                        .saveChanges()
                    : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor:         _darkSlate,
                  disabledBackgroundColor: _surfaceGrey,
                  elevation:               0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(w * 0.031),
                  ),
                ),
                child: state.isSaving
                    ? SizedBox(
                        width:  w * 0.046,
                        height: w * 0.046,
                        child: const CircularProgressIndicator(
                          strokeWidth: 2,
                          color:       _surfaceWhite,
                        ),
                      )
                    : Text(
                        state.isSaved ? 'Saved ✓' : 'Save Changes',
                        style: TextStyle(
                          fontSize:   w * 0.038,
                          fontWeight: FontWeight.w600,
                          color:      _surfaceWhite,
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
