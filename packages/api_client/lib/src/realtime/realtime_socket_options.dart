import 'package:socket_io_client/socket_io_client.dart' as io;

/// Shared Socket.IO transport policy for MyShop realtime namespaces.
///
/// Reconnects continue for the lifetime of the owning service, with
/// exponential backoff and jitter. This avoids synchronized reconnect storms
/// during a deploy or network outage while still recovering long-lived
/// provider, chat, and call sessions without requiring an app restart.
Map<String, dynamic> buildRealtimeSocketOptions({
  required String token,
  Map<String, dynamic> auth = const <String, dynamic>{},
}) {
  return io.OptionBuilder()
      .setTransports(['websocket'])
      .setExtraHeaders({'Authorization': 'Bearer $token'})
      .setAuth({'token': token, ...auth})
      // Each namespace has independent lifecycle and auth recovery. Do not let
      // socket_io_client reuse a Manager whose token or reconnect state belongs
      // to another namespace.
      .enableForceNew()
      .enableAutoConnect()
      .enableReconnection()
      // socket_io_client doubles the delay after each failed attempt. Jitter
      // prevents hundreds of devices reconnecting on the same millisecond.
      .setReconnectionDelay(1000)
      .setReconnectionDelayMax(30000)
      .setRandomizationFactor(0.5)
      .setTimeout(15000)
      // Deliberately omit reconnectionAttempts: the library default is
      // Infinity. A temporary outage must not leave a provider permanently
      // unreachable until they restart the app.
      .build();
}
