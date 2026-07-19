import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myshop_provider/src/core/services/fcm_service.dart';

void main() {
  test('authorized and provisional notification access can go online', () {
    expect(
      notificationAuthorizationAllowsOnline(AuthorizationStatus.authorized),
      isTrue,
    );
    expect(
      notificationAuthorizationAllowsOnline(AuthorizationStatus.provisional),
      isTrue,
    );
  });

  test('denied and undetermined notification access cannot go online', () {
    expect(
      notificationAuthorizationAllowsOnline(AuthorizationStatus.denied),
      isFalse,
    );
    expect(
      notificationAuthorizationAllowsOnline(AuthorizationStatus.notDetermined),
      isFalse,
    );
  });
}
