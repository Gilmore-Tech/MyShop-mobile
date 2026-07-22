import 'package:api_client/src/services/system_telemetry_service.dart';
import 'package:test/test.dart';

void main() {
  group('formatSystemTelemetryAppVersion', () {
    test('adds a bounded source marker for a reviewed full commit', () {
      expect(
        formatSystemTelemetryAppVersion(
          '1.4.1',
          '24',
          sourceCommit: 'ABCDEF0123456789ABCDEF0123456789ABCDEF01',
        ),
        '1.4.1+24@abcdef012345',
      );
    });

    test('omits missing or malformed source markers', () {
      expect(
        formatSystemTelemetryAppVersion('1.4.1', '24'),
        '1.4.1+24',
      );
      expect(
        formatSystemTelemetryAppVersion(
          '1.4.1',
          '24',
          sourceCommit: 'not-a-reviewed-commit',
        ),
        '1.4.1+24',
      );
    });
  });
}
