import 'package:api_client/api_client.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../features/auth/providers/auth_controller.dart';
import '../chat/shared_prefs_chat_outbox.dart';
import '../di/providers.dart';
import 'chat_realtime_provider.dart';

/// Singleton [ChatController] for the client app, scoped to the active
/// auth session.
///
/// Async because of the one-time `SharedPreferences.getInstance()` call —
/// the rebuild keeps the same instance for the whole signed-in session
/// and only reconstructs when auth state changes (login → load,
/// logout → null + dispose).
final chatControllerProvider =
    FutureProvider<ChatController?>((ref) async {
  final auth = ref.watch(clientAuthControllerProvider);
  if (auth is! AuthAuthenticated) return null;

  final prefs = await SharedPreferences.getInstance();
  final outbox = SharedPreferencesChatOutbox(prefs);
  final realtime = ref.watch(chatRealtimeProvider);
  final rest = ref.watch(chatServiceProvider);

  final controller = ChatController(
    rest: rest,
    realtime: realtime,
    outbox: outbox,
    selfUserId: auth.profile.id,
  );
  ref.onDispose(controller.dispose);
  return controller;
});
