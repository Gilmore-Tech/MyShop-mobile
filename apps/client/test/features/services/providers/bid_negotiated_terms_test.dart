import 'package:flutter_test/flutter_test.dart';
import 'package:myshop_client/src/features/services/providers/bid_list_provider.dart';

void main() {
  ArtisanBid bid({
    String negotiationStatus = 'none',
    int? negotiationAmountPesewas,
    int? negotiationDurationMinutes,
  }) {
    return ArtisanBid(
      bidId: 'bid-1',
      artisanId: 'artisan-1',
      artisanName: 'Ama Artisan',
      tradeTitle: 'Electrician',
      rating: 5,
      reviewCount: 3,
      isVerified: true,
      amountPesewas: 10000,
      arrivesInMinutes: 10,
      durationMinutes: 120,
      negotiationStatus: negotiationStatus,
      negotiationAmountPesewas: negotiationAmountPesewas,
      negotiationDurationMinutes: negotiationDurationMinutes,
    );
  }

  test('active counteroffer surfaces use the latest amount and duration', () {
    final current = bid(
      negotiationStatus: 'client_counter_pending',
      negotiationAmountPesewas: 8500,
      negotiationDurationMinutes: 3 * 24 * 60,
    );

    expect(current.currentTermsAmountPesewas, 8500);
    expect(current.currentTermsDurationMinutes, 4320);
    expect(current.amountDisplay, 'GHS 85');
  });

  test('declined counteroffer returns to the valid bid terms', () {
    final current = bid(
      negotiationStatus: 'declined',
      negotiationAmountPesewas: 8500,
      negotiationDurationMinutes: 3 * 24 * 60,
    );

    expect(current.currentTermsAmountPesewas, 10000);
    expect(current.currentTermsDurationMinutes, 120);
  });
}
