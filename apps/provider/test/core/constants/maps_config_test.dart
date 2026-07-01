import 'package:flutter_test/flutter_test.dart';
import 'package:myshop_provider/src/core/constants/maps_config.dart';

void main() {
  test('normalizes a Cloud Console SHA-1 for X-Android-Cert', () {
    expect(
      MapsConfig.normalizeAndroidCertSha1(
        '01:e7:6b:07:01:8c:28:8e:75:c3:84:5a:04:34:a4:d9:a7:42:72:6d',
      ),
      '01E76B07018C288E75C3845A0434A4D9A742726D',
    );
  });
}
