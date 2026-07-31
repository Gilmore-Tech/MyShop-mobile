import 'package:flutter_test/flutter_test.dart';
import 'package:shared_ui/shared_ui.dart';

void main() {
  test('validates canonical Ghana E.164 phone numbers', () {
    expect(Validators.ghanaE164Phone('+233241234567'), isNull);
    expect(Validators.ghanaE164Phone('+233 30 123 4567'), isNull);
    expect(Validators.ghanaE164Phone('+447911123456'), isNotNull);
    expect(Validators.ghanaE164Phone('+23334123456'), isNotNull);
    expect(Validators.ghanaE164Phone('0241234567'), isNotNull);
  });
}
