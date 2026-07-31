import 'package:api_client/api_client.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Mutable container that lets [dioProvider] notify the auth controller of a
/// force-logout event without creating a Dart-level import cycle (auth
/// controller already imports `providers.dart`, so providers.dart can't
/// import the auth controller back).
///
/// The auth controller registers its handler at construction; the Dio
/// interceptor invokes [call] when the backend says the session is dead.
class ForceLogoutHandler {
  void Function(AuthForceLogoutEvent event)? _handler;

  void register(void Function(AuthForceLogoutEvent event) handler) {
    _handler = handler;
  }

  void call(AuthForceLogoutEvent event) {
    _handler?.call(event);
  }
}

final forceLogoutHandlerProvider = Provider<ForceLogoutHandler>(
  (_) => ForceLogoutHandler(),
);
