import 'package:flutter/material.dart';
import 'package:shared_ui/shared_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/app_preferences_provider.dart';

// ── Screen ────────────────────────────────────────────────────────────────────
// PRD § 11 Localisation: English + Twi at launch, further languages post-pilot.
// EDD § User Module: language, distanceUnit, theme stored on user profile.
// API: PUT /v1/users/me  { distanceUnit, languageCode, theme, ... }

class AppPreferencesScreen extends ConsumerWidget {
  const AppPreferencesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final size = MediaQuery.sizeOf(context);
    final w = size.width;
    final h = size.height;
    final bottom = MediaQuery.paddingOf(context).bottom;
    final state = ref.watch(appPreferencesProvider);

    // Backend saves (only language right now) can fail. Surface the error
    // as a snackbar — every other pref is a SharedPreferences write that
    // doesn't 4xx.
    ref.listen<AppPreferencesState>(appPreferencesProvider, (prev, next) {
      if (next.errorMessage != null &&
          next.errorMessage != prev?.errorMessage) {
        MyShopToast.show(
          context,
          message: next.errorMessage!,
          type: ToastType.error,
        );
      }
    });

    return Scaffold(
      backgroundColor: MyShopColors.offWhite,
      appBar: _buildAppBar(context, w),
      body: SingleChildScrollView(
        padding: EdgeInsets.only(bottom: bottom + h * 0.032),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(height: h * 0.024),

            // ── Customization header ───────────────────────────────────────
            _CustomizationHeader(w: w, h: h),

            SizedBox(height: h * 0.028),

            // ── Navigation & Units (hidden — coming in next update) ─────────
            // _SectionLabel(label: 'NAVIGATION & UNITS', w: w, h: h),
            // _SectionCard(
            //   w: w,
            //   children: [
            //     _MapUnitsRow(
            //       selected: state.distanceUnit,
            //       onSelect: (v) => ref
            //           .read(appPreferencesProvider.notifier)
            //           .setDistanceUnit(v),
            //       w: w,
            //       h: h,
            //     ),
            //   ],
            // ),
            //
            // SizedBox(height: h * 0.028),

            // ── Visual Style (hidden — coming in next update) ──────────────
            // _SectionLabel(label: 'VISUAL STYLE', w: w, h: h),
            // _SectionCard(
            //   w: w,
            //   children: [
            //     _InterfaceThemeRow(
            //       selected: state.themeMode,
            //       onSelect: (v) =>
            //           ref.read(appPreferencesProvider.notifier).setTheme(v),
            //       w: w,
            //       h: h,
            //     ),
            //   ],
            // ),
            //
            // SizedBox(height: h * 0.028),

            // ── Onboarding & Help ──────────────────────────────────────────
            _SectionLabel(label: 'ONBOARDING & HELP', w: w, h: h),
            _SectionCard(
              w: w,
              children: [
                _ToggleRow(
                  icon: Icons.replay_rounded,
                  title: 'Replay Onboarding',
                  subtitle: 'Show tutorial on next app start',
                  value: state.replayOnboarding,
                  onChanged: (v) => ref
                      .read(appPreferencesProvider.notifier)
                      .toggleReplayOnboarding(v),
                  w: w,
                  h: h,
                ),
                _RowDivider(w: w),
                _ToggleRow(
                  icon: Icons.auto_awesome_outlined,
                  title: 'Feature Updates',
                  subtitle: 'Display tips for new updates',
                  value: state.featureUpdates,
                  onChanged: (v) => ref
                      .read(appPreferencesProvider.notifier)
                      .toggleFeatureUpdates(v),
                  w: w,
                  h: h,
                ),
                _RowDivider(w: w),
                _ProTipRow(w: w, h: h),
              ],
            ),

            SizedBox(height: h * 0.038),

            // ── Footer ─────────────────────────────────────────────────────
            _Footer(w: w, h: h),
            SizedBox(height: h * 0.016),
          ],
        ),
      ),
    );
  }

  PreferredSizeWidget _buildAppBar(BuildContext context, double w) {
    return AppBar(
      backgroundColor: MyShopColors.surfaceWhite,
      elevation: 0,
      scrolledUnderElevation: 0,
      leading: IconButton(
        icon: Icon(
          Icons.arrow_back,
          color: MyShopColors.textPrimary,
          size: w * 0.052,
        ),
        onPressed: () => Navigator.of(context).maybePop(),
      ),
      title: Text(
        'App Preferences',
        style: TextStyle(
          fontFamily: 'Raleway',
          fontSize: w * 0.050,
          fontWeight: FontWeight.w700,
          color: MyShopColors.textPrimary,
          height: 1.3,
        ),
      ),
      centerTitle: false,
    );
  }
}

