import 'package:flutter/material.dart';
import '../providers/home_provider.dart';

// Design tokens
const _gold = Color(0xFFF5A623);

class SpecialOfferCard extends StatelessWidget {
  final SpecialOffer offer;
  final VoidCallback? onTap;

  const SpecialOfferCard({super.key, required this.offer, this.onTap});

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        width:           w * 0.560,   // ~218dp on 390px screen
        decoration: BoxDecoration(
          color:        offer.backgroundColor,
          borderRadius: BorderRadius.circular(w * 0.031),
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          children: [
            _BackgroundDecoration(),
            Padding(
              padding: EdgeInsets.all(w * 0.041),
              child: _CardContent(offer: offer),
            ),
          ],
        ),
      ),
    );
  }
}

class _BackgroundDecoration extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;

    return Positioned(
      right: -(w * 0.051),
      top:   -(w * 0.051),
      child: Container(
        width:  w * 0.256,
        height: w * 0.256,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.white.withValues(alpha: 0.04),
        ),
      ),
    );
  }
}

class _CardContent extends StatelessWidget {
  final SpecialOffer offer;
  const _CardContent({required this.offer});

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final w = size.width;
    final h = size.height;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            _TagChip(label: offer.tag),
            const Spacer(),
            _SaleBadge(),
          ],
        ),
        SizedBox(height: h * 0.015),
        Text(
          offer.title,
          style: TextStyle(
            fontSize:   w * 0.041,
            fontWeight: FontWeight.w700,
            color:      Colors.white,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        SizedBox(height: h * 0.005),
        Text(
          offer.subtitle,
          style: TextStyle(
            fontSize:   w * 0.031,
            fontWeight: FontWeight.w400,
            color:      Colors.white.withValues(alpha: 0.8),
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }
}

class _TagChip extends StatelessWidget {
  final String label;
  const _TagChip({required this.label});

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: w * 0.021,
        vertical:   w * 0.008,
      ),
      decoration: BoxDecoration(
        color:        _gold,
        borderRadius: BorderRadius.circular(w * 0.010),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize:      w * 0.023,
          fontWeight:    FontWeight.w900,
          color:         Colors.white,
          letterSpacing: 0.8,
        ),
      ),
    );
  }
}

class _SaleBadge extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: w * 0.021,
        vertical:   w * 0.008,
      ),
      decoration: BoxDecoration(
        color:        Colors.white.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(w * 0.010),
        border: Border.all(color: Colors.white.withValues(alpha: 0.3)),
      ),
      child: Text(
        'SALE',
        style: TextStyle(
          fontSize:      w * 0.023,
          fontWeight:    FontWeight.w900,
          color:         Colors.white,
          letterSpacing: 0.8,
        ),
      ),
    );
  }
}

// ── Skeleton loader ────────────────────────────────────────────────────────────

class SpecialOfferCardSkeleton extends StatelessWidget {
  const SpecialOfferCardSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final w = size.width;
    final h = size.height;

    return Container(
      width:  w * 0.560,
      height: h * 0.175,
      decoration: BoxDecoration(
        color:        const Color(0xFFE0E0E0),
        borderRadius: BorderRadius.circular(w * 0.031),
      ),
    );
  }
}
