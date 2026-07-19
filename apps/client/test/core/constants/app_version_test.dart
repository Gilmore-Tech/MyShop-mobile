import 'package:flutter_test/flutter_test.dart';
import 'package:myshop_client/src/core/constants/app_version.dart';

void main() {
  test('release UI defaults to the approved marketing version', () {
    expect(appMarketingVersion, '1.4.1');
    expect(appVersionLabel, 'Version 1.4.1');
  });
}
