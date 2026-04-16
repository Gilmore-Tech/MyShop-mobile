import 'package:flutter/material.dart';
import 'package:shared_ui/shared_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

// ── Screen ─────────────────────────────────────────────────────────────────────
// PRD § 4.11 — Client manages saved payment methods.
// Supported: MTN MoMo, Vodafone Cash, AirtelTigo Money, Visa/Mastercard.
// EDD: GET /v1/payment-methods  |  DELETE /v1/payment-methods/:id
//      POST /v1/payment-methods/momo  { provider, phone }
//      POST /v1/payment-methods/card  (via Flutterwave SDK)

class PaymentMethodsScreen extends ConsumerStatefulWidget {
  const PaymentMethodsScreen({super.key});

  @override
  ConsumerState<PaymentMethodsScreen> createState() =>
      _PaymentMethodsScreenState();
}

class _PaymentMethodsScreenState
    extends ConsumerState<PaymentMethodsScreen> {
  String _defaultId = 'mtn-0';

  void _setDefault(String id) => setState(() => _defaultId = id);

  void _showAddSheet(BuildContext ctx) {
    showModalBottomSheet<void>(
      context: ctx,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _AddMethodSheet(w: MediaQuery.sizeOf(ctx).width),
    );
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final w    = size.width;
    final h    = size.height;

    return Scaffold(
      backgroundColor: MyShopColors.offWhite,
      appBar: AppBar(
        backgroundColor: MyShopColors.surfaceWhite,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back,
              color: MyShopColors.textPrimary),
          onPressed: () => context.pop(),
        ),
        title: Text('Payment Methods',
            style: TextStyle(
                color:      MyShopColors.textPrimary,
                fontSize:   w * 0.044,
                fontWeight: FontWeight.w700)),
        centerTitle: false,
      ),
      body: SingleChildScrollView(
        padding: EdgeInsets.all(w * 0.05),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _SectionLabel(text: 'MOBILE MONEY', w: w),
            SizedBox(height: h * 0.012),
            _MethodCard(
              id:         'mtn-0',
              icon:       Icons.phone_android_rounded,
              iconColor:  MyShopColors.primaryGold,
              iconBg:     MyShopColors.primaryGoldLight,
              title:      'MTN MoMo',
              subtitle:   '+233 •••• •••• 42',
              isDefault:  _defaultId == 'mtn-0',
              onSetDefault: () => _setDefault('mtn-0'),
              onDelete:   () {},
              w: w, h: h,
            ),
            SizedBox(height: h * 0.012),
            _MethodCard(
              id:         'voda-0',
              icon:       Icons.phone_android_rounded,
              iconColor:  MyShopColors.error,
              iconBg:     MyShopColors.errorLight,
              title:      'Vodafone Cash',
              subtitle:   '+233 •••• •••• 87',
              isDefault:  _defaultId == 'voda-0',
              onSetDefault: () => _setDefault('voda-0'),
              onDelete:   () {},
              w: w, h: h,
            ),
            SizedBox(height: h * 0.024),
            _SectionLabel(text: 'CARDS', w: w),
            SizedBox(height: h * 0.012),
            _MethodCard(
              id:         'visa-0',
              icon:       Icons.credit_card_rounded,
              iconColor:  MyShopColors.info,
              iconBg:     MyShopColors.infoLight,
              title:      'Visa  ••••  4242',
              subtitle:   'Expires 08 / 27',
              isDefault:  _defaultId == 'visa-0',
              onSetDefault: () => _setDefault('visa-0'),
              onDelete:   () {},
              w: w, h: h,
            ),
            SizedBox(height: h * 0.028),
            // Add new
            SizedBox(
              width:  double.infinity,
              height: h * 0.062,
              child: OutlinedButton.icon(
                onPressed: () => _showAddSheet(context),
                icon:  const Icon(Icons.add_rounded),
                label: const Text('Add Payment Method'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: MyShopColors.primaryGold,
                  side:  const BorderSide(color: MyShopColors.primaryGold),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
            SizedBox(height: h * 0.020),
            _SecurityNote(w: w),
          ],
        ),
      ),
    );
  }
}

// ── Method card ────────────────────────────────────────────────────────────────

class _MethodCard extends StatelessWidget {
  final String     id;
  final IconData   icon;
  final Color      iconColor, iconBg;
  final String     title, subtitle;
  final bool       isDefault;
  final VoidCallback onSetDefault;
  final VoidCallback onDelete;
  final double     w, h;

