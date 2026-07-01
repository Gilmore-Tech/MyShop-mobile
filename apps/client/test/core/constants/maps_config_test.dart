import 'package:flutter_test/flutter_test.dart';
import 'package:myshop_client/src/core/constants/maps_config.dart';

void main() {
  test('normalizes a Cloud Console SHA-1 for X-Android-Cert', () {
    expect(
      MapsConfig.normalizeAndroidCertSha1(
        'aa:bb:cc:dd:ee:ff:00:11:22:33:44:55:66:77:88:99:aa:bb:cc:dd',
      ),
      'AABBCCDDEEFF00112233445566778899AABBCCDD',
    );
  });
}
