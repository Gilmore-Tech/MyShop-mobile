import 'dart:io' show Platform;

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:incoming_request_overlay/incoming_request_overlay.dart';
import 'package:shared_ui/shared_ui.dart';
import 'package:url_launcher/url_launcher.dart';

/// Notification Settings — channel toggles, safety alerts, preferences.
///
/// PRD Reference: PRD 5.5 — provider notification preferences.
class NotificationSettingsScreen extends StatefulWidget {
  const NotificationSettingsScreen({super.key});

  @override
  State<NotificationSettingsScreen> createState() =>
      _NotificationSettingsScreenState();
}

class _NotificationSettingsScreenState extends State<NotificationSettingsScreen>
    with WidgetsBindingObserver {
  bool _push = true;
  bool _sms = false;
  bool _email = true;
  bool _emergencySos = true;
  bool _criticalSystem = true;
  bool _quietHours = false;
  bool _marketing = false;
  bool _requestPermissionLoading = true;
  bool _requestPermissionGranted = false;
  String _requestPermissionSubtitle = 'Checking system settings…';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refreshRequestPermission();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refreshRequestPermission();
  }

  Future<void> _refreshRequestPermission() async {
    if (!mounted) return;
    setState(() => _requestPermissionLoading = true);
    try {
      if (Platform.isAndroid) {
        final supported = await IncomingRequestOverlay.instance.isSupported();
        final granted = supported &&
            await IncomingRequestOverlay.instance.canDrawOverlays();
        if (!mounted) return;
        setState(() {
          _requestPermissionGranted = granted;
          _requestPermissionSubtitle = !supported
              ? 'Custom request cards are not supported on this device.'
              : granted
                  ? 'Custom ride and job cards can appear over other apps.'
                  : 'Allow Display over other apps to see the custom request card.';
          _requestPermissionLoading = false;
        });
        return;
      }

      final settings =
          await FirebaseMessaging.instance.getNotificationSettings();
      final authorized =
          settings.authorizationStatus == AuthorizationStatus.authorized ||
              settings.authorizationStatus == AuthorizationStatus.provisional;
      final timeSensitive =
          settings.timeSensitive == AppleNotificationSetting.enabled;
      if (!mounted) return;
      setState(() {
        _requestPermissionGranted = authorized && timeSensitive;
        _requestPermissionSubtitle = !authorized
            ? 'Notifications are disabled. Enable them in iOS Settings.'
            : timeSensitive
                ? 'Time Sensitive ride and job request alerts are enabled.'
                : 'Enable Time Sensitive Notifications in iOS Settings.';
        _requestPermissionLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _requestPermissionGranted = false;
        _requestPermissionSubtitle =
            'Could not read the current system notification setting.';
        _requestPermissionLoading = false;
      });
    }
  }

  Future<void> _openRequestPermission() async {
    if (Platform.isAndroid) {
      await IncomingRequestOverlay.instance.openOverlaySettings();
      return;
    }
    await launchUrl(
      Uri.parse('app-settings:'),
      mode: LaunchMode.externalApplication,
    );
  }

  void _resetToDefaults() {
    setState(() {
      _push = true;
      _sms = false;
      _email = true;
      _emergencySos = true;
      _criticalSystem = true;
      _quietHours = false;
      _marketing = false;
    });
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
                  _SectionHeader(
                    icon: Icons.notifications_none,
                    label: 'CHANNELS',
                    iconColor: MyShopColors.textSecondary,
                  ),
                  const SizedBox(height: MyShopSpacing.sm),
                  _SettingsCard(
                    rows: [
                      _SettingRow(
                        iconBg: MyShopColors.surfaceGrey,
                        icon: Icons.notifications_none,
                        iconColor: MyShopColors.textPrimary,
                        title: 'Push Notifications',
                        subtitle:
                            'Instant updates on job requests and earnings.',
                        value: _push,
                        onChanged: (v) => setState(() => _push = v),
                      ),
                      _SettingRow(
                        iconBg: MyShopColors.surfaceGrey,
                        icon: Icons.chat_bubble_outline,
                        iconColor: MyShopColors.textPrimary,
                        title: 'SMS Alerts',
                        subtitle: 'Critical updates when you are offline.',
                        value: _sms,
                        onChanged: (v) => setState(() => _sms = v),
                      ),
                      _SettingRow(
                        iconBg: MyShopColors.surfaceGrey,
                        icon: Icons.mail_outline,
                        iconColor: MyShopColors.textPrimary,
                        title: 'Email Reports',
                        subtitle: 'Weekly summaries and payment invoices.',
                        value: _email,
                        onChanged: (v) => setState(() => _email = v),
                      ),
                    ],
                  ),
                  const SizedBox(height: MyShopSpacing.lg),
                  _SectionHeader(
                    icon: Icons.picture_in_picture_alt_outlined,
                    label: 'INCOMING REQUESTS',
                    iconColor: MyShopColors.primaryGold,
                  ),
                  const SizedBox(height: MyShopSpacing.sm),
                  _SettingsCard(
                    rows: [
                      _PermissionRow(
                        icon: Platform.isAndroid
                            ? Icons.layers_outlined
                            : Icons.notifications_active_outlined,
                        title: Platform.isAndroid
                            ? 'Display over other apps'
                            : 'Time Sensitive alerts',
                        subtitle: _requestPermissionSubtitle,
                        granted: _requestPermissionGranted,
                        loading: _requestPermissionLoading,
                        onTap: _openRequestPermission,
                      ),
                    ],
                  ),
                  const SizedBox(height: MyShopSpacing.lg),
                  Row(
                    children: [
                      Expanded(
                        child: _SectionHeader(
                          icon: Icons.shield_outlined,
                          label: 'SAFETY & CRISIS',
                          iconColor: MyShopColors.error,
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: MyShopColors.error,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          'Priority',
                          style: MyShopTypography.body2.copyWith(
                            color: MyShopColors.textOnPrimary,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: MyShopSpacing.sm),
                  _SettingsCard(
                    rows: [
                      _SettingRow(
                        iconBg: MyShopColors.errorLight,
                        icon: Icons.shield_outlined,
                        iconColor: MyShopColors.error,
                        title: 'Emergency SOS',
                        subtitle:
                            'Real-time alerts for safety incidents in your area.',
                        value: _emergencySos,
                        onChanged: (v) => setState(() => _emergencySos = v),
                      ),
                      _SettingRow(
                        iconBg: MyShopColors.primaryGoldLight,
                        icon: Icons.flash_on,
                        iconColor: MyShopColors.primaryGold,
                        title: 'Critical System Alerts',
                        subtitle:
                            'App outages and essential service maintenance.',
                        value: _criticalSystem,
                        onChanged: (v) => setState(() => _criticalSystem = v),
                      ),
                    ],
                    footer: const _SafetyFooterNote(),
                  ),
                  const SizedBox(height: MyShopSpacing.lg),
                  _SectionHeader(
                    icon: Icons.nightlight_outlined,
                    label: 'PREFERENCES',
                    iconColor: MyShopColors.textSecondary,
                  ),
                  const SizedBox(height: MyShopSpacing.sm),
                  _SettingsCard(
                    rows: [
                      _SettingRow(
                        iconBg: MyShopColors.surfaceGrey,
                        icon: Icons.nightlight_outlined,
                        iconColor: MyShopColors.textPrimary,
                        title: 'Quiet Hours',
                        subtitle:
                            'Mute all non-critical alerts from 10 PM to 6 AM.',
                        value: _quietHours,
                        onChanged: (v) => setState(() => _quietHours = v),
                      ),
                      _SettingRow(
                        iconBg: MyShopColors.surfaceGrey,
                        icon: Icons.campaign_outlined,
                        iconColor: MyShopColors.textPrimary,
                        title: 'Marketing & Tips',
                        subtitle: 'News on promotions and ways to earn more.',
                        value: _marketing,
                        onChanged: (v) => setState(() => _marketing = v),
                      ),
                    ],
                  ),
                  const SizedBox(height: MyShopSpacing.xl),
                  _ResetButton(onTap: _resetToDefaults),
                  const SizedBox(height: MyShopSpacing.lg),
                  Center(
                    child: Text(
                      'Provider App v4.12.0 (Build 2024.08)',
                      style: MyShopTypography.body2.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Center(
                    child: Text(
                      'Adjusting these settings may affect how quickly you receive\njob requests and payments.',
                      textAlign: TextAlign.center,
                      style: MyShopTypography.body2.copyWith(height: 1.5),
                    ),
                  ),
                  const SizedBox(height: MyShopSpacing.lg),
                ],
              ),
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
            'Notifications Settings',
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
// Section header
// ─────────────────────────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.icon,
    required this.label,
    required this.iconColor,
  });

  final IconData icon;
  final String label;
  final Color iconColor;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 16, color: iconColor),
        const SizedBox(width: MyShopSpacing.sm),
        Text(
          label,
          style: MyShopTypography.overline.copyWith(
            color: MyShopColors.textSecondary,
            fontWeight: FontWeight.w900,
            fontSize: 12,
            letterSpacing: 1.2,
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Settings card
// ─────────────────────────────────────────────────────────────────────────────

class _SettingsCard extends StatelessWidget {
  const _SettingsCard({required this.rows, this.footer});

  final List<Widget> rows;
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: MyShopColors.surfaceWhite,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: MyShopColors.divider),
      ),
      child: Column(
        children: [
          for (int i = 0; i < rows.length; i++) ...[
            rows[i],
            if (i < rows.length - 1)
              const Divider(
                height: 1,
                indent: MyShopSpacing.md,
                endIndent: MyShopSpacing.md,
                color: MyShopColors.divider,
              ),
          ],
          if (footer != null) footer!,
        ],
      ),
    );
  }
}

