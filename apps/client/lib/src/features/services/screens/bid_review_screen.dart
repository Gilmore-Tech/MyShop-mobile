import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../providers/bid_detail_provider.dart';
import '../../../app/router.dart';

// ── Design tokens ──────────────────────────────────────────────────────────────
const _bg            = Color(0xFFF6F7F8);
const _surfaceWhite  = Color(0xFFFFFFFF);
const _textPrimary   = Color(0xFF161A1D);
const _textSecondary = Color(0xFF555E68);
const _gold          = Color(0xFFF5A623);
const _goldLight     = Color(0xFFFFF8EC);
const _success       = Color(0xFF27AE60);
const _successLight  = Color(0xFFE8F8EE);
const _danger        = Color(0xFFEB5757);
const _divider       = Color(0xFFE8EAEC);

// ── Screen ─────────────────────────────────────────────────────────────────────
// PRD § 4.5 — Client reviews a specific artisan bid and decides to accept/decline.
// EDD: PATCH /v1/jobs/:id/select-bid { bidId }

class BidReviewScreen extends ConsumerStatefulWidget {
  final String jobId;
  final String bidId;
  const BidReviewScreen(
      {super.key, required this.jobId, required this.bidId});

  @override
  ConsumerState<BidReviewScreen> createState() => _BidReviewScreenState();
}

class _BidReviewScreenState extends ConsumerState<BidReviewScreen> {
  bool _isAccepting = false;

  Future<void> _accept() async {
    setState(() => _isAccepting = true);
    await ref
        .read(bidDetailActionProvider.notifier)
        .acceptBid(jobId: widget.jobId, bidId: widget.bidId);
    if (!mounted) return;
    setState(() => _isAccepting = false);
    context.go(AppRoutes.jobActivePath(widget.jobId));
  }

  @override
  Widget build(BuildContext context) {
    final size  = MediaQuery.sizeOf(context);
    final w     = size.width;
    final h     = size.height;
    final bot   = MediaQuery.paddingOf(context).bottom;
    final state = ref.watch(bidDetailProvider(widget.bidId));

    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _surfaceWhite,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded,
              color: _textPrimary),
          onPressed: () => context.pop(),
        ),
        title: Text('Review Bid',
            style: TextStyle(
                color:      _textPrimary,
                fontSize:   w * 0.044,
                fontWeight: FontWeight.w700)),
        centerTitle: false,
      ),
      body: state.when(
        loading: () => const Center(
            child: CircularProgressIndicator(color: _gold)),
        error: (_, __) => Center(
            child: Text('Failed to load bid.',
                style: TextStyle(
                    color: _textSecondary, fontSize: w * 0.036))),
        data: (bid) => Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: EdgeInsets.all(w * 0.05),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _ArtisanCard(bid: bid, w: w, h: h),
                    SizedBox(height: h * 0.020),
                    _BidAmountCard(bid: bid, w: w, h: h),
                    if (bid.artisanNote != null &&
                        bid.artisanNote!.isNotEmpty) ...[
                      SizedBox(height: h * 0.020),
                      _MessageCard(
                          message:   bid.artisanNote!,
                          timestamp: bid.noteTimestamp,
                          w: w, h: h),
                    ],
                    SizedBox(height: h * 0.020),
                    _GuaranteeNote(w: w),
                  ],
                ),
              ),
            ),
            _ActionBar(
              onAccept:    _accept,
              onDecline:   () => context.pop(),
              isAccepting: _isAccepting,
              w: w, h: h, bot: bot,
            ),
          ],
        ),
      ),
    );
  }
}

// ── Artisan card ───────────────────────────────────────────────────────────────

class _ArtisanCard extends StatelessWidget {
  final BidDetail bid;
  final double    w, h;
  const _ArtisanCard(
      {required this.bid, required this.w, required this.h});

