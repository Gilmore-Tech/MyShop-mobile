import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/auth/providers/current_user_provider.dart';
import '../providers/provider_status_provider.dart';
import '../providers/socket_provider.dart';

/// Compact overlay that surfaces the real-time state of the socket
/// connection, driver status, and the last event received.
///
/// Helps diagnose why incoming ride/job requests aren't appearing:
///   - Green `WS` pill  → socket connected
///   - Red `WS` pill    → not connected (check token / backend)
///   - Driver badge     → online / offline / busy
///   - Last event line  → shows the most recent event payload from the backend
///
/// Visible in debug builds only.
class SocketDebugBanner extends ConsumerWidget {
  const SocketDebugBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!kDebugMode) return const SizedBox.shrink();

    final connected = ref.watch(socketConnectedProvider);
    final status = ref.watch(providerStatusProvider);
    final lastEvent = ref.watch(lastSocketEventProvider);
    final verification = ref.watch(currentUserProvider)?.verificationStatus
        ?? 'unknown';
    final isVerified = verification.toLowerCase() == 'approved';

    return Material(
      color: Colors.transparent,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.72),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                _Pill(
                  label: connected ? 'WS ON' : 'WS OFF',
                  color: connected ? Colors.green : Colors.red,
                ),
                _Pill(
                  label: status.name.toUpperCase(),
                  color: status.isOnline
                      ? Colors.green
                      : status.isBusy
                          ? Colors.orange
                          : Colors.grey,
                ),
                _Pill(
                  label: 'VERIF: ${verification.toUpperCase()}',
                  color: isVerified ? Colors.green : Colors.red,
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              lastEvent ?? 'No events yet',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 10,
                fontFamily: 'monospace',
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 10,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
