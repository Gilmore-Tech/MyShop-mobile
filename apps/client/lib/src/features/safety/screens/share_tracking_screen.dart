import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_ui/shared_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

// ── Screen ─────────────────────────────────────────────────────────────────────
// PRD § 4.6 / § 4.10 — Share a live tracking link with trusted contacts.
// Link expires when the ride/job ends.
// EDD: POST /v1/bookings/:id/share-link → { url, expiresAt }

class ShareTrackingScreen extends ConsumerStatefulWidget {
  const ShareTrackingScreen({super.key});

  @override
  ConsumerState<ShareTrackingScreen> createState() =>
      _ShareTrackingScreenState();
}

class _ShareTrackingScreenState extends ConsumerState<ShareTrackingScreen> {
  bool _linkGenerated = false;
  bool _isGenerating = false;

  static const _mockLink = 'https://myshop.com.gh/track/r/abc123xyz';

  Future<void> _generateLink() async {
    setState(() => _isGenerating = true);
    // TODO: POST /v1/bookings/:id/share-link
    await Future.delayed(const Duration(milliseconds: 700));
    if (!mounted) return;
    setState(() {
      _isGenerating = false;
      _linkGenerated = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final w = size.width;
    final h = size.height;
    final bot = MediaQuery.paddingOf(context).bottom;

    return Scaffold(
      backgroundColor: MyShopColors.offWhite,
      appBar: AppBar(
        backgroundColor: MyShopColors.surfaceWhite,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: MyShopColors.textPrimary),
          onPressed: () => context.pop(),
        ),
        title: Text('Share My Location',
            style: TextStyle(
                color: MyShopColors.textPrimary,
                fontSize: w * 0.044,
                fontWeight: FontWeight.w700)),
        centerTitle: false,
      ),
      body: Padding(
        padding: EdgeInsets.fromLTRB(w * 0.05, 0, w * 0.05, bot + h * 0.024),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(height: h * 0.024),
            _InfoCard(w: w, h: h),
            SizedBox(height: h * 0.024),
            if (_linkGenerated) ...[
              _LinkCard(
                link: _mockLink,
                w: w,
                h: h,
                onCopy: () {
                  Clipboard.setData(const ClipboardData(text: _mockLink));
                  MyShopToast.show(context,
                      message: 'Link copied to clipboard');
                },
              ),
              SizedBox(height: h * 0.024),
              _ShareMethods(w: w, h: h),
              SizedBox(height: h * 0.024),
              _ExpiryNote(w: w),
            ] else
              _GeneratePrompt(w: w, h: h),
            const Spacer(),
            if (!_linkGenerated)
              SizedBox(
                width: double.infinity,
                height: h * 0.066,
                child: ElevatedButton(
                  onPressed: _isGenerating ? null : _generateLink,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: MyShopColors.primaryGold,
                    foregroundColor: Colors.white,
                    disabledBackgroundColor:
                        MyShopColors.primaryGold.withAlpha(120),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                    elevation: 0,
                  ),
                  child: _isGenerating
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                              color: Colors.white, strokeWidth: 2.5))
                      : Text('Generate Tracking Link',
                          style: TextStyle(
                              fontSize: w * 0.040,
                              fontWeight: FontWeight.w700)),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ── Info card ──────────────────────────────────────────────────────────────────

class _InfoCard extends StatelessWidget {
  final double w, h;
  const _InfoCard({required this.w, required this.h});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(w * 0.04),
      decoration: BoxDecoration(
        color: MyShopColors.primaryGoldLight,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: MyShopColors.primaryGold.withAlpha(60)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.location_on_rounded,
              color: MyShopColors.primaryGold, size: 22),
          SizedBox(width: w * 0.030),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Share your live location',
                    style: TextStyle(
                      color: MyShopColors.textPrimary,
                      fontSize: w * 0.036,
                      fontWeight: FontWeight.w700,
                    )),
                SizedBox(height: h * 0.006),
                Text(
                  'Generate a link and send it to someone you trust. '
                  'They can follow your journey in real time — no app needed.',
                  style: TextStyle(
                      color: MyShopColors.textSecondary,
                      fontSize: w * 0.031,
                      height: 1.5),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Generate prompt ────────────────────────────────────────────────────────────

class _GeneratePrompt extends StatelessWidget {
  final double w, h;
  const _GeneratePrompt({required this.w, required this.h});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        children: [
          SizedBox(height: h * 0.04),
          Container(
            width: w * 0.22,
            height: w * 0.22,
            decoration: const BoxDecoration(
                color: MyShopColors.surfaceGrey, shape: BoxShape.circle),
            child: Icon(Icons.link_rounded,
                color: MyShopColors.textSecondary.withAlpha(120),
                size: w * 0.10),
          ),
          SizedBox(height: h * 0.016),
          Text('No link generated yet',
              style: TextStyle(
                  color: MyShopColors.textSecondary, fontSize: w * 0.036)),
          SizedBox(height: h * 0.008),
          Text('Tap the button below to create a shareable link.',
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: MyShopColors.textSecondary.withAlpha(160),
                  fontSize: w * 0.030)),
        ],
      ),
    );
  }
}

