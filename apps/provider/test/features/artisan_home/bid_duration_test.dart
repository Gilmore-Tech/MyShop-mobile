import 'package:flutter_test/flutter_test.dart';
import 'package:myshop_provider/src/features/artisan_home/screens/bid_submission_screen.dart';

void main() {
  test('formats artisan bid durations through the 15-day maximum', () {
    expect(formatBidDuration(0), isEmpty);
    expect(formatBidDuration(15), '15m');
    expect(formatBidDuration(90), '1h 30m');
    expect(formatBidDuration(24 * 60), '1d');
    expect(formatBidDuration(15 * 24 * 60), '15d');
  });
}
