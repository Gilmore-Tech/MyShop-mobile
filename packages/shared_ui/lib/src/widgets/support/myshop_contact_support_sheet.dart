import 'package:flutter/material.dart';

import '../../theme/myshop_colors.dart';
import '../../theme/myshop_spacing.dart';
import '../../theme/myshop_typography.dart';
import '../myshop_toast.dart';
import 'support_channels.dart';

const Color _kWhatsappGreen = Color(0xFF25D366);

/// Bottom sheet exposing the four support contact channels:
/// WhatsApp, phone, email, in-app ticket form.
///
/// Caller wires:
///   - [whatsappNumber] / [supportPhone] / [supportEmail] — copy + dial info
///   - [onNewTicket] — navigate to the new-ticket form (caller closes sheet)
///
/// The sheet itself launches WhatsApp / tel: / mailto: directly via
/// [SupportChannels]; only the in-app ticket button delegates to the
/// caller because that one needs router access.
class MyShopContactSupportSheet extends StatelessWidget {
  const MyShopContactSupportSheet({
    super.key,
    required this.whatsappNumber,
    required this.supportPhone,
    required this.supportEmail,
    required this.onNewTicket,
    this.whatsappPrefill,
    this.emailSubjectPrefill,
  });

  final String whatsappNumber;
  final String supportPhone;
  final String supportEmail;
  final VoidCallback onNewTicket;

  /// Optional message body pre-filled into the WhatsApp deeplink.
  final String? whatsappPrefill;

  /// Optional `subject=` value baked into the mailto: link.
  final String? emailSubjectPrefill;

  /// Convenience to present the sheet — handles `showModalBottomSheet`
  /// boilerplate. Call from any onTap.
  static Future<void> show(
    BuildContext context, {
    required String whatsappNumber,
    required String supportPhone,
    required String supportEmail,
    required VoidCallback onNewTicket,
    String? whatsappPrefill,
    String? emailSubjectPrefill,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => MyShopContactSupportSheet(
        whatsappNumber: whatsappNumber,
        supportPhone: supportPhone,
        supportEmail: supportEmail,
        onNewTicket: onNewTicket,
        whatsappPrefill: whatsappPrefill,
        emailSubjectPrefill: emailSubjectPrefill,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.only(bottom: bottomInset),
        child: Container(
          decoration: const BoxDecoration(
            color: MyShopColors.surfaceWhite,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          padding: const EdgeInsets.fromLTRB(
            MyShopSpacing.md,
            MyShopSpacing.md,
            MyShopSpacing.md,
            MyShopSpacing.lg,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: MyShopColors.divider,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: MyShopSpacing.md),
              Text(
                'Contact Support',
                style: MyShopTypography.h3.copyWith(fontSize: 18),
              ),
              const SizedBox(height: 4),
              const Text(
                'Reach us through any of these channels.',
                style: MyShopTypography.body2,
              ),
              const SizedBox(height: MyShopSpacing.md),
              _ChannelTile(
                icon: Icons.chat_outlined,
                iconBg: _kWhatsappGreen,
                iconColor: MyShopColors.surfaceWhite,
                title: 'WhatsApp',
                subtitle: '+$whatsappNumber',
                onTap: () async {
                  Navigator.of(context).pop();
                  final ok = await SupportChannels.openWhatsApp(
                    number: whatsappNumber,
                    message: whatsappPrefill,
                  );
                  if (!ok && context.mounted) {
                    MyShopToast.show(
                      context,
                      message: 'WhatsApp not installed. Try another channel.',
                    );
                  }
                },
              ),
              const SizedBox(height: MyShopSpacing.sm),
              _ChannelTile(
                icon: Icons.flag_outlined,
                iconBg: MyShopColors.darkSlate,
                iconColor: MyShopColors.textOnDarkSlate,
                title: 'Open a ticket',
                subtitle: 'Track replies in the app',
                onTap: () {
                  Navigator.of(context).pop();
                  onNewTicket();
                },
              ),
              const SizedBox(height: MyShopSpacing.sm),
              _ChannelTile(
                icon: Icons.phone_outlined,
                iconBg: MyShopColors.primaryGold,
                iconColor: MyShopColors.textOnPrimary,
                title: 'Call support',
                subtitle: supportPhone,
                onTap: () async {
                  Navigator.of(context).pop();
                  final ok = await SupportChannels.openPhone(supportPhone);
                  if (!ok && context.mounted) {
                    MyShopToast.show(
                      context,
                      message: 'Could not start a call. Try another channel.',
                    );
                  }
                },
              ),
              const SizedBox(height: MyShopSpacing.sm),
              _ChannelTile(
                icon: Icons.mail_outline,
                iconBg: MyShopColors.surfaceGrey,
                iconColor: MyShopColors.textPrimary,
                title: 'Email us',
                subtitle: supportEmail,
                onTap: () async {
                  Navigator.of(context).pop();
                  final ok = await SupportChannels.openEmail(
                    to: supportEmail,
                    subject: emailSubjectPrefill,
                  );
                  if (!ok && context.mounted) {
                    MyShopToast.show(
                      context,
                      message: 'Email us at $supportEmail',
                      duration: const Duration(seconds: 5),
                    );
                  }
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ChannelTile extends StatelessWidget {
  const _ChannelTile({
    required this.icon,
    required this.iconBg,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final Color iconBg;
  final Color iconColor;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(MyShopSpacing.md),
        decoration: BoxDecoration(
          color: MyShopColors.surfaceWhite,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: MyShopColors.divider),
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: iconBg,
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: iconColor, size: 20),
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
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(subtitle, style: MyShopTypography.body2),
                ],
              ),
            ),
            const Icon(
              Icons.chevron_right_rounded,
              color: MyShopColors.textSecondary,
            ),
          ],
        ),
      ),
    );
  }
}