// ── Customization header ──────────────────────────────────────────────────────

class _CustomizationHeader extends StatelessWidget {
  final double w;
  final double h;
  const _CustomizationHeader({required this.w, required this.h});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: w * 0.044),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Customization',
            style: TextStyle(
              fontFamily: 'Raleway',
              fontSize: w * 0.060,
              fontWeight: FontWeight.w700,
              color: MyShopColors.textPrimary,
              height: 1.2,
            ),
          ),
          SizedBox(height: h * 0.007),
          Text(
            'Tailor your navigation and interface experience to suit your daily needs.',
            style: TextStyle(
              fontFamily: 'Raleway',
              fontSize: w * 0.034,
              fontWeight: FontWeight.w400,
              color: MyShopColors.textSecondary,
              height: 1.55,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Section label ─────────────────────────────────────────────────────────────

class _SectionLabel extends StatelessWidget {
  final String label;
  final double w;
  final double h;
  const _SectionLabel({required this.label, required this.w, required this.h});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(left: w * 0.044, bottom: h * 0.010),
      child: Text(
        label,
        style: TextStyle(
          fontFamily: 'Raleway',
          fontSize: w * 0.026,
          fontWeight: FontWeight.w900,
          color: MyShopColors.textSecondary,
          letterSpacing: 1.4,
          height: 1.4,
        ),
      ),
    );
  }
}

// ── Section card ──────────────────────────────────────────────────────────────

class _SectionCard extends StatelessWidget {
  final double w;
  final List<Widget> children;
  const _SectionCard({required this.w, required this.children});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: EdgeInsets.symmetric(horizontal: w * 0.044),
      decoration: BoxDecoration(
        color: MyShopColors.surfaceWhite,
        borderRadius: BorderRadius.circular(12),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0D000000),
            blurRadius: 8,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: children,
      ),
    );
  }
}

// ── Row divider ───────────────────────────────────────────────────────────────

class _RowDivider extends StatelessWidget {
  final double w;
  const _RowDivider({required this.w});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(left: w * 0.041 + w * 0.092 + w * 0.031),
      child:
          const Divider(color: MyShopColors.divider, height: 1, thickness: 1),
    );
  }
}

// ── Map Units row ─────────────────────────────────────────────────────────────
// Kept (but not currently rendered) — will be re-enabled in the next update.

// ignore: unused_element
class _MapUnitsRow extends StatelessWidget {
  final DistanceUnit selected;
  final ValueChanged<DistanceUnit> onSelect;
  final double w;
  final double h;
  const _MapUnitsRow({
    required this.selected,
    required this.onSelect,
    required this.w,
    required this.h,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: w * 0.041, vertical: h * 0.016),
      child: Row(
        children: [
          // Icon
          Container(
            width: w * 0.092,
            height: w * 0.092,
            decoration: const BoxDecoration(
                color: MyShopColors.surfaceGrey, shape: BoxShape.circle),
            child: Icon(Icons.map_outlined,
                color: MyShopColors.textSecondary, size: w * 0.046),
          ),
          SizedBox(width: w * 0.031),
          // Title + subtitle
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Map Units',
                  style: TextStyle(
                    fontFamily: 'Raleway',
                    fontSize: w * 0.038,
                    fontWeight: FontWeight.w600,
                    color: MyShopColors.textPrimary,
                    height: 1.3,
                  ),
                ),
                SizedBox(height: h * 0.003),
                Text(
                  'Choose between Metric and Imperial',
                  style: TextStyle(
                    fontFamily: 'Raleway',
                    fontSize: w * 0.030,
                    fontWeight: FontWeight.w400,
                    color: MyShopColors.textSecondary,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
          SizedBox(width: w * 0.020),
          // Segmented picker
          _TextSegmented<DistanceUnit>(
            options: DistanceUnit.values,
            selected: selected,
            labelOf: (v) => v.label,
            onSelect: onSelect,
            w: w,
            h: h,
          ),
        ],
      ),
    );
  }
}