  @override
  Widget build(BuildContext context) {
    final a = bid.artisan;
    return Container(
      padding: EdgeInsets.all(w * 0.04),
      decoration: BoxDecoration(
        color: _surfaceWhite,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
              color:      Colors.black.withAlpha(8),
              blurRadius: 8,
              offset:     const Offset(0, 2))
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width:  w * 0.14,
                height: w * 0.14,
                decoration: BoxDecoration(
                    color: a.avatarColor, shape: BoxShape.circle),
                child: Icon(Icons.person_rounded,
                    color: Colors.white, size: w * 0.07),
              ),
              SizedBox(width: w * 0.036),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(a.name,
                        style: TextStyle(
                          color:      _textPrimary,
                          fontSize:   w * 0.042,
                          fontWeight: FontWeight.w700,
                        )),
                    const SizedBox(height: 4),
                    Text(a.tradeTitle,
                        style: TextStyle(
                            color:    _textSecondary,
                            fontSize: w * 0.033)),
                    const SizedBox(height: 6),
                    Row(children: [
                      const Icon(Icons.star_rounded,
                          color: _gold, size: 16),
                      const SizedBox(width: 4),
                      Text(a.rating.toStringAsFixed(1),
                          style: TextStyle(
                            color:      _textPrimary,
                            fontSize:   w * 0.033,
                            fontWeight: FontWeight.w600,
                          )),
                      SizedBox(width: w * 0.016),
                      Text('(${a.reviewCount} reviews)',
                          style: TextStyle(
                              color:    _textSecondary,
                              fontSize: w * 0.030)),
                    ]),
                  ],
                ),
              ),
              if (a.isKycVerified)
                Container(
                  padding: EdgeInsets.symmetric(
                      horizontal: w * 0.024, vertical: 4),
                  decoration: BoxDecoration(
                    color:        _successLight,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.verified_rounded,
                          color: _success, size: 14),
                      const SizedBox(width: 4),
                      Text('Verified',
                          style: TextStyle(
                            color:      _success,
                            fontSize:   w * 0.028,
                            fontWeight: FontWeight.w600,
                          )),
                    ],
                  ),
                ),
            ],
          ),
          SizedBox(height: h * 0.016),
          const Divider(height: 1, color: _divider),
          SizedBox(height: h * 0.016),
          Row(
            children: [
              _StatChip(
                  icon:  Icons.work_history_rounded,
                  label: '${a.reviewCount} completed',
                  w:     w),
              SizedBox(width: w * 0.030),
              _StatChip(
                  icon:  Icons.schedule_rounded,
                  label: '~${a.etaMinutes} min away',
                  w:     w),
            ],
          ),
        ],
      ),
    );
  }
}

class _StatChip extends StatelessWidget {
  final IconData icon;
  final String   label;
  final double   w;
  const _StatChip(
      {required this.icon, required this.label, required this.w});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: _textSecondary, size: 14),
        const SizedBox(width: 4),
        Text(label,
            style: TextStyle(
                color: _textSecondary, fontSize: w * 0.030)),
      ],
    );
  }
}

// ── Bid amount card ────────────────────────────────────────────────────────────

class _BidAmountCard extends StatelessWidget {
  final BidDetail bid;
  final double    w, h;
  const _BidAmountCard(
      {required this.bid, required this.w, required this.h});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(w * 0.04),
      decoration: BoxDecoration(
        color:        _goldLight,
        borderRadius: BorderRadius.circular(12),
        border:       Border.all(color: _gold.withAlpha(60)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Bid Amount',
                    style: TextStyle(
                        color:    _textSecondary,
                        fontSize: w * 0.030)),
                const SizedBox(height: 4),
                Text(bid.breakdown.totalDisplay,
                    style: TextStyle(
                      color:      _textPrimary,
                      fontSize:   w * 0.060,
                      fontWeight: FontWeight.w800,
                    )),
                const SizedBox(height: 4),
                Text('Covers labour + estimated materials',
                    style: TextStyle(
                        color:    _textSecondary,
                        fontSize: w * 0.030)),
                const SizedBox(height: 8),
                Row(children: [
                  _InfoPill(
                      label: bid.durationLabel,
                      icon:  Icons.access_time_rounded,
                      w:     w),
                  SizedBox(width: w * 0.020),
                  _InfoPill(
                      label: bid.availabilityLabel,
                      icon:  Icons.event_available_rounded,
                      w:     w),
                ]),
              ],
            ),
          ),
          Container(
            padding: EdgeInsets.all(w * 0.032),
            decoration: BoxDecoration(
                color: _gold.withAlpha(30), shape: BoxShape.circle),
            child: Icon(Icons.receipt_long_rounded,
                color: _gold, size: w * 0.06),
          ),
        ],
      ),
    );
  }
}

