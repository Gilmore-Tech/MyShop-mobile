import 'package:api_client/api_client.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Exact Client SID currently allowed to own session-scoped asynchronous work.
///
/// Kept in a neutral core file so auth orchestration and core service wiring
/// can both update/watch it without an import cycle.
final currentClientAuthSessionIdentityProvider =
    StateProvider<AuthSessionIdentity?>((_) => null);
