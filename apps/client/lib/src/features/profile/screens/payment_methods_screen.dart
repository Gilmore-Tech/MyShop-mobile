import 'package:flutter/material.dart';
import 'package:shared_ui/shared_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../providers/payment_methods_provider.dart';

// ── Screen ─────────────────────────────────────────────────────────────────────
// PRD § 4.11 — Client manages saved payment methods.
// Supported: MTN MoMo, Vodafone Cash, AirtelTigo Money, Visa/Mastercard.
// EDD: GET /payment-methods  |  DELETE /payment-methods/:id
//      POST /payment-methods/momo  { provider, phone }
//      POST /payment-methods/card  (via Flutterwave SDK)

class PaymentMethodsScreen extends ConsumerWidget {
  const PaymentMethodsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final size = MediaQuery.sizeOf(context);
    final w = size.width;
    final h = size.height;
    final state = ref.watch(paymentMethodsProvider);

    return Scaffold(
      backgroundColor: MyShopColors.offWhite,
      appBar: AppBar(
        backgroundColor: MyShopColors.surfaceWhite,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: MyShopColors.textPrimary),
          onPressed: () => context.pop(),
        ),
        title: Text('Payment Methods',
            style: TextStyle(
                color: MyShopColors.textPrimary,
                fontSize: w * 0.044,
                fontWeight: FontWeight.w700)),
        centerTitle: false,
      ),
      body: _Body(state: state, w: w, h: h),
    );
  }
}

// ── Body ───────────────────────────────────────────────────────────────────────

class _Body extends ConsumerWidget {
  final PaymentMethodsState state;
  final double w, h;
  const _Body({required this.state, required this.w, required this.h});

  void _showAddSheet(BuildContext ctx, WidgetRef ref) {
    showModalBottomSheet<void>(
      context: ctx,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _AddMethodSheet(
          w: w,
          onAdded: () {
            ref.read(paymentMethodsProvider.notifier).reload();
          }),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (state.isLoading) {
      return const Center(
          child: CircularProgressIndicator(color: MyShopColors.primaryGold));
    }

    return SingleChildScrollView(
      padding: EdgeInsets.all(w * 0.05),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (state.errorMessage != null)
            _ErrorBanner(message: state.errorMessage!, w: w),

          if (state.momoMethods.isNotEmpty) ...[
            _SectionLabel(text: 'MOBILE MONEY', w: w),
            SizedBox(height: h * 0.012),
            ...state.momoMethods.map((m) => Padding(
                  padding: EdgeInsets.only(bottom: h * 0.012),
                  child: _MethodCard(
                    method: m,
                    isDeleting: state.deletingId == m.id,
                    onSetDefault: () => ref
                        .read(paymentMethodsProvider.notifier)
                        .setDefault(m.id),
                    onDelete: () => ref
                        .read(paymentMethodsProvider.notifier)
                        .deleteMethod(m.id),
                    w: w,
                    h: h,
                  ),
                )),
            SizedBox(height: h * 0.012),
          ],

          if (state.cardMethods.isNotEmpty) ...[
            _SectionLabel(text: 'CARDS', w: w),
            SizedBox(height: h * 0.012),
            ...state.cardMethods.map((m) => Padding(
                  padding: EdgeInsets.only(bottom: h * 0.012),
                  child: _MethodCard(
                    method: m,
                    isDeleting: state.deletingId == m.id,
                    onSetDefault: () => ref
                        .read(paymentMethodsProvider.notifier)
                        .setDefault(m.id),
                    onDelete: () => ref
                        .read(paymentMethodsProvider.notifier)
                        .deleteMethod(m.id),
                    w: w,
                    h: h,
                  ),
                )),
            SizedBox(height: h * 0.016),
          ],

          if (state.methods.isEmpty && !state.isLoading)
            _EmptyState(w: w, h: h),

          SizedBox(height: h * 0.016),

          // Add new
          SizedBox(
            width: double.infinity,
            height: h * 0.062,
            child: OutlinedButton.icon(
              onPressed: () => _showAddSheet(context, ref),
              icon: const Icon(Icons.add_rounded),
              label: const Text('Add Payment Method'),
              style: OutlinedButton.styleFrom(
                foregroundColor: MyShopColors.primaryGold,
                side: const BorderSide(color: MyShopColors.primaryGold),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
          SizedBox(height: h * 0.020),
          _SecurityNote(w: w),
        ],
      ),
    );
  }
}

// ── Error banner ───────────────────────────────────────────────────────────────

class _ErrorBanner extends StatelessWidget {
  final String message;
  final double w;
  const _ErrorBanner({required this.message, required this.w});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: EdgeInsets.only(bottom: w * 0.032),
      padding: EdgeInsets.symmetric(horizontal: w * 0.04, vertical: 12),
      decoration: BoxDecoration(
        color: MyShopColors.errorLight,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: MyShopColors.error.withAlpha(60)),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline_rounded,
              color: MyShopColors.error, size: 18),
          SizedBox(width: w * 0.024),
          Expanded(
            child: Text(message,
                style:
                    TextStyle(color: MyShopColors.error, fontSize: w * 0.032)),
          ),
        ],
      ),
    );
  }
}