class _PermissionRow extends StatelessWidget {
  const _PermissionRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.granted,
    required this.loading,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool granted;
  final bool loading;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(MyShopSpacing.md),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: MyShopColors.primaryGoldLight,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: MyShopColors.primaryGold, size: 20),
          ),
          const SizedBox(width: MyShopSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: MyShopTypography.h3.copyWith(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: MyShopTypography.body2.copyWith(height: 1.45),
                ),
              ],
            ),
          ),
          const SizedBox(width: MyShopSpacing.sm),
          if (loading)
            const SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          else if (granted)
            const Icon(Icons.check_circle, color: MyShopColors.success)
          else
            TextButton(onPressed: onTap, child: const Text('Enable')),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Setting row
// ─────────────────────────────────────────────────────────────────────────────

class _SettingRow extends StatelessWidget {
  const _SettingRow({
    required this.iconBg,
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final Color iconBg;
  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(MyShopSpacing.md),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: iconBg,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 20, color: iconColor),
          ),
          const SizedBox(width: MyShopSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: MyShopTypography.h3.copyWith(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: MyShopTypography.body2.copyWith(height: 1.45),
                ),
              ],
            ),
          ),
          const SizedBox(width: MyShopSpacing.sm),
          Switch.adaptive(
            value: value,
            onChanged: onChanged,
            activeThumbColor: Colors.white,
            activeTrackColor: MyShopColors.primaryGold,
            inactiveThumbColor: Colors.white,
            inactiveTrackColor: MyShopColors.divider,
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Safety footer note
// ─────────────────────────────────────────────────────────────────────────────

class _SafetyFooterNote extends StatelessWidget {
  const _SafetyFooterNote();

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.all(MyShopSpacing.sm),
      padding: const EdgeInsets.all(MyShopSpacing.sm + 2),
      decoration: BoxDecoration(
        color: MyShopColors.offWhite,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.info_outline,
            size: 16,
            color: MyShopColors.textSecondary,
          ),
          const SizedBox(width: MyShopSpacing.sm),
          Expanded(
            child: Text(
              'Emergency alerts bypass "Quiet Hours" and system mutes to ensure your safety during active shifts.',
              style: MyShopTypography.body2.copyWith(height: 1.5),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Reset button
// ─────────────────────────────────────────────────────────────────────────────

class _ResetButton extends StatelessWidget {
  const _ResetButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 52,
        decoration: BoxDecoration(
          color: MyShopColors.surfaceWhite,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: MyShopColors.error),
        ),
        alignment: Alignment.center,
        child: Text(
          'Reset to Default Settings',
          style: MyShopTypography.button.copyWith(
            color: MyShopColors.error,
            fontWeight: FontWeight.w800,
            fontSize: 15,
          ),
        ),
      ),
    );
  }
}
