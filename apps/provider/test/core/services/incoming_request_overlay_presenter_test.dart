import 'package:flutter_test/flutter_test.dart';
import 'package:myshop_provider/src/core/services/incoming_request_overlay_presenter.dart';

void main() {
  group('safeIncomingRequestPreviewUrl', () {
    test('accepts an opaque HTTPS preview URL', () {
      expect(
        safeIncomingRequestPreviewUrl(
          'https://api.example.com/v1/notifications/offers/map/token-1',
        ),
        'https://api.example.com/v1/notifications/offers/map/token-1',
      );
    });

    test('rejects cleartext, credentialed, and malformed URLs', () {
      expect(
        safeIncomingRequestPreviewUrl('http://api.example.com/map/token'),
        isNull,
      );
      expect(
        safeIncomingRequestPreviewUrl(
          'https://user:password@api.example.com/map/token',
        ),
        isNull,
      );
      expect(safeIncomingRequestPreviewUrl('not a URL'), isNull);
      expect(safeIncomingRequestPreviewUrl(''), isNull);
    });
  });
}