// ── Link card ──────────────────────────────────────────────────────────────────

class _LinkCard extends StatelessWidget {
  final String link;
  final VoidCallback onCopy;
  final double w, h;

  const _LinkCard({
    required this.link,
    required this.onCopy,
    required this.w,
    required this.h,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(w * 0.04),
      decoration: BoxDecoration(
        color: MyShopColors.successLight,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: MyShopColors.success.withAlpha(60)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.check_circle_rounded,
                  color: MyShopColors.success, size: 18),
              SizedBox(width: w * 0.020),
              Text('Link ready to share',
                  style: TextStyle(
                    color: MyShopColors.success,
                    fontSize: w * 0.034,
                    fontWeight: FontWeight.w700,
                  )),
            ],
          ),
          SizedBox(height: h * 0.012),
          Row(
            children: [
              Expanded(
                child: Container(
                  padding: EdgeInsets.symmetric(
                      horizontal: w * 0.030, vertical: h * 0.012),
                  decoration: BoxDecoration(
                    color: MyShopColors.surfaceWhite,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: MyShopColors.divider),
                  ),
                  child: Text(
                    link,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        color: MyShopColors.textPrimary, fontSize: w * 0.030),
                  ),
                ),
              ),
              SizedBox(width: w * 0.020),
              GestureDetector(
                onTap: onCopy,
                child: Container(
                  padding: EdgeInsets.all(w * 0.028),
                  decoration: BoxDecoration(
                    color: MyShopColors.surfaceWhite,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: MyShopColors.divider),
                  ),
                  child: Icon(Icons.copy_rounded,
                      color: MyShopColors.textSecondary, size: w * 0.048),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Share methods ──────────────────────────────────────────────────────────────

class _ShareMethods extends StatelessWidget {
  final double w, h;
  const _ShareMethods({required this.w, required this.h});

  static const _methods = [
    (icon: Icons.sms_rounded, label: 'SMS', color: MyShopColors.success),
    (icon: Icons.share_rounded, label: 'Share', color: MyShopColors.info),
    (
      icon: Icons.copy_all_rounded,
      label: 'Copy',
      color: MyShopColors.darkSlate
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Row(
      children: _methods.map((m) {
        final isLast = m == _methods.last;
        return Expanded(
          child: Padding(
            padding: EdgeInsets.only(right: isLast ? 0 : w * 0.030),
            child: GestureDetector(
              onTap: () {
                // TODO: invoke platform share
              },
              child: Container(
                padding: EdgeInsets.symmetric(vertical: h * 0.018),
                decoration: BoxDecoration(
                  color: m.color.withAlpha(16),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: m.color.withAlpha(60)),
                ),
                child: Column(
                  children: [
                    Icon(m.icon, color: m.color, size: w * 0.060),
                    SizedBox(height: h * 0.008),
                    Text(m.label,
                        style: TextStyle(
                          color: m.color,
                          fontSize: w * 0.030,
                          fontWeight: FontWeight.w600,
                        )),
                  ],
                ),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}

// ── Expiry note ────────────────────────────────────────────────────────────────

class _ExpiryNote extends StatelessWidget {
  final double w;
  const _ExpiryNote({required this.w});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Icon(Icons.timer_outlined,
            color: MyShopColors.textSecondary, size: 14),
        SizedBox(width: w * 0.016),
        Expanded(
          child: Text(
            'This link expires automatically when your ride or job ends.',
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
