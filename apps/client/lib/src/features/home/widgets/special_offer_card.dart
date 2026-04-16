import 'package:flutter/material.dart';
import 'package:shared_ui/shared_ui.dart';
import '../providers/home_provider.dart';

// Design tokens
const _saleRed    = Color(0xFFE03131); // stamp red for SALE badge + tag
const _tagDeepRed = Color(0xFFB91C1C); // slightly darker for the chip

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
        width: w * 0.70, // ~273dp on 390 screen — wider like the design
        decoration: BoxDecoration(
          color: offer.backgroundColor,
          borderRadius: BorderRadius.circular(6),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.12),
              blurRadius: 10,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          children: [
            // Large stamp-style SALE graphic on the right
            const Positioned(
              right: -8,
              top: 0,
              bottom: 0,
              child: Center(child: _SaleStamp()),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
              child: _CardContent(offer: offer),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Content (tag + title + subtitle) ─────────────────────────────────────────

class _CardContent extends StatelessWidget {
  final SpecialOffer offer;
  const _CardContent({required this.offer});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        _TagChip(label: offer.tag),
        const Spacer(),
        // Title + subtitle sit in the left 60% so the SALE stamp can breathe
        SizedBox(
          width: MediaQuery.sizeOf(context).width * 0.42,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                offer.title,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                  height: 1.15,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 4),
              Text(
                offer.subtitle,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                  color: Colors.white.withValues(alpha: 0.85),
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ── "SPECIAL OFFER" tag chip (red pill, top-left) ────────────────────────────

class _TagChip extends StatelessWidget {
  final String label;
  const _TagChip({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: _tagDeepRed,
        borderRadius: BorderRadius.circular(3),
      ),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 9,
          fontWeight: FontWeight.w900,
          color: Colors.white,
          letterSpacing: 1.0,
        ),
      ),
    );
  }
}

// ── Big stamp-style SALE graphic ─────────────────────────────────────────────

class _SaleStamp extends StatelessWidget {
  const _SaleStamp();

  @override
  Widget build(BuildContext context) {
    return Transform.rotate(
      angle: -0.17, // ~ -10°
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: _saleRed,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: Colors.white.withValues(alpha: 0.9), width: 2),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.2),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: const Text(
          'SALE',
          style: TextStyle(
            fontSize: 32,
            fontWeight: FontWeight.w900,
            color: Colors.white,
            letterSpacing: 2,
            fontStyle: FontStyle.italic,
            height: 1,
          ),
        ),
      ),
    );
  }
}

// ── Skeleton loader ──────────────────────────────────────────────────────────

class SpecialOfferCardSkeleton extends StatelessWidget {
  const SpecialOfferCardSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    return Container(
      width: w * 0.70,
      decoration: BoxDecoration(
        color: MyShopColors.divider,
        borderRadius: BorderRadius.circular(6),
      ),
    );
  }
}
