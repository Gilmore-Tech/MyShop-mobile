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

  test('converts explicit hour and day selections to API minutes', () {
    expect(
      bidDurationMinutes(quantity: 3, unit: BidDurationUnit.hours),
      180,
    );
    expect(
      bidDurationMinutes(quantity: 15, unit: BidDurationUnit.days),
      21600,
    );
  });

  test('restores an existing duration into the clearest picker unit', () {
    expect(
      bidDurationSelectionFromMinutes(4 * 60),
      (unit: BidDurationUnit.hours, quantity: 4),
    );
    expect(
      bidDurationSelectionFromMinutes(3 * 24 * 60),
      (unit: BidDurationUnit.days, quantity: 3),
    );
    expect(
      bidDurationSelectionFromMinutes(90),
      (unit: BidDurationUnit.hours, quantity: 2),
    );
  });
}
