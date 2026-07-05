import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_ui/shared_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../providers/referral_provider.dart';

// ── Screen ─────────────────────────────────────────────────────────────────────
// PRD § 4.9 — Referral programme: share code, earn loyalty points per referral.
// EDD: GET /users/me/referral  → { code, totalReferrals, pendingPesewas, earnedPesewas }

class ReferralScreen extends ConsumerWidget {
  const ReferralScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final size = MediaQuery.sizeOf(context);
    final w = size.width;
    final h = size.height;
    final async = ref.watch(referralProvider);

    return Scaffold(
      backgroundColor: MyShopColors.offWhite,
      appBar: AppBar(
        backgroundColor: MyShopColors.surfaceWhite,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: MyShopColors.textPrimary),
          onPressed: () => context.pop(),
        ),
        title: Text('Refer & Earn',
            style: TextStyle(
                color: MyShopColors.textPrimary,
                fontSize: w * 0.044,
                fontWeight: FontWeight.w700)),
        centerTitle: false,
      ),
      body: async.when(
        loading: () => const Center(
            child: CircularProgressIndicator(color: MyShopColors.primaryGold)),
        error: (_, __) => Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline_rounded,
                  color: MyShopColors.error, size: 48),
              const SizedBox(height: 12),
              const Text('Could not load referral data'),
              const SizedBox(height: 12),
              TextButton(
                onPressed: () => ref.invalidate(referralProvider),
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
        data: (data) => SingleChildScrollView(
          padding: EdgeInsets.all(w * 0.05),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _HeroBanner(w: w, h: h),
              SizedBox(height: h * 0.024),
              _CodeCard(
                code: data.code,
                shareLink: data.shareLink,
                w: w,
                h: h,
              ),
              SizedBox(height: h * 0.024),
              _StatsRow(data: data, w: w, h: h),
              SizedBox(height: h * 0.028),
              _SectionTitle(text: 'How it works', w: w),
              SizedBox(height: h * 0.016),
              _HowItWorks(w: w, h: h),
              if (data.recentReferrals.isNotEmpty) ...[
                SizedBox(height: h * 0.028),
                _SectionTitle(text: 'Recent referrals', w: w),
                SizedBox(height: h * 0.016),
                _ReferralList(entries: data.recentReferrals, w: w, h: h),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// ── Hero banner ────────────────────────────────────────────────────────────────

class _HeroBanner extends StatelessWidget {
  final double w, h;
  const _HeroBanner({required this.w, required this.h});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(w * 0.05),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [MyShopColors.primaryGold, MyShopColors.primaryGoldDark],
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: EdgeInsets.all(w * 0.032),
            decoration: BoxDecoration(
              color: Colors.white.withAlpha(30),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(Icons.card_giftcard_rounded,
                color: Colors.white, size: w * 0.068),
          ),
          SizedBox(height: h * 0.016),
          Text('Give GHS 0.50, Get GHS 0.50',
              style: TextStyle(
                color: Colors.white,
                fontSize: w * 0.048,
                fontWeight: FontWeight.w800,
                height: 1.2,
              )),
          SizedBox(height: h * 0.008),
          Text(
            'Share your code. Your friend gets GHS 0.50 off their first ride '
            'or job, and you earn GHS 0.50 in loyalty points.',
            style: TextStyle(
                color: Colors.white.withAlpha(210),
                fontSize: w * 0.033,
                height: 1.5),
          ),
        ],
      ),
    );
  }
}

// ── Referral code card ─────────────────────────────────────────────────────────

class _CodeCard extends StatelessWidget {
  final String code;
  final String? shareLink;
  final double w, h;
  const _CodeCard({
    required this.code,
    required this.shareLink,
    required this.w,
    required this.h,
  });

