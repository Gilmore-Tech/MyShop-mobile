import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

// ── Design tokens ──────────────────────────────────────────────────────────────
const _bg            = Color(0xFFF6F7F8);
const _surfaceWhite  = Color(0xFFFFFFFF);
const _textPrimary   = Color(0xFF161A1D);
const _textSecondary = Color(0xFF555E68);
const _gold          = Color(0xFFF5A623);
const _goldDark      = Color(0xFFD48E1A);
const _goldLight     = Color(0xFFFFF8EC);
const _success       = Color(0xFF27AE60);
const _successLight  = Color(0xFFE8F8EE);
const _divider       = Color(0xFFE8EAEC);

// ── Screen ─────────────────────────────────────────────────────────────────────
// PRD § 4.9 — Referral programme: share code, earn loyalty points per referral.
// EDD: GET /v1/users/me/referral  → { code, totalReferrals, pendingPesewas, earnedPesewas }

class ReferralScreen extends ConsumerWidget {
  const ReferralScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final size = MediaQuery.sizeOf(context);
    final w    = size.width;
    final h    = size.height;

    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _surfaceWhite,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded,
              color: _textPrimary),
          onPressed: () => context.pop(),
        ),
        title: Text('Refer & Earn',
            style: TextStyle(
                color:      _textPrimary,
                fontSize:   w * 0.044,
                fontWeight: FontWeight.w700)),
        centerTitle: false,
      ),
      body: SingleChildScrollView(
        padding: EdgeInsets.all(w * 0.05),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _HeroBanner(w: w, h: h),
            SizedBox(height: h * 0.024),
            _CodeCard(w: w, h: h),
            SizedBox(height: h * 0.024),
            _StatsRow(w: w, h: h),
            SizedBox(height: h * 0.028),
            _SectionTitle(text: 'How it works', w: w),
            SizedBox(height: h * 0.016),
            _HowItWorks(w: w, h: h),
            SizedBox(height: h * 0.028),
            _SectionTitle(text: 'Recent referrals', w: w),
            SizedBox(height: h * 0.016),
            _ReferralList(w: w, h: h),
          ],
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
      width:   double.infinity,
      padding: EdgeInsets.all(w * 0.05),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end:   Alignment.bottomRight,
          colors: [_gold, _goldDark],
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: EdgeInsets.all(w * 0.032),
            decoration: BoxDecoration(
              color:        Colors.white.withAlpha(30),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(Icons.card_giftcard_rounded,
                color: Colors.white, size: w * 0.068),
          ),
          SizedBox(height: h * 0.016),
          Text('Give GHS 10, Get GHS 10',
              style: TextStyle(
                color:      Colors.white,
                fontSize:   w * 0.048,
                fontWeight: FontWeight.w800,
                height:     1.2,
              )),
          SizedBox(height: h * 0.008),
          Text(
            'Share your code. Your friend gets GHS 10 off their first ride '
            'or job, and you earn GHS 10 in loyalty points.',
            style: TextStyle(
                color:    Colors.white.withAlpha(210),
                fontSize: w * 0.033,
                height:   1.5),
          ),
        ],
      ),
    );
  }
}

// ── Referral code card ─────────────────────────────────────────────────────────

class _CodeCard extends StatelessWidget {
  final double w, h;
  const _CodeCard({required this.w, required this.h});

  @override
  Widget build(BuildContext context) {
    const code = 'AMA-XK7F2';

    return Container(
      padding: EdgeInsets.all(w * 0.04),
      decoration: BoxDecoration(
        color:        _surfaceWhite,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
              color:      Colors.black.withAlpha(8),
              blurRadius: 8,
              offset:     const Offset(0, 2)),
        ],
      ),
      child: Column(
        children: [
          Text('Your referral code',
              style: TextStyle(
                  color:    _textSecondary,
                  fontSize: w * 0.032)),
          SizedBox(height: h * 0.012),
          Container(
            padding: EdgeInsets.symmetric(
                horizontal: w * 0.06, vertical: h * 0.018),
            decoration: BoxDecoration(
              color:        _goldLight,
              borderRadius: BorderRadius.circular(10),
              border:       Border.all(
                  color: _gold.withAlpha(80),
                  width: 1.5,
                  style: BorderStyle.solid),
            ),
            child: Text(code,
                style: TextStyle(
                  color:         _textPrimary,
                  fontSize:      w * 0.056,
                  fontWeight:    FontWeight.w900,
                  letterSpacing: 4,
                )),
          ),
          SizedBox(height: h * 0.016),
          Row(
            children: [
              Expanded(
                child: _ActionBtn(
                  icon:  Icons.copy_rounded,
                  label: 'Copy Code',
                  onTap: () {
                    Clipboard.setData(const ClipboardData(text: code));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                          content: Text('Code copied!')),
                    );
                  },
                  w: w, h: h,
                ),
              ),
              SizedBox(width: w * 0.030),
              Expanded(
                child: _ActionBtn(
                  icon:   Icons.share_rounded,
                  label:  'Share',
                  isPrimary: true,
                  onTap: () {
                    // TODO: share via platform share sheet
                  },
                  w: w, h: h,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ActionBtn extends StatelessWidget {
  final IconData icon;
  final String   label;
  final bool     isPrimary;
  final VoidCallback onTap;
  final double   w, h;

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
              icon:  Icon(icon, size: 18),
              label: Text(label),
              style: ElevatedButton.styleFrom(
                backgroundColor: _gold,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
                elevation: 0,
              ),
            )
          : OutlinedButton.icon(
              onPressed: onTap,
              icon:  Icon(icon, size: 18),
              label: Text(label),
              style: OutlinedButton.styleFrom(
                foregroundColor: _textPrimary,
                side:  const BorderSide(color: _divider),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
            ),
    );
  }
}

// ── Stats row ──────────────────────────────────────────────────────────────────

class _StatsRow extends StatelessWidget {
  final double w, h;
  const _StatsRow({required this.w, required this.h});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _StatCard(
              label: 'Total Referrals',
              value: '7',
              icon:  Icons.people_alt_rounded,
              w:     w, h: h),
        ),
        SizedBox(width: w * 0.030),
        Expanded(
          child: _StatCard(
              label: 'Rewards Earned',
              value: 'GHS 70',
              icon:  Icons.local_offer_rounded,
              w:     w, h: h),
        ),
      ],
    );
  }
}