// ── Empty state ────────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  final double w, h;
  const _EmptyState({required this.w, required this.h});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: h * 0.04),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.payment_rounded,
                color: MyShopColors.textSecondary.withAlpha(100),
                size: w * 0.14),
            SizedBox(height: h * 0.016),
            Text('No payment methods saved',
                style: TextStyle(
                  color: MyShopColors.textSecondary,
                  fontSize: w * 0.038,
                  fontWeight: FontWeight.w600,
                )),
            SizedBox(height: h * 0.008),
            Text('Add a MoMo wallet or card to pay faster',
                style: TextStyle(
                    color: MyShopColors.textSecondary, fontSize: w * 0.032)),
          ],
        ),
      ),
    );
  }
}

// ── Method card ────────────────────────────────────────────────────────────────

class _MethodCard extends StatelessWidget {
  final PaymentMethod method;
  final bool isDeleting;
  final VoidCallback onSetDefault;
  final VoidCallback onDelete;
  final double w, h;

  const _MethodCard({
    required this.method,
    required this.isDeleting,
    required this.onSetDefault,
    required this.onDelete,
    required this.w,
    required this.h,
  });

  Color get _iconColor {
    if (method.momoProvider != null) return method.momoProvider!.color;
    return MyShopColors.info;
  }

  Color get _iconBg {
    if (method.momoProvider != null) return method.momoProvider!.bgColor;
    return MyShopColors.infoLight;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(w * 0.04),
      decoration: BoxDecoration(
        color: MyShopColors.surfaceWhite,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
            color: method.isDefault
                ? MyShopColors.primaryGold
                : MyShopColors.divider,
            width: method.isDefault ? 1.5 : 1),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withAlpha(6),
              blurRadius: 6,
              offset: const Offset(0, 2)),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: w * 0.12,
            height: w * 0.12,
            decoration: BoxDecoration(
                color: _iconBg, borderRadius: BorderRadius.circular(10)),
            child: isDeleting
                ? const Center(
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: MyShopColors.error),
                    ),
                  )
                : Icon(method.type.icon, color: _iconColor, size: w * 0.056),
          ),
          SizedBox(width: w * 0.030),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(method.title,
                        style: TextStyle(
                          color: MyShopColors.textPrimary,
                          fontSize: w * 0.038,
                          fontWeight: FontWeight.w700,
                        )),
                    if (method.isDefault) ...[
                      SizedBox(width: w * 0.016),
                      Container(
                        padding: EdgeInsets.symmetric(
                            horizontal: w * 0.018, vertical: 2),
                        decoration: BoxDecoration(
                          color: MyShopColors.successLight,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text('Default',
                            style: TextStyle(
                              color: MyShopColors.success,
                              fontSize: w * 0.024,
                              fontWeight: FontWeight.w600,
                            )),
                      ),
                    ],
                  ],
                ),
                if (method.subtitle.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(method.subtitle,
                      style: TextStyle(
                          color: MyShopColors.textSecondary,
                          fontSize: w * 0.032)),
                ],
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
              if (!method.isDefault)
                const PopupMenuItem(
                    value: 'default', child: Text('Set as default')),
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

class _AddMethodSheet extends ConsumerStatefulWidget {
  final double w;
  final VoidCallback onAdded;
  const _AddMethodSheet({required this.w, required this.onAdded});

  @override
  ConsumerState<_AddMethodSheet> createState() => _AddMethodSheetState();
}

