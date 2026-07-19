import 'package:flutter/material.dart';

import '../providers/provider_location_notice_provider.dart';

class ProviderLocationNoticeBanner extends StatelessWidget {
  const ProviderLocationNoticeBanner({
    required this.notice,
    super.key,
  });

  final ProviderLocationNotice notice;

  @override
  Widget build(BuildContext context) {
    final message = notice.escalated
        ? 'Your provider’s live location is still unavailable. Your booking '
            'is active and MyShop support has been alerted.'
        : 'Your provider’s live location is temporarily unavailable. Your '
            'booking is still continuing while they reconnect.';

    return SafeArea(
      minimum: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      child: Material(
        color: const Color(0xFF92400E),
        elevation: 8,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.location_off, color: Colors.white, size: 22),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  message,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                    height: 1.25,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
