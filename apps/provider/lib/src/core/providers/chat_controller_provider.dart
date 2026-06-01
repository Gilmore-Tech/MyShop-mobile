import 'package:api_client/api_client.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_models/shared_models.dart' show ChatSenderRole;
import 'package:shared_preferences/shared_preferences.dart';

import '../../features/auth/providers/auth_controller.dart';
import '../../features/profile/providers/provider_type_provider.dart';
import '../chat/shared_prefs_chat_outbox.dart';
import '../di/providers.dart';
import 'chat_realtime_provider.dart';

/// Singleton [ChatController] for the provider app, scoped to the active
/// auth session.
///
/// Async because of the one-time `SharedPreferences.getInstance()` call —
/// the rebuild keeps the same instance for the whole signed-in session
/// and only reconstructs when auth state changes (login → load,
/// logout → null + dispose).
final chatControllerProvider = FutureProvider<ChatController?>((ref) async {
  final auth = ref.watch(authControllerProvider);
  if (auth is! AuthAuthenticated) return null;

  final prefs = await SharedPreferences.getInstance();
  final outbox = SharedPreferencesChatOutbox(prefs);
  final realtime = ref.watch(chatRealtimeProvider);
  final rest = ref.watch(chatServiceProvider);

  // Derive the active provider role at the moment the controller is built.
  // Re-watching `providerTypeProvider` makes Riverpod tear down + rebuild
  // the controller when the human switches between driver and artisan,
  // which is the correct moment to flip the chat identity tuple.
  final providerType = ref.watch(providerTypeProvider);
  final selfRole = providerType.isDriver
      ? ChatSenderRole.driver
      : ChatSenderRole.artisan;

  final controller = ChatController(
    rest: rest,
    realtime: realtime,
    outbox: outbox,
    selfUserId: auth.user.id,
    // Required so a phone running both Provider + Client apps with the
    // same `auth.user.id` can still tell which side a message came from.
    // Without this, every bubble rendered on the right side.
    selfRole: selfRole,
  );
  ref.onDispose(controller.dispose);
  return controller;
});
