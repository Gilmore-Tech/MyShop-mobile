import 'package:flutter/material.dart';
import 'package:shared_ui/shared_ui.dart';

/// Notification Settings — channel and per-event toggles.
///
/// Figma: node 313:27364
class NotificationSettingsScreen extends StatefulWidget {
  const NotificationSettingsScreen({super.key});

  @override
  State<NotificationSettingsScreen> createState() =>
      _NotificationSettingsScreenState();
}

class _NotificationSettingsScreenState
    extends State<NotificationSettingsScreen> {
  bool _push = true;
  bool _sms = true;
  bool _email = false;
  bool _newJobs = true;
  bool _payouts = true;
  bool _marketing = false;
  bool _systemAlerts = true;

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
        title: const Text('Notifications',
            style: TextStyle(
                fontFamily: 'Raleway',
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: MyShopColors.textPrimary)),
      ),
      body: ListView(
        padding: const EdgeInsets.all(MyShopSpacing.md),
        children: [
          const Text('CHANNELS',
              style: TextStyle(
                  fontFamily: 'Raleway',
                  fontSize: 12,
                  fontWeight: FontWeight.w900,
                  color: MyShopColors.textSecondary,
                  letterSpacing: 1.0)),
          const SizedBox(height: MyShopSpacing.sm),
          _ToggleRow(
              icon: Icons.notifications_outlined,
              title: 'Push Notifications',
              subtitle: 'In-app and lock screen alerts',
              value: _push,
              onChanged: (v) => setState(() => _push = v)),
          const SizedBox(height: 8),
          _ToggleRow(
              icon: Icons.sms_outlined,
              title: 'SMS Messages',
              subtitle: 'Critical alerts via text',
              value: _sms,
              onChanged: (v) => setState(() => _sms = v)),
          const SizedBox(height: 8),
          _ToggleRow(
              icon: Icons.email_outlined,
              title: 'Email Notifications',
              subtitle: 'Receipts and weekly summaries',
              value: _email,
              onChanged: (v) => setState(() => _email = v)),
          const SizedBox(height: MyShopSpacing.lg),

          const Text('NOTIFY ME ABOUT',
              style: TextStyle(
                  fontFamily: 'Raleway',
                  fontSize: 12,
                  fontWeight: FontWeight.w900,
                  color: MyShopColors.textSecondary,
                  letterSpacing: 1.0)),
          const SizedBox(height: MyShopSpacing.sm),
          _ToggleRow(
              icon: Icons.work_outline,
              title: 'New Job Requests',
              subtitle: 'Incoming rides and bookings',
              value: _newJobs,
              onChanged: (v) => setState(() => _newJobs = v)),
          const SizedBox(height: 8),
          _ToggleRow(
              icon: Icons.account_balance_wallet_outlined,
              title: 'Payouts & Earnings',
              subtitle: 'Settlement and balance updates',
              value: _payouts,
              onChanged: (v) => setState(() => _payouts = v)),
          const SizedBox(height: 8),
          _ToggleRow(
              icon: Icons.warning_amber_outlined,
              title: 'System Alerts',
              subtitle: 'Critical platform announcements',
              value: _systemAlerts,
              onChanged: (v) => setState(() => _systemAlerts = v)),
          const SizedBox(height: 8),
          _ToggleRow(
              icon: Icons.campaign_outlined,
              title: 'Promotions & Marketing',
              subtitle: 'Tips, offers and product news',
              value: _marketing,
              onChanged: (v) => setState(() => _marketing = v)),
          const SizedBox(height: MyShopSpacing.xxl),
        ],
      ),
    );
  }
}

class _ToggleRow extends StatelessWidget {
  const _ToggleRow({
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
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
              Text(title,
                  style: const TextStyle(
                      fontFamily: 'Raleway',
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: MyShopColors.textPrimary)),
              Text(subtitle,
                  style: MyShopTypography.body2.copyWith(fontSize: 11)),
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
