import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:myshop_provider/src/core/providers/provider_online_intent.dart';

void main() {
  const driver = ProviderOnlineIntentIdentity(
    role: ProviderOnlineIntentRole.driver,
    roleAccountId: 'driver-role-1',
  );
  const siblingDriver = ProviderOnlineIntentIdentity(
    role: ProviderOnlineIntentRole.driver,
    roleAccountId: 'driver-role-2',
  );
  const artisan = ProviderOnlineIntentIdentity(
    role: ProviderOnlineIntentRole.artisan,
    roleAccountId: 'artisan-role-1',
  );

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('persists intent only for the exact role account', () async {
    final store = SharedPreferencesProviderOnlineIntentStore();

    await store.write(driver, shouldBeOnline: true);

    expect(await store.read(driver), isTrue);
    expect(await store.read(siblingDriver), isFalse);
    expect(await store.read(artisan), isFalse);
  });

  test('driver and artisan intents with one private identity stay isolated',
      () async {
    final store = SharedPreferencesProviderOnlineIntentStore();

    await store.write(driver, shouldBeOnline: true);
    await store.write(artisan, shouldBeOnline: true);
    await store.write(driver, shouldBeOnline: false);

    expect(await store.read(driver), isFalse);
    expect(await store.read(artisan), isTrue);
  });

  test('cleared intent stays false after a new store instance', () async {
    final first = SharedPreferencesProviderOnlineIntentStore();
    await first.write(driver, shouldBeOnline: true);
    await first.write(driver, shouldBeOnline: false);

    final afterRelaunch = SharedPreferencesProviderOnlineIntentStore();
    expect(await afterRelaunch.read(driver), isFalse);
  });
}