  const _MethodCard({
    required this.id,
    required this.icon,
    required this.iconColor,
    required this.iconBg,
    required this.title,
    required this.subtitle,
    required this.isDefault,
    required this.onSetDefault,
    required this.onDelete,
    required this.w,
    required this.h,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(w * 0.04),
      decoration: BoxDecoration(
        color:        MyShopColors.surfaceWhite,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
            color: isDefault ? MyShopColors.primaryGold : MyShopColors.divider,
            width: isDefault ? 1.5 : 1),
        boxShadow: [
          BoxShadow(
              color:      Colors.black.withAlpha(6),
              blurRadius: 6,
              offset:     const Offset(0, 2)),
        ],
      ),
      child: Row(
        children: [
          Container(
            width:  w * 0.12,
            height: w * 0.12,
            decoration: BoxDecoration(
                color: iconBg, borderRadius: BorderRadius.circular(10)),
            child: Icon(icon, color: iconColor, size: w * 0.056),
          ),
          SizedBox(width: w * 0.030),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(title,
                        style: TextStyle(
                          color:      MyShopColors.textPrimary,
                          fontSize:   w * 0.038,
                          fontWeight: FontWeight.w700,
                        )),
                    if (isDefault) ...[
                      SizedBox(width: w * 0.016),
                      Container(
                        padding: EdgeInsets.symmetric(
                            horizontal: w * 0.018, vertical: 2),
                        decoration: BoxDecoration(
                          color:        MyShopColors.successLight,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text('Default',
                            style: TextStyle(
                              color:      MyShopColors.success,
                              fontSize:   w * 0.024,
                              fontWeight: FontWeight.w600,
                            )),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 3),
                Text(subtitle,
                    style: TextStyle(
                        color:    MyShopColors.textSecondary,
                        fontSize: w * 0.032)),
              ],
            ),
          ),
          PopupMenuButton<String>(
            icon: Icon(Icons.more_vert_rounded,
                color: MyShopColors.textSecondary, size: w * 0.050),
            onSelected: (val) {
              if (val == 'default') onSetDefault();
              if (val == 'delete') onDelete();
            },
            itemBuilder: (_) => [
              if (!isDefault)
                const PopupMenuItem(
                    value: 'default',
                    child: Text('Set as default')),
              const PopupMenuItem(
                  value: 'delete',
                  child: Text('Remove',
                      style: TextStyle(color: MyShopColors.error))),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Add method sheet ───────────────────────────────────────────────────────────

class _AddMethodSheet extends StatelessWidget {
  final double w;
  const _AddMethodSheet({required this.w});

  static const _options = [
    (icon: Icons.phone_android_rounded, color: MyShopColors.primaryGold,
     bg: MyShopColors.primaryGoldLight, label: 'MTN MoMo'),
    (icon: Icons.phone_android_rounded, color: MyShopColors.error,
     bg: MyShopColors.errorLight, label: 'Vodafone Cash'),
    (icon: Icons.phone_android_rounded, color: MyShopColors.success,
     bg: MyShopColors.successLight, label: 'AirtelTigo Money'),
    (icon: Icons.credit_card_rounded,   color: MyShopColors.info,
     bg: MyShopColors.infoLight, label: 'Visa / Mastercard'),
  ];

  @override
  Widget build(BuildContext context) {
    final h = MediaQuery.sizeOf(context).height;
    final bot = MediaQuery.paddingOf(context).bottom;
    return Container(
      decoration: const BoxDecoration(
        color:        MyShopColors.surfaceWhite,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: EdgeInsets.fromLTRB(
          w * 0.05, h * 0.020, w * 0.05, bot + h * 0.028),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: w * 0.10, height: 4,
              decoration: BoxDecoration(
                color:        MyShopColors.surfaceGrey,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          SizedBox(height: h * 0.020),
          Text('Add payment method',
              style: TextStyle(
                color:      MyShopColors.textPrimary,
                fontSize:   w * 0.044,
                fontWeight: FontWeight.w700,
              )),
          SizedBox(height: h * 0.020),
          ..._options.map((o) => ListTile(
                contentPadding: EdgeInsets.symmetric(
                    horizontal: w * 0.01, vertical: 2),
                leading: Container(
                  width:  w * 0.11,
                  height: w * 0.11,
                  decoration: BoxDecoration(
                      color:        o.bg,
                      borderRadius: BorderRadius.circular(10)),
                  child: Icon(o.icon, color: o.color, size: w * 0.052),
                ),
                title: Text(o.label,
                    style: TextStyle(
                      color:      MyShopColors.textPrimary,
                      fontSize:   w * 0.038,
                      fontWeight: FontWeight.w600,
                    )),
                trailing: const Icon(Icons.chevron_right_rounded,
                    color: MyShopColors.textSecondary),
                onTap: () => Navigator.pop(context),
              )),
        ],
      ),
    );
  }
}

// ── Section label ──────────────────────────────────────────────────────────────

class _SectionLabel extends StatelessWidget {
  final String text;
  final double w;
  const _SectionLabel({required this.text, required this.w});

  @override
  Widget build(BuildContext context) {
    return Text(text,
        style: TextStyle(
          color:         MyShopColors.textSecondary,
          fontSize:      w * 0.028,
          fontWeight:    FontWeight.w900,
          letterSpacing: 1.2,
        ));
  }
}

// ── Security note ──────────────────────────────────────────────────────────────

class _SecurityNote extends StatelessWidget {
  final double w;
  const _SecurityNote({required this.w});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Icon(Icons.lock_outline_rounded,
            color: MyShopColors.success, size: 16),
        SizedBox(width: w * 0.020),
        Expanded(
          child: Text(
            'Your payment details are encrypted and stored securely. '
            'MyShop never stores your full card number.',
            style: TextStyle(
                color:    MyShopColors.textSecondary,
                fontSize: w * 0.030,
                height:   1.5),
          ),
        ),
      ],
    );
  }
}
