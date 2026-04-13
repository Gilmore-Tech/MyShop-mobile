import 'dart:async';

import 'package:api_client/api_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../auth/providers/auth_controller.dart';
import '../../auth/providers/current_user_provider.dart';

/// Edit Business Information — name, registration, address, contact info,
/// and a service-coverage map with an adjustable radius.
///
/// Loads initial values from the authenticated user's profile.
/// Saves name and email via PUT /users/me. Service radius and other artisan
/// fields will use PUT /users/me/artisan once the backend supports it.
///
/// PRD Reference: PRD 5.3 — verified artisan profile management.
class EditBusinessInformationScreen extends ConsumerStatefulWidget {
  const EditBusinessInformationScreen({super.key});

  @override
  ConsumerState<EditBusinessInformationScreen> createState() =>
      _EditBusinessInformationScreenState();
}

class _EditBusinessInformationScreenState
    extends ConsumerState<EditBusinessInformationScreen> {
  late final TextEditingController _name;
  late final TextEditingController _registration;
  late final TextEditingController _address;
  late final TextEditingController _email;
  late final TextEditingController _phone;

  // Service area centre — Kumasi pilot city
  static const _initialCentre = LatLng(6.6885, -1.6244);
  late double _radiusKm;

  static const _minRadiusKm = 1.0;
  static const _maxRadiusKm = 25.0;
  static const _stepKm = 1.0;

  bool _dirty = false;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    final user = ref.read(currentUserProvider);
    final ap = user?.artisanProfile;

    _name = TextEditingController(
      text: user?.businessName ?? user?.displayName ?? '',
    );
    _registration = TextEditingController(); // No backend field yet
    _address = TextEditingController(); // No backend field yet
    _email = TextEditingController(text: user?.email ?? '');
    _phone = TextEditingController(text: user?.phone ?? '');
    _radiusKm = ap?.serviceRadiusKm ?? 5;

    for (final c in [_name, _registration, _address, _email, _phone]) {
      c.addListener(_markDirty);
    }
  }

  void _markDirty() {
    if (!_dirty) setState(() => _dirty = true);
  }

  @override
  void dispose() {
    _name.dispose();
    _registration.dispose();
    _address.dispose();
    _email.dispose();
    _phone.dispose();
    super.dispose();
  }

  void _adjustRadius(double delta) {
    setState(() {
      _radiusKm =
          (_radiusKm + delta).clamp(_minRadiusKm, _maxRadiusKm).toDouble();
      _dirty = true;
    });
  }

  Future<void> _save() async {
    if (_name.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Business name is required.')),
      );
      return;
    }

    setState(() => _isSaving = true);

    // Save business name and service area via PUT /users/me/artisan.
    final error =
        await ref.read(authControllerProvider.notifier).updateArtisanProfile(
              UpdateArtisanProfileRequest(
                businessName: _name.text.trim(),
                serviceRadiusKm: _radiusKm,
              ),
            );

    if (!mounted) return;
    setState(() {
      _isSaving = false;
      if (error == null) _dirty = false;
    });

    if (error != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error)),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Business info updated')),
      );
      if (context.canPop()) context.pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: MyShopColors.surfaceWhite,
      body: SafeArea(
        child: Column(
          children: [
            _Header(),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(
                  MyShopSpacing.md,
                  MyShopSpacing.md,
                  MyShopSpacing.md,
                  MyShopSpacing.lg,
                ),
                children: [
                  _SectionCard(
                    icon: Icons.business_outlined,
                    title: 'Business Details',
                    subtitle: 'Provide your registered business information.',
                    children: [
                      _LabelledField(
                        label: 'BUSINESS NAME',
                        controller: _name,
                      ),
                      _LabelledField(
                        label: 'REGISTRATION NUMBER',
                        controller: _registration,
                      ),
                      _LabelledField(
                        label: 'BUSINESS ADDRESS',
                        controller: _address,
                        minLines: 2,
                        maxLines: 3,
                      ),
                    ],
                  ),
                  const SizedBox(height: MyShopSpacing.md),
                  _SectionCard(
                    icon: Icons.alternate_email,
                    title: 'Contact',
                    subtitle: 'How clients can reach you outside the app.',
                    children: [
                      _LabelledField(
                        label: 'BUSINESS EMAIL',
                        controller: _email,
                        keyboardType: TextInputType.emailAddress,
                      ),
                      _LabelledField(
                        label: 'BUSINESS PHONE',
                        controller: _phone,
                        keyboardType: TextInputType.phone,
                      ),
                    ],
                  ),
                  const SizedBox(height: MyShopSpacing.md),
                  _ServiceAreaCard(
                    centre: _initialCentre,
                    radiusKm: _radiusKm,
                    minRadiusKm: _minRadiusKm,
                    maxRadiusKm: _maxRadiusKm,
                    onIncrease: () => _adjustRadius(_stepKm),
                    onDecrease: () => _adjustRadius(-_stepKm),
                  ),
                  const SizedBox(height: MyShopSpacing.lg),
                ],
              ),
            ),
            _SaveFooter(
              enabled: _dirty && !_isSaving,
              onTap: _save,
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Header
// ─────────────────────────────────────────────────────────────────────────────

class _Header extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(
        MyShopSpacing.sm,
        MyShopSpacing.sm,
        MyShopSpacing.md,
        MyShopSpacing.md,
      ),
      decoration: const BoxDecoration(
        color: MyShopColors.surfaceWhite,
        border: Border(bottom: BorderSide(color: MyShopColors.divider)),
      ),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back, color: MyShopColors.textPrimary),
            onPressed: () => context.pop(),
          ),
          Text(
            'Business Info',
            style: MyShopTypography.h1.copyWith(
              fontWeight: FontWeight.w700,
              fontSize: 18,
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Section card (title + subtitle + children)
// ─────────────────────────────────────────────────────────────────────────────

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.children,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final List<Widget> children;

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
            children: [
              Icon(icon, size: 18, color: MyShopColors.textPrimary),
              const SizedBox(width: MyShopSpacing.sm),
              Text(
                title,
                style: MyShopTypography.h3.copyWith(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(subtitle, style: MyShopTypography.body2),
          const SizedBox(height: MyShopSpacing.md),
          ...children,
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Labelled field
// ─────────────────────────────────────────────────────────────────────────────

class _LabelledField extends StatelessWidget {
  const _LabelledField({
    required this.label,
    required this.controller,
    this.minLines = 1,
    this.maxLines = 1,
    this.keyboardType,
  });

  final String label;
  final TextEditingController controller;
  final int minLines;
  final int maxLines;
  final TextInputType? keyboardType;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: MyShopSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: MyShopTypography.overline.copyWith(
              color: MyShopColors.textSecondary,
              fontWeight: FontWeight.w800,
              fontSize: 11,
              letterSpacing: 1.0,
            ),
          ),
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: MyShopSpacing.md,
              vertical: 12,
            ),
            decoration: BoxDecoration(
              color: MyShopColors.offWhite,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: MyShopColors.divider),
            ),
            child: TextField(
              controller: controller,
              minLines: minLines,
              maxLines: maxLines,
              keyboardType: keyboardType,
              style: MyShopTypography.body1.copyWith(
                fontWeight: FontWeight.w600,
                fontSize: 15,
              ),
              decoration: const InputDecoration(
                border: InputBorder.none,
                isDense: true,
                contentPadding: EdgeInsets.zero,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Service area card (map + radius controls)
// ─────────────────────────────────────────────────────────────────────────────

class _ServiceAreaCard extends StatefulWidget {
  const _ServiceAreaCard({
    required this.centre,
    required this.radiusKm,
    required this.minRadiusKm,
    required this.maxRadiusKm,
    required this.onIncrease,
    required this.onDecrease,
  });

  final LatLng centre;
  final double radiusKm;
  final double minRadiusKm;
  final double maxRadiusKm;
  final VoidCallback onIncrease;
  final VoidCallback onDecrease;

  @override
  State<_ServiceAreaCard> createState() => _ServiceAreaCardState();
}

class _ServiceAreaCardState extends State<_ServiceAreaCard> {
  final Completer<GoogleMapController> _controller = Completer();

  @override
  void didUpdateWidget(covariant _ServiceAreaCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.radiusKm != oldWidget.radiusKm) {
      _fitBounds();
    }
  }

  Future<void> _fitBounds() async {
    final controller = await _controller.future;
    final zoom = _zoomForRadiusKm(widget.radiusKm);
    await controller.animateCamera(
      CameraUpdate.newCameraPosition(
        CameraPosition(target: widget.centre, zoom: zoom),
      ),
    );
  }

  /// Rough mapping from radius (km) to a sensible Google Maps zoom level so
  /// the circle stays nicely framed in the card.
  double _zoomForRadiusKm(double km) {
    if (km <= 1) return 14;
    if (km <= 3) return 13;
    if (km <= 5) return 12.2;
    if (km <= 10) return 11.4;
    if (km <= 15) return 11;
    if (km <= 20) return 10.6;
    return 10.2;
  }

  @override
  Widget build(BuildContext context) {
    final atMin = widget.radiusKm <= widget.minRadiusKm;
    final atMax = widget.radiusKm >= widget.maxRadiusKm;

    return Container(
      decoration: BoxDecoration(
        color: MyShopColors.surfaceWhite,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: MyShopColors.divider),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              MyShopSpacing.md,
              MyShopSpacing.md,
              MyShopSpacing.md,
              MyShopSpacing.sm,
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.near_me_outlined,
                  size: 18,
                  color: MyShopColors.textPrimary,
                ),
                const SizedBox(width: MyShopSpacing.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Service Area',
                        style: MyShopTypography.h3.copyWith(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Set how far from your base you want to take jobs.',
                        style: MyShopTypography.body2,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Map
          SizedBox(
            height: 220,
            child: Stack(
              children: [
                Positioned.fill(
                  child: GoogleMap(
                    initialCameraPosition: CameraPosition(
                      target: widget.centre,
                      zoom: _zoomForRadiusKm(widget.radiusKm),
                    ),
                    onMapCreated: (controller) {
                      if (!_controller.isCompleted) {
                        _controller.complete(controller);
                      }
                    },
                    myLocationButtonEnabled: false,
                    zoomControlsEnabled: false,
                    mapToolbarEnabled: false,
                    compassEnabled: false,
                    liteModeEnabled: true,
                    markers: {
                      Marker(
                        markerId: const MarkerId('service-area-centre'),
                        position: widget.centre,
                      ),
                    },
                    circles: {
                      Circle(
                        circleId: const CircleId('service-area'),
                        center: widget.centre,
                        radius: widget.radiusKm * 1000,
                        fillColor:
                            MyShopColors.primaryGold.withValues(alpha: 0.18),
                        strokeColor: MyShopColors.primaryGold,
                        strokeWidth: 2,
                      ),
                    },
                  ),
                ),

                // Radius badge
                Positioned(
                  left: MyShopSpacing.md,
                  top: MyShopSpacing.md,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: MyShopColors.darkSlate,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      '${widget.radiusKm.toStringAsFixed(0)} km radius',
                      style: MyShopTypography.body2.copyWith(
                        color: MyShopColors.textOnDarkSlate,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),

                // +/- controls
                Positioned(
                  right: MyShopSpacing.md,
                  top: MyShopSpacing.md,
                  child: Column(
                    children: [
                      _RadiusButton(
                        icon: Icons.add,
                        onTap: atMax ? null : widget.onIncrease,
                      ),
                      const SizedBox(height: 8),
                      _RadiusButton(
                        icon: Icons.remove,
                        onTap: atMin ? null : widget.onDecrease,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          Padding(
            padding: const EdgeInsets.all(MyShopSpacing.md),
            child: Row(
              children: [
                const Icon(
                  Icons.info_outline,
                  size: 14,
                  color: MyShopColors.textSecondary,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Range: ${widget.minRadiusKm.toStringAsFixed(0)}–${widget.maxRadiusKm.toStringAsFixed(0)} km. Larger areas surface more jobs but increase travel time.',
                    style: MyShopTypography.body2.copyWith(height: 1.5),
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

class _RadiusButton extends StatelessWidget {
  const _RadiusButton({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final disabled = onTap == null;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: MyShopColors.surfaceWhite,
          shape: BoxShape.circle,
          border: Border.all(color: MyShopColors.divider),
          boxShadow: const [
            BoxShadow(
              color: Color(0x14000000),
              blurRadius: 6,
              offset: Offset(0, 2),
            ),
          ],
        ),
        child: Icon(
          icon,
          size: 20,
          color: disabled ? MyShopColors.disabled : MyShopColors.textPrimary,
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Save footer
// ─────────────────────────────────────────────────────────────────────────────

class _SaveFooter extends StatelessWidget {
  const _SaveFooter({required this.enabled, required this.onTap});

  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.fromLTRB(
        MyShopSpacing.md,
        MyShopSpacing.md,
        MyShopSpacing.md,
        MyShopSpacing.md + MediaQuery.of(context).padding.bottom * 0.2,
      ),
      decoration: const BoxDecoration(
        color: MyShopColors.surfaceWhite,
        border: Border(top: BorderSide(color: MyShopColors.divider)),
      ),
      child: GestureDetector(
        onTap: enabled ? onTap : null,
        child: Container(
          height: 56,
          width: double.infinity,
          decoration: BoxDecoration(
            color: enabled ? MyShopColors.darkSlate : MyShopColors.surfaceGrey,
            borderRadius: BorderRadius.circular(28),
          ),
          alignment: Alignment.center,
          child: Text(
            'Save Changes',
            style: MyShopTypography.button.copyWith(
              color: enabled
                  ? MyShopColors.textOnDarkSlate
                  : MyShopColors.disabled,
              fontWeight: FontWeight.w800,
              fontSize: 15,
            ),
          ),
        ),
      ),
    );
  }
}