  @override
  Widget build(BuildContext context) {
    final displayCode = code.isNotEmpty ? code : '—';

    return Container(
      padding: EdgeInsets.all(w * 0.04),
      decoration: BoxDecoration(
        color: MyShopColors.surfaceWhite,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withAlpha(8),
              blurRadius: 8,
              offset: const Offset(0, 2)),
        ],
      ),
      child: Column(
        children: [
          Text('Your referral code',
              style: TextStyle(
                  color: MyShopColors.textSecondary, fontSize: w * 0.032)),
          SizedBox(height: h * 0.012),
          Container(
            padding:
                EdgeInsets.symmetric(horizontal: w * 0.06, vertical: h * 0.018),
            decoration: BoxDecoration(
              color: MyShopColors.primaryGoldLight,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                  color: MyShopColors.primaryGold.withAlpha(80), width: 1.5),
            ),
            child: Text(displayCode,
                style: TextStyle(
                  color: MyShopColors.textPrimary,
                  fontSize: w * 0.056,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 4,
                )),
          ),
          SizedBox(height: h * 0.016),
          Row(
            children: [
              Expanded(
                child: _ActionBtn(
                  icon: Icons.copy_rounded,
                  label: 'Copy Code',
                  onTap: code.isEmpty
                      ? null
                      : () {
                          Clipboard.setData(ClipboardData(text: code));
                          MyShopToast.show(context, message: 'Code copied!');
                        },
                  w: w,
                  h: h,
                ),
              ),
              SizedBox(width: w * 0.030),
              Expanded(
                child: _ShareCodeButton(
                  code: code,
                  shareLink: shareLink,
                  w: w,
                  h: h,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Share button ───────────────────────────────────────────────────────────────
// Opens the native share sheet. Kept as its own widget so the iPad popover
// anchor is computed from the button's own render box (not the parent card).

class _ShareCodeButton extends StatelessWidget {
  final String code;
  final String? shareLink;
  final double w, h;

  const _ShareCodeButton({
    required this.code,
    required this.shareLink,
    required this.w,
    required this.h,
  });

  @override
  Widget build(BuildContext context) {
    return _ActionBtn(
      icon: Icons.share_rounded,
      label: 'Share',
      isPrimary: true,
      onTap: code.isEmpty ? null : () => _share(context),
      w: w,
      h: h,
    );
  }

  Future<void> _share(BuildContext context) async {
    final link = _effectiveReferralShareLink(code, shareLink);
    // On iPad the share sheet is a popover that requires a non-zero source
    // rect. Anchor to this button; if the render box is unavailable, fall back
    // to the screen centre so the origin is never null. Other platforms ignore
    // the rect, so this is safe everywhere.
    final box = context.findRenderObject() as RenderBox?;
    final Rect origin;
    if (box != null && box.hasSize) {
      origin = box.localToGlobal(Offset.zero) & box.size;
    } else {
      final size = MediaQuery.sizeOf(context);
      origin = Rect.fromCenter(
        center: Offset(size.width / 2, size.height / 2),
        width: 1,
        height: 1,
      );
    }

    try {
      await Share.share(
        'Join me on MyShop! Use my referral code '
        '$code to get GHS 0.50 off your first ride or job.\n\n'
        'Download MyShop and sign up here:\n$link',
        subject: 'Get GHS 0.50 off MyShop',
        sharePositionOrigin: origin,
      );
    } catch (_) {
      if (context.mounted) {
        MyShopToast.show(
          context,
          message: 'Could not open the share sheet',
          type: ToastType.error,
        );
      }
    }
  }
}

String _effectiveReferralShareLink(String code, String? shareLink) {
  final cleanLink = shareLink?.trim();
  if (cleanLink != null && cleanLink.isNotEmpty) return cleanLink;
  return Uri.https('app.myshop.com.gh', '/ref/$code').toString();
}

class _ActionBtn extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isPrimary;
  final VoidCallback? onTap;
  final double w, h;

  const _ActionBtn({
    required this.icon,
    required this.label,
    this.isPrimary = false,
    required this.onTap,
    required this.w,
    required this.h,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: h * 0.056,
      child: isPrimary
          ? ElevatedButton.icon(
              onPressed: onTap,
              icon: Icon(icon, size: 18),
              label: Text(label),
              style: ElevatedButton.styleFrom(
                backgroundColor: MyShopColors.primaryGold,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
                elevation: 0,
              ),
            )
          : OutlinedButton.icon(
              onPressed: onTap,
              icon: Icon(icon, size: 18),
              label: Text(label),
              style: OutlinedButton.styleFrom(
                foregroundColor: MyShopColors.textPrimary,
                side: const BorderSide(color: MyShopColors.divider),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
            ),
    );
  }
}

// ── Stats row ──────────────────────────────────────────────────────────────────

class _StatsRow extends StatelessWidget {
  final ReferralData data;
  final double w, h;
  const _StatsRow({required this.data, required this.w, required this.h});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _StatCard(
              label: 'Total Referrals',
              value: '${data.totalReferrals}',
              icon: Icons.people_alt_rounded,
              w: w,
              h: h),
        ),
        SizedBox(width: w * 0.030),
        Expanded(
          child: _StatCard(
              label: 'Rewards Earned',
              value: 'GHS ${data.earnedGhs.toStringAsFixed(2)}',
              icon: Icons.local_offer_rounded,
              w: w,
              h: h),
        ),
      ],
    );
  }
}

class _StatCard extends StatelessWidget {
  final String label, value;
  final IconData icon;
  final double w, h;

  const _StatCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.w,
    required this.h,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(w * 0.04),
      decoration: BoxDecoration(
        color: MyShopColors.surfaceWhite,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: MyShopColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: MyShopColors.primaryGold, size: w * 0.052),
          SizedBox(height: h * 0.010),
          Text(value,
              style: TextStyle(
                color: MyShopColors.textPrimary,
                fontSize: w * 0.048,
                fontWeight: FontWeight.w800,
              )),
          const SizedBox(height: 3),
          Text(label,
              style: TextStyle(
                  color: MyShopColors.textSecondary, fontSize: w * 0.030)),
        ],
      ),
    );
  }
}

