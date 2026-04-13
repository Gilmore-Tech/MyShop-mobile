import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/notification_settings_provider.dart';

// ── Design tokens ─────────────────────────────────────────────────────────────
const _surfaceWhite  = Color(0xFFFFFFFF);
const _offWhite      = Color(0xFFF6F7F8);
const _surfaceGrey   = Color(0xFFF3F5F6);
const _textPrimary   = Color(0xFF161A1D);
const _textSecondary = Color(0xFF555E68);
const _gold          = Color(0xFFF5A623);
const _darkSlate     = Color(0xFF46535D);
const _disabled      = Color(0xFFBDBDBD);
const _divider       = Color(0xFFE0E0E0);
const _warning       = Color(0xFFF2994A);
const _warningLight  = Color(0xFFFEF3E8);

// ── Screen ────────────────────────────────────────────────────────────────────
// PRD § 10 Notification Strategy: push, SMS, email, emergency alerts, promos.
// API: GET  /v1/users/me/notification-preferences
//      PATCH /v1/users/me/notification-preferences
//      POST  /v1/notifications/test

class NotificationSettingsScreen extends ConsumerWidget {
  const NotificationSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final size   = MediaQuery.sizeOf(context);
    final w      = size.width;
    final h      = size.height;
    final bottom = MediaQuery.paddingOf(context).bottom;

    final state = ref.watch(notificationSettingsProvider);