class _StatCard extends StatelessWidget {
  final String   label, value;
  final IconData icon;
  final double   w, h;

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
        color:        _surfaceWhite,
        borderRadius: BorderRadius.circular(12),
        border:       Border.all(color: _divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: _gold, size: w * 0.052),
          SizedBox(height: h * 0.010),
          Text(value,
              style: TextStyle(
                color:      _textPrimary,
                fontSize:   w * 0.048,
                fontWeight: FontWeight.w800,
              )),
          const SizedBox(height: 3),
          Text(label,
              style: TextStyle(
                  color:    _textSecondary,
                  fontSize: w * 0.030)),
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
      desc: 'They get GHS 10 off their first booking. You earn GHS 10 points.',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(w * 0.04),
      decoration: BoxDecoration(
        color:        _surfaceWhite,
        borderRadius: BorderRadius.circular(12),
        border:       Border.all(color: _divider),
      ),
      child: Column(
        children: _steps.map((s) {
          final isLast = s == _steps.last;
          return Column(
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: EdgeInsets.all(w * 0.028),
                    decoration: BoxDecoration(
                      color:        _goldLight,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(s.icon, color: _gold, size: w * 0.048),
                  ),
                  SizedBox(width: w * 0.030),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(s.title,
                            style: TextStyle(
                              color:      _textPrimary,
                              fontSize:   w * 0.036,
                              fontWeight: FontWeight.w700,
                            )),
                        const SizedBox(height: 4),
                        Text(s.desc,
                            style: TextStyle(
                                color:    _textSecondary,
                                fontSize: w * 0.032,
                                height:   1.4)),
                      ],
                    ),
                  ),
                ],
              ),
              if (!isLast) ...[
                SizedBox(height: h * 0.016),
                const Divider(height: 1, color: _divider),
                SizedBox(height: h * 0.016),
              ],
            ],
          );
        }).toList(),
      ),
    );
  }
}

// ── Referral history ───────────────────────────────────────────────────────────

class _SectionTitle extends StatelessWidget {
  final String text;
  final double w;
  const _SectionTitle({required this.text, required this.w});

  @override
  Widget build(BuildContext context) {
    return Text(text,
        style: TextStyle(
          color:      _textPrimary,
          fontSize:   w * 0.040,
          fontWeight: FontWeight.w700,
        ));
  }
}

class _ReferralList extends StatelessWidget {
  final double w, h;
  const _ReferralList({required this.w, required this.h});

  static const _items = [
    (name: 'Kwesi A.', date: 'Oct 21', status: 'earned'),
    (name: 'Efua M.', date: 'Oct 15', status: 'pending'),
    (name: 'Nana K.', date: 'Oct 3',  status: 'earned'),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color:        _surfaceWhite,
        borderRadius: BorderRadius.circular(12),
        border:       Border.all(color: _divider),
      ),
      child: Column(
        children: _items.map((item) {
          final earned = item.status == 'earned';
          return Column(
            children: [
              Padding(
                padding: EdgeInsets.symmetric(
                    horizontal: w * 0.04, vertical: h * 0.016),
                child: Row(
                  children: [
                    Container(
                      width:  w * 0.10,
                      height: w * 0.10,
                      decoration: const BoxDecoration(
                        color:  Color(0xFFF3F5F6),
                        shape:  BoxShape.circle,
                      ),
                      child: Icon(Icons.person_rounded,
                          color: _textSecondary, size: w * 0.050),
                    ),
                    SizedBox(width: w * 0.030),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(item.name,
                              style: TextStyle(
                                color:      _textPrimary,
                                fontSize:   w * 0.036,
                                fontWeight: FontWeight.w600,
                              )),
                          const SizedBox(height: 2),
                          Text(item.date,
                              style: TextStyle(
                                  color:    _textSecondary,
                                  fontSize: w * 0.030)),
                        ],
                      ),
                    ),
                    Container(
                      padding: EdgeInsets.symmetric(
                          horizontal: w * 0.024, vertical: 5),
                      decoration: BoxDecoration(
                        color:        earned ? _successLight : const Color(0xFFFEF3E8),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        earned ? '+GHS 10' : 'Pending',
                        style: TextStyle(
                          color:      earned ? _success : const Color(0xFFF2994A),
                          fontSize:   w * 0.028,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              if (item != _items.last)
                const Divider(height: 1, indent: 16, endIndent: 16,
                    color: _divider),
            ],
          );
        }).toList(),
      ),
    );
  }
}
