import 'package:api_client/api_client.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../di/providers.dart';

/// Singleton [ChatRealtime] for the provider app.
///
/// Lifecycle is lazy — the instance is constructed on first read but the
/// underlying `/chat` Socket.IO connection is only opened when the Phase 3
/// orchestrator (or a chat surface itself) calls [ChatRealtime.connect].
/// Disposed automatically when the [ProviderScope] tears down.
///
/// Refresh + force-logout are handled by the shared [TokenRefresher] (set
/// in [dioClientProvider]) — same path as REST + main WS, so all three
/// realtime layers coalesce onto one `/auth/refresh` and one storage
/// write per token-expiry cycle.
final chatRealtimeProvider = Provider<ChatRealtime>((ref) {
  final realtime = ChatRealtime(
    config: ref.watch(apiConfigProvider),
    tokenStorage: ref.watch(appTokenStorageProvider),
    tokenRefresher: ref.watch(tokenRefresherProvider),
  );
  ref.onDispose(realtime.dispose);
  return realtime;
});
