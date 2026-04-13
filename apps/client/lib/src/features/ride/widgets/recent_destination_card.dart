import 'package:flutter/material.dart';
import '../providers/ride_provider.dart';

// Design tokens
const _gold = Color(0xFFF5A623);
const _textPrimary = Color(0xFF161A1D);
const _textSecondary = Color(0xFF555E68);
const _surfaceGrey = Color(0xFFF3F5F6);

class RecentDestinationCard extends StatelessWidget {
  final RecentDestination destination;
  final VoidCallback? onTap;

  const RecentDestinationCard({
    super.key,
    required this.destination,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0xFFE0E0E0)),
        ),
        child: Row(
          children: [
            _DestinationIcon(isHome: destination.isHome),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    destination.label,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: _textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    destination.address,
                    style: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w400,
                      color: _textSecondary,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DestinationIcon extends StatelessWidget {
  final bool isHome;
  const _DestinationIcon({required this.isHome});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color: _surfaceGrey,
        shape: BoxShape.circle,
      ),
      child: Icon(
        isHome ? Icons.home_rounded : Icons.business_rounded,
        size: 18,
        color: const Color(0xFF46535D),
      ),
    );
  }
}