class _InfoPill extends StatelessWidget {
  final String   label;
  final IconData icon;
  final double   w;
  const _InfoPill(
      {required this.label, required this.icon, required this.w});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: _textSecondary, size: 13),
        const SizedBox(width: 4),
        Text(label,
            style: TextStyle(
                color:    _textSecondary,
                fontSize: w * 0.030)),
      ],
    );
  }
}

// ── Message card ───────────────────────────────────────────────────────────────

class _MessageCard extends StatelessWidget {
  final String  message;
  final String? timestamp;
  final double  w, h;
  const _MessageCard(
      {required this.message,
      required this.timestamp,
      required this.w,
      required this.h});

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
          Row(
            children: [
              Text('Message from artisan',
                  style: TextStyle(
                    color:      _textSecondary,
                    fontSize:   w * 0.030,
                    fontWeight: FontWeight.w600,
                  )),
              if (timestamp != null) ...[
                const Spacer(),
                Text(timestamp!,
                    style: TextStyle(
                        color:    _textSecondary,
                        fontSize: w * 0.028)),
              ],
            ],
          ),
          SizedBox(height: h * 0.010),
          Text(message,
              style: TextStyle(
                  color:    _textPrimary,
                  fontSize: w * 0.034,
                  height:   1.6)),
        ],
      ),
    );
  }
}

class _GuaranteeNote extends StatelessWidget {
  final double w;
  const _GuaranteeNote({required this.w});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Icon(Icons.security_rounded, color: _success, size: 16),
        SizedBox(width: w * 0.020),
        Expanded(
          child: Text(
            'Payment is held in escrow and only released after you confirm the job is complete.',
            style: TextStyle(
                color:    _textSecondary,
                fontSize: w * 0.030,
                height:   1.5),
          ),
        ),
      ],
    );
  }
}

// ── Action bar ─────────────────────────────────────────────────────────────────

class _ActionBar extends StatelessWidget {
  final VoidCallback onAccept;
  final VoidCallback onDecline;
  final bool         isAccepting;
  final double       w, h, bot;

  const _ActionBar({
    required this.onAccept,
    required this.onDecline,
    required this.isAccepting,
    required this.w,
    required this.h,
    required this.bot,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color:   _surfaceWhite,
      padding: EdgeInsets.fromLTRB(
          w * 0.05, h * 0.016, w * 0.05, bot + h * 0.020),
      child: Row(
        children: [
          SizedBox(
            height: h * 0.062,
            child: OutlinedButton(
              onPressed: onDecline,
              style: OutlinedButton.styleFrom(
                foregroundColor: _danger,
                side:  const BorderSide(color: _danger),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
                padding: EdgeInsets.symmetric(horizontal: w * 0.06),
              ),
              child: Text('Decline',
                  style: TextStyle(
                      fontSize:   w * 0.038,
                      fontWeight: FontWeight.w600)),
            ),
          ),
          SizedBox(width: w * 0.030),
          Expanded(
            child: SizedBox(
              height: h * 0.062,
              child: ElevatedButton(
                onPressed: isAccepting ? null : onAccept,
                style: ElevatedButton.styleFrom(
                  backgroundColor:        _gold,
                  foregroundColor:        Colors.white,
                  disabledBackgroundColor: _gold.withAlpha(120),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                  elevation: 0,
                ),
                child: isAccepting
                    ? const SizedBox(
                        width: 20, height: 20,
                        child: CircularProgressIndicator(
                            color: Colors.white, strokeWidth: 2.5))
                    : Text('Accept Bid',
                        style: TextStyle(
                          fontSize:   w * 0.040,
                          fontWeight: FontWeight.w700,
                        )),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