    return Scaffold(
      backgroundColor: _offWhite,
      appBar: _buildAppBar(context, w, h),
      body: SingleChildScrollView(
        padding: EdgeInsets.only(
          bottom: bottom + h * 0.032,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(height: h * 0.022),

            // ── Delivery Channels ──────────────────────────────────────────
            _SectionLabel(label: 'DELIVERY CHANNELS', w: w, h: h),
            _SectionCard(
              w: w,
              children: [
                _ToggleRow(
                  icon: Icons.smartphone_outlined,
                  title: 'Push Notifications',
                  subtitle: 'Instant updates on your mobile device',
                  value: state.pushEnabled,
                  onChanged: (v) =>
                      ref.read(notificationSettingsProvider.notifier).togglePush(v),
                  w: w,
                  h: h,
                ),
                _RowDivider(w: w),
                _ToggleRow(
                  icon: Icons.chat_bubble_outline_rounded,
                  title: 'SMS Alerts',
                  subtitle: 'Direct text messages for critical items',
                  value: state.smsEnabled,
                  onChanged: (v) =>
                      ref.read(notificationSettingsProvider.notifier).toggleSms(v),
                  w: w,
                  h: h,
                ),
                _RowDivider(w: w),
                _ToggleRow(
                  icon: Icons.mail_outline_rounded,
                  title: 'Email Digest',
                  subtitle: 'Summary reports sent to your inbox',
                  value: state.emailEnabled,
                  onChanged: (v) =>
                      ref.read(notificationSettingsProvider.notifier).toggleEmail(v),
                  w: w,
                  h: h,
                ),
              ],
            ),

            SizedBox(height: h * 0.028),

            // ── Content & Frequency ────────────────────────────────────────
            _SectionLabel(label: 'CONTENT & FREQUENCY', w: w, h: h),
            _SectionCard(
              w: w,
              children: [
                // Emergency Broadcasting info — always-on, no toggle
                _EmergencyRow(w: w, h: h),
                _RowDivider(w: w),
                // Critical Safety Alerts sub-row (boxed)
                _CriticalSafetyRow(
                  value: state.criticalSafetyEnabled,
                  onChanged: (v) => ref
                      .read(notificationSettingsProvider.notifier)
                      .toggleCriticalSafety(v),
                  w: w,
                  h: h,
                ),
                _RowDivider(w: w),
                // Promo Frequency segmented picker
                _PromoFrequencyRow(
                  selected: state.promoFrequency,
                  onSelect: (f) => ref
                      .read(notificationSettingsProvider.notifier)
                      .setPromoFrequency(f),
                  w: w,
                  h: h,
                ),
              ],
            ),

            SizedBox(height: h * 0.028),

            // ── System Preview ─────────────────────────────────────────────
            _SectionLabel(label: 'SYSTEM PREVIEW', w: w, h: h),
            _PreviewCard(w: w, h: h),

            SizedBox(height: h * 0.032),

            // ── Send Test Notification ─────────────────────────────────────
            Padding(
              padding: EdgeInsets.symmetric(horizontal: w * 0.044),
              child: _SendTestButton(w: w, h: h),
            ),

            SizedBox(height: h * 0.022),

            // ── Footer ─────────────────────────────────────────────────────
            _Footer(w: w, h: h),
          ],
        ),
      ),
    );
  }

  PreferredSizeWidget _buildAppBar(
      BuildContext context, double w, double h) {
    return AppBar(
      backgroundColor: _surfaceWhite,
      elevation: 0,
      scrolledUnderElevation: 0,
      leading: IconButton(
        icon: Icon(
          Icons.arrow_back_ios_new_rounded,
          color: _textPrimary,
          size: w * 0.052,
        ),
        onPressed: () => Navigator.of(context).maybePop(),
      ),
      title: Text(
        'Notifications',
        style: TextStyle(
          fontFamily: 'Raleway',
          fontSize: w * 0.050,
          fontWeight: FontWeight.w700,
          color: _textPrimary,
          height: 1.3,
        ),
      ),
      centerTitle: false,
      actions: [
        Padding(
          padding: EdgeInsets.only(right: w * 0.038),
          child: Icon(
            Icons.notifications_outlined,
            color: _textSecondary,
            size: w * 0.060,
          ),
        ),
      ],
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
      padding: EdgeInsets.only(
        left: w * 0.044,
        bottom: h * 0.010,
      ),
      child: Text(
        label,
        style: TextStyle(
          fontFamily: 'Raleway',
          fontSize: w * 0.026,
          fontWeight: FontWeight.w900,
          color: _textSecondary,
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
        color: _surfaceWhite,
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
    // Left-indent aligns to the text (after icon circle + gap).
    return Padding(
      padding: EdgeInsets.only(left: w * 0.041 + w * 0.092 + w * 0.031),
      child: const Divider(color: _divider, height: 1, thickness: 1),
    );
  }
}

// ── Toggle row ────────────────────────────────────────────────────────────────

class _ToggleRow extends StatelessWidget {
  final IconData icon;
  final String   title;
  final String   subtitle;
  final bool     value;
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
      padding: EdgeInsets.symmetric(
        horizontal: w * 0.041,
        vertical:   h * 0.016,
      ),
      child: Row(
        children: [
          // Icon circle
          Container(
            width:  w * 0.092,
            height: w * 0.092,
            decoration: const BoxDecoration(
              color:        _surfaceGrey,
              shape:        BoxShape.circle,
            ),
            child: Icon(icon, color: _textSecondary, size: w * 0.046),
          ),
          SizedBox(width: w * 0.031),
          // Title + subtitle
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
                    color: _textPrimary,
                    height: 1.3,
                  ),
                ),
                SizedBox(height: h * 0.003),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontFamily: 'Raleway',
                    fontSize: w * 0.031,
                    fontWeight: FontWeight.w400,
                    color: _textSecondary,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
          SizedBox(width: w * 0.020),
          // Switch
          Switch(
            value:              value,
            activeThumbColor:   Colors.white,
            activeTrackColor:   _gold,
            inactiveThumbColor: Colors.white,
            inactiveTrackColor: _disabled,
            trackOutlineColor:  const WidgetStatePropertyAll(Colors.transparent),
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}

// ── Emergency Broadcasting row ────────────────────────────────────────────────
// Always-on broadcast — no toggle. PRD § 10: emergency alerts bypass silent mode.

class _EmergencyRow extends StatelessWidget {
  final double w;
  final double h;
  const _EmergencyRow({required this.w, required this.h});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        w * 0.041,
        h * 0.018,
        w * 0.041,
        h * 0.014,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Warning icon circle
          Container(
            width:  w * 0.092,
            height: w * 0.092,
            decoration: const BoxDecoration(
              color: _warningLight,
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.warning_amber_rounded,
              color: _warning,
              size: w * 0.046,
            ),
          ),
          SizedBox(width: w * 0.031),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Emergency Broadcasting',
                  style: TextStyle(
                    fontFamily: 'Raleway',
                    fontSize: w * 0.038,
                    fontWeight: FontWeight.w600,
                    color: _textPrimary,
                    height: 1.3,
                  ),
                ),
                SizedBox(height: h * 0.005),
                Text(
                  'Receive government and neighbourhood safety alerts '
                  'immediately, regardless of silent mode.',
                  style: TextStyle(
                    fontFamily: 'Raleway',
                    fontSize: w * 0.031,
                    fontWeight: FontWeight.w400,
                    color: _textSecondary,
                    height: 1.45,
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

// ── Critical Safety Alerts row ────────────────────────────────────────────────
// Sub-item under Emergency Broadcasting — boxed appearance inside the card.

class _CriticalSafetyRow extends StatelessWidget {
  final bool value;
  final ValueChanged<bool> onChanged;
  final double w;
  final double h;

  const _CriticalSafetyRow({
    required this.value,
    required this.onChanged,
    required this.w,
    required this.h,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: w * 0.041,
        vertical:   h * 0.012,
      ),
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: w * 0.038,
          vertical:   h * 0.013,
        ),
        decoration: BoxDecoration(
          color:        _surfaceGrey,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: _divider, width: 1),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                'Critical Safety Alerts',
                style: TextStyle(
                  fontFamily: 'Raleway',
                  fontSize: w * 0.038,
                  fontWeight: FontWeight.w600,
                  color: _textPrimary,
                  height: 1.3,
                ),
              ),
            ),
            Switch(
              value:              value,
              activeThumbColor:   Colors.white,
              activeTrackColor:   _gold,
              inactiveThumbColor: Colors.white,
              inactiveTrackColor: _disabled,
              trackOutlineColor:  const WidgetStatePropertyAll(Colors.transparent),
              onChanged: onChanged,
            ),
          ],
        ),
      ),
    );
  }
}

