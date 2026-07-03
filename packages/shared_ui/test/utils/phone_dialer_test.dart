import 'package:flutter_test/flutter_test.dart';
import 'package:shared_ui/shared_ui.dart';

void main() {
  group('normalizeDialablePhoneNumber', () {
    test('keeps full Ghana E.164 numbers dialable', () {
      expect(
        normalizeDialablePhoneNumber('+233 54 123 4567'),
        '+233541234567',
      );
    });

    test('keeps full local numbers dialable', () {
      expect(normalizeDialablePhoneNumber('054 123 4567'), '0541234567');
    });

    test('converts international 00 prefix to plus', () {
      expect(
        normalizeDialablePhoneNumber('00233 54 123 4567'),
        '+233541234567',
      );
    });

    test('rejects masked numbers instead of producing partial dial strings',
        () {
      expect(normalizeDialablePhoneNumber('+233 ••• ••• 67'), isEmpty);
      expect(normalizeDialablePhoneNumber('+233****4567'), isEmpty);
      expect(isDialablePhoneNumber('+233 ••• ••• 67'), isFalse);
    });

    test('rejects numbers that are too short for booking contact calls', () {
      expect(normalizeDialablePhoneNumber('+23367'), isEmpty);
    });
  });
}
