import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myshop_provider/src/core/services/ios_always_location_permission_bridge.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel(
    'com.gilmoretech.myshopprovider/location_authorization_test',
  );

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('invokes the native Always request on iOS and reports a grant',
      () async {
    MethodCall? receivedCall;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      receivedCall = call;
      return 'always';
    });
    final bridge = IosAlwaysLocationPermissionBridge(
      channel: channel,
      isIos: () => true,
    );

    final result = await bridge.requestAlwaysAuthorization();

    expect(receivedCall?.method, 'requestAlwaysAuthorization');
    expect(receivedCall?.arguments, isNull);
    expect(result, IosAlwaysAuthorizationRequestResult.granted);
  });

  test('reports notGranted when iOS keeps While In Use access', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) async => 'whileInUse');
    final bridge = IosAlwaysLocationPermissionBridge(
      channel: channel,
      isIos: () => true,
    );

    final result = await bridge.requestAlwaysAuthorization();

    expect(result, IosAlwaysAuthorizationRequestResult.notGranted);
  });

  test('does not invoke the iOS channel on another platform', () async {
    var invoked = false;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) async {
      invoked = true;
      return 'always';
    });
    final bridge = IosAlwaysLocationPermissionBridge(
      channel: channel,
      isIos: () => false,
    );

    final result = await bridge.requestAlwaysAuthorization();

    expect(invoked, isFalse);
    expect(result, IosAlwaysAuthorizationRequestResult.unsupported);
  });

  test('fails closed when the native bridge reports an error', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) async {
      throw PlatformException(code: 'NOT_FOREGROUND');
    });
    final bridge = IosAlwaysLocationPermissionBridge(
      channel: channel,
      isIos: () => true,
    );

    final result = await bridge.requestAlwaysAuthorization();

    expect(result, IosAlwaysAuthorizationRequestResult.failed);
  });
}
