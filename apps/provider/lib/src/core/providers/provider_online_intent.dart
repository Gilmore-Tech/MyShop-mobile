import 'package:api_client/api_client.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum ProviderOnlineIntentRole { driver, artisan }

class ProviderOnlineIntentIdentity {
  const ProviderOnlineIntentIdentity({
    required this.role,
    required this.roleAccountId,
  });

  factory ProviderOnlineIntentIdentity.fromUser(AuthUser user) {
    switch (user.role) {
      case AuthRole.driver:
        final roleAccountId = user.driverProfile?.id;
        if (roleAccountId == null || roleAccountId.isEmpty) {
          throw StateError('The active Driver role account is unavailable.');
        }
        return ProviderOnlineIntentIdentity(
          role: ProviderOnlineIntentRole.driver,
          roleAccountId: roleAccountId,
        );
      case AuthRole.artisan:
        final roleAccountId = user.artisanProfile?.id;
        if (roleAccountId == null || roleAccountId.isEmpty) {
          throw StateError('The active Artisan role account is unavailable.');
        }
        return ProviderOnlineIntentIdentity(
          role: ProviderOnlineIntentRole.artisan,
          roleAccountId: roleAccountId,
        );
      case AuthRole.client:
        throw StateError('A Client account cannot own provider Online intent.');
    }
  }

  factory ProviderOnlineIntentIdentity.fromSession(
    AuthUser user,
    AuthSessionIdentity session,
  ) {
    final identity = ProviderOnlineIntentIdentity.fromUser(user);
    if (session.role != identity.role.name ||
        session.roleAccountId != identity.roleAccountId ||
        user.id != identity.roleAccountId) {
      throw const StaleAuthSessionException();
    }
    return identity;
  }

  final ProviderOnlineIntentRole role;
  final String roleAccountId;
}

abstract interface class ProviderOnlineIntentStore {
  Future<bool> read(ProviderOnlineIntentIdentity identity);

  Future<void> write(
    ProviderOnlineIntentIdentity identity, {
    required bool shouldBeOnline,
  });
}

class SharedPreferencesProviderOnlineIntentStore
    implements ProviderOnlineIntentStore {
  static const _prefix = 'myshop_provider_online_intent_v1';

  String _key(ProviderOnlineIntentIdentity identity) =>
      '$_prefix:${identity.role.name}:${identity.roleAccountId}';

  @override
  Future<bool> read(ProviderOnlineIntentIdentity identity) async {
    final preferences = await SharedPreferences.getInstance();
    return preferences.getBool(_key(identity)) ?? false;
  }

  @override
  Future<void> write(
    ProviderOnlineIntentIdentity identity, {
    required bool shouldBeOnline,
  }) async {
    final preferences = await SharedPreferences.getInstance();
    final key = _key(identity);
    if (shouldBeOnline) {
      await preferences.setBool(key, true);
    } else {
      await preferences.remove(key);
    }
  }
}

final providerOnlineIntentStoreProvider = Provider<ProviderOnlineIntentStore>(
  (_) => SharedPreferencesProviderOnlineIntentStore(),
);

/// Exact authenticated role account for Online-intent reads/writes. The auth
/// reconciliation bridge owns this state so location/ride recovery never
/// lazily constructs authentication bootstrap as a side effect.
final currentProviderOnlineIntentIdentityProvider =
    StateProvider<ProviderOnlineIntentIdentity?>((_) => null);

/// Actionable, non-sensitive reason explaining why a prior Online intent was
/// not restored after process relaunch. Both provider home surfaces render it.
final availabilityRestoreNoticeProvider = StateProvider<String?>((_) => null);
