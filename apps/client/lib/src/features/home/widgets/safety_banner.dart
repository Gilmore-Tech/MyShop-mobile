import 'package:flutter/material.dart';

// Design tokens
const _gold = Color(0xFFF5A623);
const _textPrimary = Color(0xFF161A1D);
const _textSecondary = Color(0xFF555E68);

class SafetyBanner extends StatelessWidget {
  const SafetyBanner({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Gold left accent bar
            Container(width: 4, color: _gold),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 14,
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.verified_user_rounded,
                      color: _gold,
                      size: 28,
                    ),
                    const SizedBox(width: 12),
                    const Expanded(child: _BannerText()),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BannerText extends StatelessWidget {
  const _BannerText();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text(
          'Verified Safety Guaranteed',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: _textPrimary,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          'All providers pass Ghana Police & KYC background checks.',
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w400,
            color: _textSecondary,
          ),
        ),
      ],
    );
  }
}