// ── How it works ───────────────────────────────────────────────────────────────

class _HowItWorks extends StatelessWidget {
  final double w, h;
  const _HowItWorks({required this.w, required this.h});

  static const _steps = [
    (
      icon: Icons.share_rounded,
      title: 'Share your code',
      desc: 'Send your unique code to friends and family.',
    ),
    (
      icon: Icons.person_add_alt_1_rounded,
      title: 'They sign up',
      desc: 'Your friend creates an account and enters your code.',
    ),
    (
      icon: Icons.local_offer_rounded,
      title: 'Both of you earn',
      desc:
          'They get GHS 0.50 off their first booking. You earn GHS 0.50 points.',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(w * 0.04),
      decoration: BoxDecoration(
        color: MyShopColors.surfaceWhite,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: MyShopColors.divider),
      ),
      child: Column(
        children: _steps.asMap().entries.map((kv) {
          final s = kv.value;
          final isLast = kv.key == _steps.length - 1;
          return Column(
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: EdgeInsets.all(w * 0.028),
                    decoration: BoxDecoration(
                      color: MyShopColors.primaryGoldLight,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(s.icon,
                        color: MyShopColors.primaryGold, size: w * 0.048),
                  ),
                  SizedBox(width: w * 0.030),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(s.title,
                            style: TextStyle(
                              color: MyShopColors.textPrimary,
                              fontSize: w * 0.036,
                              fontWeight: FontWeight.w700,
                            )),
                        const SizedBox(height: 4),
                        Text(s.desc,
                            style: TextStyle(
                                color: MyShopColors.textSecondary,
                                fontSize: w * 0.032,
                                height: 1.4)),
                      ],
                    ),
                  ),
                ],
              ),
              if (!isLast) ...[
                SizedBox(height: h * 0.016),
                const Divider(height: 1, color: MyShopColors.divider),
                SizedBox(height: h * 0.016),
              ],
            ],
          );
        }).toList(),
      ),
    );
  }
}

// ── Shared helpers ─────────────────────────────────────────────────────────────

class _SectionTitle extends StatelessWidget {
  final String text;
  final double w;
  const _SectionTitle({required this.text, required this.w});

  @override
  Widget build(BuildContext context) {
    return Text(text,
        style: TextStyle(
          color: MyShopColors.textPrimary,
          fontSize: w * 0.040,
          fontWeight: FontWeight.w700,
        ));
  }
}

// ── Referral history ───────────────────────────────────────────────────────────

class _ReferralList extends StatelessWidget {
  final List<ReferralEntry> entries;
  final double w, h;
  const _ReferralList(
      {required this.entries, required this.w, required this.h});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: MyShopColors.surfaceWhite,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: MyShopColors.divider),
      ),
      child: Column(
        children: entries.asMap().entries.map((kv) {
          final item = kv.value;
          final isLast = kv.key == entries.length - 1;
          final earned = item.status == 'earned';
          return Column(
            children: [
              Padding(
                padding: EdgeInsets.symmetric(
                    horizontal: w * 0.04, vertical: h * 0.016),
                child: Row(
                  children: [
                    Container(
                      width: w * 0.10,
                      height: w * 0.10,
                      decoration: const BoxDecoration(
                        color: MyShopColors.surfaceGrey,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(Icons.person_rounded,
                          color: MyShopColors.textSecondary, size: w * 0.050),
                    ),
                    SizedBox(width: w * 0.030),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(item.name,
                              style: TextStyle(
                                color: MyShopColors.textPrimary,
                                fontSize: w * 0.036,
                                fontWeight: FontWeight.w600,
                              )),
                          const SizedBox(height: 2),
                          Text(item.dateLabel,
                              style: TextStyle(
                                  color: MyShopColors.textSecondary,
                                  fontSize: w * 0.030)),
                        ],
                      ),
                    ),
                    Container(
                      padding: EdgeInsets.symmetric(
                          horizontal: w * 0.024, vertical: 5),
                      decoration: BoxDecoration(
                        color: earned
                            ? MyShopColors.successLight
                            : MyShopColors.warningLight,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        earned
                            ? '+GHS ${(item.bonusPesewas / 100).toStringAsFixed(2)}'
                            : 'Pending',
                        style: TextStyle(
                          color: earned
                              ? MyShopColors.success
                              : MyShopColors.warning,
                          fontSize: w * 0.028,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              if (!isLast)
                const Divider(
                    height: 1,
                    indent: 16,
                    endIndent: 16,
                    color: MyShopColors.divider),
            ],
          );
        }).toList(),
      ),
    );
  }
}
