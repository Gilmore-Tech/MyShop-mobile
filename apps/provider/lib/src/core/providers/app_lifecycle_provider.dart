import 'package:flutter_riverpod/flutter_riverpod.dart';

/// True while the app is in the foreground (resumed). Driven by
/// [_ProviderAppState.didChangeAppLifecycleState] in `provider_app.dart`.
///
/// Watch this from any periodic background-unsafe operation (REST polls,
/// timers that fire network calls) so we don't burn CPU + battery on
/// requests that Doze mode is going to fail anyway. FCM is the
/// reachability channel for the backgrounded state — see
/// `core/services/fcm_service.dart`.
final appForegroundedProvider = StateProvider<bool>((_) => true);