class _AddMethodSheetState extends ConsumerState<_AddMethodSheet> {
  MomoProvider? _selectedMomo;
  final _phoneController = TextEditingController();
  bool _loading = false;

  @override
  void dispose() {
    _phoneController.dispose();
    super.dispose();
  }

  Future<void> _saveMomo() async {
    if (_selectedMomo == null || _phoneController.text.trim().isEmpty) return;
    setState(() => _loading = true);
    final ok = await ref.read(paymentMethodsProvider.notifier).addMomo(
          provider: _selectedMomo!,
          phone: _phoneController.text.trim(),
        );
    if (!mounted) return;
    if (ok) {
      widget.onAdded();
      Navigator.of(context).pop();
    } else {
      setState(() => _loading = false);
      MyShopToast.show(context,
          message: 'Could not add method. Please try again.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final h = MediaQuery.sizeOf(context).height;
    final bot = MediaQuery.paddingOf(context).bottom;
    final w = widget.w;

    return Container(
      decoration: const BoxDecoration(
        color: MyShopColors.surfaceWhite,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding:
          EdgeInsets.fromLTRB(w * 0.05, h * 0.020, w * 0.05, bot + h * 0.028),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: w * 0.10,
              height: 4,
              decoration: BoxDecoration(
                color: MyShopColors.surfaceGrey,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          SizedBox(height: h * 0.020),
          Text('Add Mobile Money',
              style: TextStyle(
                color: MyShopColors.textPrimary,
                fontSize: w * 0.044,
                fontWeight: FontWeight.w700,
              )),
          SizedBox(height: h * 0.020),

          // Provider selection
          Text('Provider',
              style: TextStyle(
                  color: MyShopColors.textSecondary,
                  fontSize: w * 0.032,
                  fontWeight: FontWeight.w600)),
          SizedBox(height: h * 0.010),
          ...MomoProvider.values.map((p) {
            final isSelected = _selectedMomo == p;
            return InkWell(
              onTap: () => setState(() => _selectedMomo = p),
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: h * 0.010),
                child: Row(
                  children: [
                    Container(
                      width: w * 0.11,
                      height: w * 0.11,
                      decoration: BoxDecoration(
                          color: p.bgColor,
                          borderRadius: BorderRadius.circular(10)),
                      child: Icon(Icons.phone_android_rounded,
                          color: p.color, size: w * 0.052),
                    ),
                    SizedBox(width: w * 0.028),
                    Expanded(
                      child: Text(p.label,
                          style: TextStyle(
                            color: MyShopColors.textPrimary,
                            fontSize: w * 0.038,
                            fontWeight: FontWeight.w600,
                          )),
                    ),
                    // Custom radio indicator — avoids deprecated Radio.groupValue
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      width: 22,
                      height: 22,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: isSelected
                              ? MyShopColors.primaryGold
                              : MyShopColors.divider,
                          width: isSelected ? 6 : 2,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          }),

          SizedBox(height: h * 0.016),

          // Phone field
          Text('Phone number',
              style: TextStyle(
                  color: MyShopColors.textSecondary,
                  fontSize: w * 0.032,
                  fontWeight: FontWeight.w600)),
          SizedBox(height: h * 0.008),
          TextField(
            controller: _phoneController,
            keyboardType: TextInputType.phone,
            decoration: InputDecoration(
              hintText: '+233 XX XXX XXXX',
              prefixIcon: const Icon(Icons.phone_outlined),
              border:
                  OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              contentPadding:
                  EdgeInsets.symmetric(horizontal: w * 0.038, vertical: 14),
            ),
          ),

          SizedBox(height: h * 0.024),

          SizedBox(
            width: double.infinity,
            height: h * 0.062,
            child: ElevatedButton(
              onPressed:
                  (_selectedMomo != null && !_loading) ? _saveMomo : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: MyShopColors.primaryGold,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
                elevation: 0,
              ),
              child: _loading
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                          color: Colors.white, strokeWidth: 2))
                  : const Text('Save',
                      style:
                          TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
            ),
          ),
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
          color: MyShopColors.textSecondary,
          fontSize: w * 0.028,
          fontWeight: FontWeight.w900,
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
                color: MyShopColors.textSecondary,
                fontSize: w * 0.030,
                height: 1.5),
          ),
        ),
      ],
    );
  }
}