// ── Interface Theme row ───────────────────────────────────────────────────────
// Kept (but not currently rendered) — will be re-enabled in the next update.

// ignore: unused_element
class _InterfaceThemeRow extends StatelessWidget {
  final AppThemeMode selected;
  final ValueChanged<AppThemeMode> onSelect;
  final double w;
  final double h;
  const _InterfaceThemeRow({
    required this.selected,
    required this.onSelect,
    required this.w,
    required this.h,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: w * 0.041, vertical: h * 0.016),
      child: Row(
        children: [
          Container(
            width: w * 0.092,
            height: w * 0.092,
            decoration: const BoxDecoration(
                color: MyShopColors.surfaceGrey, shape: BoxShape.circle),
            child: Icon(Icons.tune_rounded,
                color: MyShopColors.textSecondary, size: w * 0.046),
          ),
          SizedBox(width: w * 0.031),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Interface Theme',
                  style: TextStyle(
                    fontFamily: 'Raleway',
                    fontSize: w * 0.038,
                    fontWeight: FontWeight.w600,
                    color: MyShopColors.textPrimary,
                    height: 1.3,
                  ),
                ),
                SizedBox(height: h * 0.003),
                Text(
                  'Switch between light and dark',
                  style: TextStyle(
                    fontFamily: 'Raleway',
                    fontSize: w * 0.030,
                    fontWeight: FontWeight.w400,
                    color: MyShopColors.textSecondary,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
          SizedBox(width: w * 0.020),
          _IconSegmented<AppThemeMode>(
            options: AppThemeMode.values,
            selected: selected,
            labelOf: (v) => v.label,
            iconOf: (v) => v == AppThemeMode.light
                ? Icons.light_mode_outlined
                : Icons.dark_mode_outlined,
            onSelect: onSelect,
            w: w,
            h: h,
          ),
        ],
      ),
    );
  }
}

// ── Toggle row ────────────────────────────────────────────────────────────────

class _ToggleRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;
  final double w;
  final double h;
  const _ToggleRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
    required this.w,
    required this.h,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: w * 0.041, vertical: h * 0.016),
      child: Row(
        children: [
          Container(
            width: w * 0.092,
            height: w * 0.092,
            decoration: const BoxDecoration(
                color: MyShopColors.surfaceGrey, shape: BoxShape.circle),
            child:
                Icon(icon, color: MyShopColors.textSecondary, size: w * 0.046),
          ),
          SizedBox(width: w * 0.031),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontFamily: 'Raleway',
                    fontSize: w * 0.038,
                    fontWeight: FontWeight.w600,
                    color: MyShopColors.textPrimary,
                    height: 1.3,
                  ),
                ),
                SizedBox(height: h * 0.003),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontFamily: 'Raleway',
                    fontSize: w * 0.030,
                    fontWeight: FontWeight.w400,
                    color: MyShopColors.textSecondary,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
          SizedBox(width: w * 0.015),
          Switch(
            value: value,
            activeThumbColor: Colors.white,
            activeTrackColor: MyShopColors.darkSlate,
            inactiveThumbColor: Colors.white,
            inactiveTrackColor: MyShopColors.disabled,
            trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}

// ── Pro Tip row ───────────────────────────────────────────────────────────────

