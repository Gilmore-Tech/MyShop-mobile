import 'package:shared_utils/shared_utils.dart';
import 'package:test/test.dart';

void main() {
  group('humanReadableLocationLabel', () {
    test('removes a leading Plus Code and preserves the descriptive address',
        () {
      expect(
        humanReadableLocationLabel('MCFG+RPC, Queens Rd, Kumasi, Ghana'),
        'Queens Rd, Kumasi, Ghana',
      );
    });

    test('does not change an ordinary named address', () {
      expect(
        humanReadableLocationLabel('Maxima, Kumasi, Ghana'),
        'Maxima, Kumasi, Ghana',
      );
    });

    test('uses a clear fallback when no descriptive label exists', () {
      expect(humanReadableLocationLabel('MCFG+RPC'), 'Pinned location');
      expect(humanReadableLocationLabel(''), 'Pinned location');
    });

    test('does not mistake codes embedded in a place name for a prefix', () {
      expect(
        humanReadableLocationLabel('Shop MCFG+RPC Annex, Kumasi'),
        'Shop MCFG+RPC Annex, Kumasi',
      );
    });
  });
}
