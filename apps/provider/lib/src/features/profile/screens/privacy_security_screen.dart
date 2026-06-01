import 'package:flutter/material.dart';
import 'package:shared_ui/shared_ui.dart';

/// Privacy & Security — 2FA, data masking, sessions, password.
class PrivacySecurityScreen extends StatefulWidget {
  const PrivacySecurityScreen({super.key});

  @override
  State<PrivacySecurityScreen> createState() => _PrivacySecurityScreenState();
}

class _PrivacySecurityScreenState extends State<PrivacySecurityScreen> {
  bool _twoFactor = true;
  bool _maskNumber = true;
  bool _maskLocation = false;
  bool _biometric = true;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: MyShopColors.surfaceWhite,
      appBar: AppBar(
        backgroundColor: MyShopColors.surfaceWhite,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: MyShopColors.textPrimary),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: const Text('Privacy & Security',
            style: TextStyle(
                fontFamily: 'Raleway',
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: MyShopColors.textPrimary)),
      ),
      body: ListView(
        padding: const EdgeInsets.all(MyShopSpacing.md),
        children: [
          // Security score banner
          Container(
            padding: const EdgeInsets.all(MyShopSpacing.md),
            decoration: BoxDecoration(
              color: MyShopColors.successLight,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                  color: MyShopColors.success.withValues(alpha: 0.3)),
            ),
            child: Row(children: [
              const Icon(Icons.security, size: 22, color: MyShopColors.success),
              const SizedBox(width: 12),
              Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                    const Text('Security score: Strong',
                        style: TextStyle(
                            fontFamily: 'Raleway',
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: MyShopColors.textPrimary)),
                    Text('Your account meets all best-practice checks.',
                        style: MyShopTypography.body2.copyWith(fontSize: 11)),
                  ])),
            ]),
          ),
          const SizedBox(height: MyShopSpacing.lg),

          const Text('AUTHENTICATION',
              style: TextStyle(
                  fontFamily: 'Raleway',
                  fontSize: 12,
                  fontWeight: FontWeight.w900,
                  color: MyShopColors.textSecondary,
                  letterSpacing: 1.0)),
          const SizedBox(height: MyShopSpacing.sm),
          _SettingToggle(
              icon: Icons.shield_outlined,
              title: 'Two-Factor Authentication',
              subtitle: 'OTP via SMS on every login',
              value: _twoFactor,
              onChanged: (v) => setState(() => _twoFactor = v)),
          const SizedBox(height: 8),
          _SettingToggle(
              icon: Icons.fingerprint,
              title: 'Biometric Unlock',
              subtitle: 'Fingerprint or Face ID',
              value: _biometric,
              onChanged: (v) => setState(() => _biometric = v)),
          const SizedBox(height: 8),
          _LinkRow(
              icon: Icons.key_outlined,
              title: 'Change Password',
              subtitle: 'Last changed: 60 days ago'),
          const SizedBox(height: MyShopSpacing.lg),

          const Text('DATA MASKING',
              style: TextStyle(
                  fontFamily: 'Raleway',
                  fontSize: 12,
                  fontWeight: FontWeight.w900,
                  color: MyShopColors.textSecondary,
                  letterSpacing: 1.0)),
          const SizedBox(height: MyShopSpacing.sm),
          _SettingToggle(
              icon: Icons.phone_disabled,
              title: 'Mask Phone Number',
              subtitle: 'Hide your number from clients',
              value: _maskNumber,
              onChanged: (v) => setState(() => _maskNumber = v)),
          const SizedBox(height: 8),
          _SettingToggle(
              icon: Icons.location_off,
              title: 'Mask Live Location',
              subtitle: 'Off-trip GPS visibility',
              value: _maskLocation,
              onChanged: (v) => setState(() => _maskLocation = v)),
          const SizedBox(height: MyShopSpacing.lg),

          const Text('DEVICES & SESSIONS',
              style: TextStyle(
                  fontFamily: 'Raleway',
                  fontSize: 12,
                  fontWeight: FontWeight.w900,
                  color: MyShopColors.textSecondary,
                  letterSpacing: 1.0)),
          const SizedBox(height: MyShopSpacing.sm),
          _LinkRow(
              icon: Icons.devices,
              title: 'Active Sessions',
              subtitle: '2 devices currently signed in'),
          const SizedBox(height: 8),
          _LinkRow(
              icon: Icons.history,
              title: 'Login History',
              subtitle: 'Last 30 days'),
          const SizedBox(height: MyShopSpacing.xxl),
        ],
      ),
    );
  }
}

class _SettingToggle extends StatelessWidget {
  const _SettingToggle({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });
  final IconData icon;
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: MyShopSpacing.md, vertical: 10),
      decoration: BoxDecoration(
        color: MyShopColors.surfaceWhite,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: MyShopColors.divider),
      ),
      child: Row(children: [
        Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
                color: MyShopColors.surfaceGrey,
                borderRadius: BorderRadius.circular(10)),
            child: Icon(icon, size: 18, color: MyShopColors.darkSlate)),
        const SizedBox(width: 12),
        Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title,
              style: const TextStyle(
                  fontFamily: 'Raleway',
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: MyShopColors.textPrimary)),
          Text(subtitle, style: MyShopTypography.body2.copyWith(fontSize: 11)),
        ])),
        Switch(
          value: value,
          onChanged: onChanged,
          activeThumbColor: MyShopColors.success,
          activeTrackColor: MyShopColors.successLight,
        ),
      ]),
    );
  }
}

class _LinkRow extends StatelessWidget {
  const _LinkRow(
      {required this.icon, required this.title, required this.subtitle});
  final IconData icon;
  final String title;
  final String subtitle;
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: MyShopSpacing.md, vertical: 12),
      decoration: BoxDecoration(
        color: MyShopColors.surfaceWhite,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: MyShopColors.divider),
      ),
      child: Row(children: [
        Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
                color: MyShopColors.surfaceGrey,
                borderRadius: BorderRadius.circular(10)),
            child: Icon(icon, size: 18, color: MyShopColors.darkSlate)),
        const SizedBox(width: 12),
        Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title,
              style: const TextStyle(
                  fontFamily: 'Raleway',
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: MyShopColors.textPrimary)),
          Text(subtitle, style: MyShopTypography.body2.copyWith(fontSize: 11)),
        ])),
        const Icon(Icons.chevron_right,
            size: 18, color: MyShopColors.textSecondary),
      ]),
    );
  }
}
