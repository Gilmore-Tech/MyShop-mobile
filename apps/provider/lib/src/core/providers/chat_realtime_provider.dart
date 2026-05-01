import 'package:api_client/api_client.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/auth/providers/auth_controller.dart';
import '../di/providers.dart';

/// Singleton [ChatRealtime] for the provider app.
///
/// Lifecycle is lazy — the instance is constructed on first read but the
/// underlying `/chat` Socket.IO connection is only opened when the Phase 3
/// orchestrator (or a chat surface itself) calls [ChatRealtime.connect].
/// Disposed automatically when the [ProviderScope] tears down.
final chatRealtimeProvider = Provider<ChatRealtime>((ref) {
  final realtime = ChatRealtime(
    config: ref.watch(apiConfigProvider),
    tokenStorage: ref.watch(appTokenStorageProvider),
    dio: ref.watch(dioProvider),
    onForceLogout: () {
      ref.read(authControllerProvider.notifier).logout();
    },
  );
  ref.onDispose(realtime.dispose);
  return realtime;
});