// ── Promo Frequency row ───────────────────────────────────────────────────────

class _PromoFrequencyRow extends StatelessWidget {
  final PromoFrequency selected;
  final ValueChanged<PromoFrequency> onSelect;
  final double w;
  final double h;

  const _PromoFrequencyRow({
    required this.selected,
    required this.onSelect,
    required this.w,
    required this.h,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: w * 0.041,
        vertical:   h * 0.016,
      ),
      child: Row(
        children: [
          // Clock icon circle
          Container(
            width:  w * 0.092,
            height: w * 0.092,
            decoration: const BoxDecoration(
              color: _surfaceGrey,
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.access_time_rounded,
              color: _textSecondary,
              size: w * 0.046,
            ),
          ),
          SizedBox(width: w * 0.031),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Promo Frequency',
                  style: TextStyle(
                    fontFamily: 'Raleway',
                    fontSize: w * 0.038,
                    fontWeight: FontWeight.w600,
                    color: _textPrimary,
                    height: 1.3,
                  ),
                ),
                SizedBox(height: h * 0.010),
                // Segmented picker
                _PromoSegmented(
                  selected: selected,
                  onSelect: onSelect,
                  w: w,
                  h: h,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Promo Segmented control ───────────────────────────────────────────────────

class _PromoSegmented extends StatelessWidget {
  final PromoFrequency selected;
  final ValueChanged<PromoFrequency> onSelect;
  final double w;
  final double h;

  const _PromoSegmented({
    required this.selected,
    required this.onSelect,
    required this.w,
    required this.h,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color:        _surfaceGrey,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _divider, width: 1),
      ),
      child: Row(
        children: PromoFrequency.values.map((freq) {
          final isSelected = freq == selected;
          final isFirst    = freq == PromoFrequency.values.first;
          final isLast     = freq == PromoFrequency.values.last;
          return Expanded(
            child: GestureDetector(
              onTap: () => onSelect(freq),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeInOut,
                padding: EdgeInsets.symmetric(vertical: h * 0.011),
                decoration: BoxDecoration(
                  color: isSelected ? _gold : Colors.transparent,
                  borderRadius: BorderRadius.horizontal(
                    left:  isFirst ? const Radius.circular(7) : Radius.zero,
                    right: isLast  ? const Radius.circular(7) : Radius.zero,
                  ),
                ),
                child: Text(
                  freq.label,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: 'Raleway',
                    fontSize: w * 0.034,
                    fontWeight:
                        isSelected ? FontWeight.w700 : FontWeight.w500,
                    color: isSelected ? Colors.white : _textSecondary,
                    height: 1.3,
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

// ── System Preview card ───────────────────────────────────────────────────────

class _PreviewCard extends StatelessWidget {
  final double w;
  final double h;
  const _PreviewCard({required this.w, required this.h});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: EdgeInsets.symmetric(horizontal: w * 0.044),
      decoration: BoxDecoration(
        color:        _surfaceWhite,
        borderRadius: BorderRadius.circular(12),
        boxShadow: const [
          BoxShadow(
            color:     Color(0x0D000000),
            blurRadius: 8,
            offset:     Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header text
          Padding(
            padding: EdgeInsets.fromLTRB(
              w * 0.041,
              h * 0.016,
              w * 0.041,
              h * 0.012,
            ),
            child: Text(
              'Preview of how your notifications appear',
              style: TextStyle(
                fontFamily: 'Raleway',
                fontSize: w * 0.031,
                fontWeight: FontWeight.w400,
                color: _textSecondary,
                height: 1.4,
              ),
            ),
          ),
          // Divider
          const Divider(color: _divider, height: 1, thickness: 1),
          // Notification preview item
          Padding(
            padding: EdgeInsets.symmetric(
              horizontal: w * 0.041,
              vertical:   h * 0.016,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // App icon circle
                Container(
                  width:  w * 0.100,
                  height: w * 0.100,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF46535D), _gold],
                      begin: Alignment.topLeft,
                      end:   Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(w * 0.022),
                  ),
                  child: Icon(
                    Icons.bolt_rounded,
                    color: Colors.white,
                    size: w * 0.052,
                  ),
                ),
                SizedBox(width: w * 0.031),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              'App Update',
                              style: TextStyle(
                                fontFamily: 'Raleway',
                                fontSize: w * 0.036,
                                fontWeight: FontWeight.w700,
                                color: _textPrimary,
                                height: 1.3,
                              ),
                            ),
                          ),
                          Text(
                            'from',
                            style: TextStyle(
                              fontFamily: 'Raleway',
                              fontSize: w * 0.028,
                              fontWeight: FontWeight.w400,
                              color: _textSecondary,
                              height: 1.4,
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: h * 0.004),
                      Text(
                        "Your saved place 'Accra Mall' has a new...",
                        style: TextStyle(
                          fontFamily: 'Raleway',
                          fontSize: w * 0.031,
                          fontWeight: FontWeight.w400,
                          color: _textSecondary,
                          height: 1.4,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
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

// ── Send Test Notification button ─────────────────────────────────────────────

class _SendTestButton extends ConsumerStatefulWidget {
  final double w;
  final double h;
  const _SendTestButton({required this.w, required this.h});

  @override
  ConsumerState<_SendTestButton> createState() => _SendTestButtonState();
}

class _SendTestButtonState extends ConsumerState<_SendTestButton> {
  bool _loading = false;

  Future<void> _onTap() async {
    if (_loading) return;
    setState(() => _loading = true);
    await ref
        .read(notificationSettingsProvider.notifier)
        .sendTestNotification();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Test notification sent!'),
        backgroundColor: _darkSlate,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        margin: EdgeInsets.fromLTRB(
          widget.w * 0.044,
          0,
          widget.w * 0.044,
          widget.h * 0.032,
        ),
        duration: const Duration(seconds: 2),
      ),
    );
    setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    final w = widget.w;
    final h = widget.h;

    return SizedBox(
      width:  double.infinity,
      height: h * 0.064,
      child: Material(
        color:        _darkSlate,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          onTap:        _loading ? null : _onTap,
          borderRadius: BorderRadius.circular(8),
          splashColor: Colors.white.withValues(alpha: 0.12),
          child: Center(
            child: _loading
                ? SizedBox(
                    width:  w * 0.052,
                    height: w * 0.052,
                    child: const CircularProgressIndicator(
                      color: Colors.white,
                      strokeWidth: 2,
                    ),
                  )
                : Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.auto_awesome_rounded,
                        color: Colors.white,
                        size: w * 0.046,
                      ),
                      SizedBox(width: w * 0.025),
                      Text(
                        'Send Test Notification',
                        style: TextStyle(
                          fontFamily: 'Raleway',
                          fontSize: w * 0.040,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                          height: 1.3,
                        ),
                      ),
                    ],
                  ),
          ),
        ),
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
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(Icons.lock_outline_rounded, color: _disabled, size: w * 0.036),
        SizedBox(width: w * 0.015),
        Text(
          'End-to-End Encrypted',
          style: TextStyle(
            fontFamily: 'Raleway',
            fontSize: w * 0.029,
            fontWeight: FontWeight.w400,
            color: _disabled,
            height: 1.4,
          ),
        ),
        SizedBox(width: w * 0.025),
        Container(
          width:  w * 0.010,
          height: w * 0.010,
          decoration: const BoxDecoration(
            color: _disabled,
            shape: BoxShape.circle,
          ),
        ),
        SizedBox(width: w * 0.025),
        Icon(Icons.sync_rounded, color: _disabled, size: w * 0.036),
        SizedBox(width: w * 0.015),
        Text(
          'Device Synced',
          style: TextStyle(
            fontFamily: 'Raleway',
            fontSize: w * 0.029,
            fontWeight: FontWeight.w400,
            color: _disabled,
            height: 1.4,
          ),
        ),
      ],
    );
  }
}
