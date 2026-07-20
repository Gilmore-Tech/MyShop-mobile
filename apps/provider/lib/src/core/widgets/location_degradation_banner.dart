import 'package:flutter/material.dart';

import '../providers/location_degradation_provider.dart';

class LocationDegradationBanner extends StatelessWidget {
  const LocationDegradationBanner({
    required this.state,
    super.key,
  });

  final ProviderLocationDegradationState state;

  @override
  Widget build(BuildContext context) {
    if (!state.isDegraded) return const SizedBox.shrink();

    final message = state.isEscalated
        ? 'Location is still unavailable. MyShop support has been alerted. '
            'Your current work can continue, but new requests are paused.'
        : state.hasActiveWork
            ? 'Location unavailable. Finish your current work; new requests '
                'are paused until an accurate location returns.'
            : 'You are Offline because location is unavailable. Restore '
                'accurate location before going Online again.';

    return SafeArea(
      minimum: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      child: Material(
        color: const Color(0xFF9A3412),
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