class _ProTipRow extends StatelessWidget {
  final double w;
  final double h;
  const _ProTipRow({required this.w, required this.h});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        w * 0.041,
        h * 0.016,
        w * 0.041,
        h * 0.018,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Gold icon circle
          Container(
            width: w * 0.092,
            height: w * 0.092,
            decoration: const BoxDecoration(
              color: MyShopColors.primaryGoldLight,
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.tips_and_updates_outlined,
                color: MyShopColors.primaryGold, size: w * 0.046),
          ),
          SizedBox(width: w * 0.031),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Pro Tip',
                  style: TextStyle(
                    fontFamily: 'Raleway',
                    fontSize: w * 0.038,
                    fontWeight: FontWeight.w700,
                    color: MyShopColors.textPrimary,
                    height: 1.3,
                  ),
                ),
                SizedBox(height: h * 0.005),
                Text(
                  'Settings are synced with your cloud profile and will '
                  'apply to all connected devices automatically.',
                  style: TextStyle(
                    fontFamily: 'Raleway',
                    fontSize: w * 0.030,
                    fontWeight: FontWeight.w400,
                    color: MyShopColors.textSecondary,
                    height: 1.55,
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

// ── Generic text segmented control ───────────────────────────────────────────
// Used for Map Units (KM | Miles). Selected item: white bg + border.

class _TextSegmented<T> extends StatelessWidget {
  final List<T> options;
  final T selected;
  final String Function(T) labelOf;
  final ValueChanged<T> onSelect;
  final double w;
  final double h;
  const _TextSegmented({
    required this.options,
    required this.selected,
    required this.labelOf,
    required this.onSelect,
    required this.w,
    required this.h,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: MyShopColors.surfaceGrey,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: MyShopColors.divider, width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: options.map((opt) {
          final isSelected = opt == selected;
          return GestureDetector(
            onTap: () => onSelect(opt),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeInOut,
              padding: EdgeInsets.symmetric(
                  horizontal: w * 0.030, vertical: h * 0.009),
              decoration: BoxDecoration(
                color:
                    isSelected ? MyShopColors.surfaceWhite : Colors.transparent,
                borderRadius: BorderRadius.circular(6),
                border: isSelected
                    ? Border.all(color: MyShopColors.divider, width: 1)
                    : null,
                boxShadow: isSelected
                    ? [
                        const BoxShadow(
                          color: Color(0x14000000),
                          blurRadius: 4,
                          offset: Offset(0, 1),
                        ),
                      ]
                    : null,
              ),
              child: Text(
                labelOf(opt),
                style: TextStyle(
                  fontFamily: 'Raleway',
                  fontSize: w * 0.033,
                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                  color: isSelected
                      ? MyShopColors.textPrimary
                      : MyShopColors.textSecondary,
                  height: 1.3,
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

// ── Generic icon+text segmented control ───────────────────────────────────────
// Used for Interface Theme (☀ Light | 🌙 Dark).

class _IconSegmented<T> extends StatelessWidget {
  final List<T> options;
  final T selected;
  final String Function(T) labelOf;
  final IconData Function(T) iconOf;
  final ValueChanged<T> onSelect;
  final double w;
  final double h;
  const _IconSegmented({
    required this.options,
    required this.selected,
    required this.labelOf,
    required this.iconOf,
    required this.onSelect,
    required this.w,
    required this.h,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: MyShopColors.surfaceGrey,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: MyShopColors.divider, width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: options.map((opt) {
          final isSelected = opt == selected;
          return GestureDetector(
            onTap: () => onSelect(opt),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeInOut,
              padding: EdgeInsets.symmetric(
                  horizontal: w * 0.028, vertical: h * 0.009),
              decoration: BoxDecoration(
                color:
                    isSelected ? MyShopColors.surfaceWhite : Colors.transparent,
                borderRadius: BorderRadius.circular(6),
                border: isSelected
                    ? Border.all(color: MyShopColors.divider, width: 1)
                    : null,
                boxShadow: isSelected
                    ? [
                        const BoxShadow(
                          color: Color(0x14000000),
                          blurRadius: 4,
                          offset: Offset(0, 1),
                        ),
                      ]
                    : null,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    iconOf(opt),
                    size: w * 0.036,
                    color: isSelected
                        ? MyShopColors.textPrimary
                        : MyShopColors.textSecondary,
                  ),
                  SizedBox(width: w * 0.012),
                  Text(
                    labelOf(opt),
                    style: TextStyle(
                      fontFamily: 'Raleway',
                      fontSize: w * 0.033,
                      fontWeight:
                          isSelected ? FontWeight.w700 : FontWeight.w500,
                      color: isSelected
                          ? MyShopColors.textPrimary
                          : MyShopColors.textSecondary,
                      height: 1.3,
                    ),
                  ),
                ],
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

// ── Footer ────────────────────────────────────────────────────────────────────

class _Footer extends StatelessWidget {
  final double w;
  final double h;
  const _Footer({required this.w, required this.h});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        'MyShop App v1.2.0  •  Security Patch: May 2024',
        style: TextStyle(
          fontFamily: 'Raleway',
          fontSize: w * 0.028,
          fontWeight: FontWeight.w400,
          color: MyShopColors.textHint,
          height: 1.5,
        ),
      ),
    );
  }
}
