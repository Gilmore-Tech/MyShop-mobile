import 'package:api_client/api_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:myshop_client/src/features/auth/data/auth_repository.dart';
import 'package:myshop_client/src/features/auth/providers/auth_controller.dart';
import 'package:myshop_client/src/features/loyalty/data/loyalty_repository.dart';
import 'package:myshop_client/src/features/loyalty/domain/loyalty_models.dart';
import 'package:myshop_client/src/features/loyalty/providers/loyalty_redemption_providers.dart';
import 'package:myshop_client/src/features/loyalty/widgets/redeem_points_sheet.dart';

class _MockLoyaltyRepository extends Mock implements LoyaltyRepository {}

class _MockAuthRepository extends Mock implements ClientAuthRepository {}

const _rate = LoyaltyRate(pointPesewas: 10, maxRedemptionPercent: 50);

ApiException _apiError(String code, {int status = 400}) =>
    ApiException(message: 'x', statusCode: status, errorCode: code);

/// Pumps a host screen with a button that opens the redeem sheet, then taps it.
/// Returns the [ProviderContainer] so tests can assert on provider state.
Future<ProviderContainer> _openSheet(
  WidgetTester tester, {
  required _MockLoyaltyRepository repo,
  int balance = 500,
  int farePesewas = 5000,
  RedeemableBookingType bookingType = RedeemableBookingType.ride,
  String bookingId = 'r1',
}) async {
  when(() => repo.fetchRate()).thenAnswer((_) async => _rate);

  final container = ProviderContainer(
    overrides: [
      loyaltyRepositoryProvider.overrideWithValue(repo),
      loyaltyBalanceProvider.overrideWithValue(balance),
      // Keep the auth controller offline: left in AuthUnknown so the
      // success-path refreshProfile() is a no-op (no network in tests).
      clientAuthControllerProvider
          .overrideWith((ref) => ClientAuthController(_MockAuthRepository())),
    ],
  );
  addTearDown(container.dispose);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: ElevatedButton(
                onPressed: () => showRedeemPointsSheet(
                  context: context,
                  bookingType: bookingType,
                  bookingId: bookingId,
                  farePesewas: farePesewas,
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    ),
  );

  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  return container;
}

void main() {
  setUpAll(() {
    registerFallbackValue(RedeemableBookingType.ride);
  });

  testWidgets('renders balance, max redeemable and live saving preview',
      (tester) async {
    final repo = _MockLoyaltyRepository();
    await _openSheet(tester, repo: repo, balance: 500, farePesewas: 5000);

    // 500 points available, capped to 250 by the 50% fare ceiling.
    expect(find.textContaining('You have 500 points'), findsOneWidget);
    // Seeded to the max (250) → preview 250 × 10 = 2500 pesewas = GHS 25.00.
    expect(find.text("You'll save GHS 25.00"), findsOneWidget);
    expect(find.text('Apply 250 points'), findsOneWidget);
  });

  testWidgets('happy path: redeem applies the discount to the booking',
      (tester) async {
    final repo = _MockLoyaltyRepository();
    when(() => repo.redeem(
          points: any(named: 'points'),
          bookingType: any(named: 'bookingType'),
          bookingId: any(named: 'bookingId'),
        )).thenAnswer((_) async => const LoyaltyRedemption(
          pointsRedeemed: 250,
          discountPesewas: 2500,
          newBalance: 250,
        ));

    final container =
        await _openSheet(tester, repo: repo, balance: 500, farePesewas: 5000);

    await tester.tap(find.text('Apply 250 points'));
    await tester.pumpAndSettle();

    // The applied redemption is recorded for this booking…
    final applied = container.read(appliedRedemptionProvider('r1'));
    expect(applied, isNotNull);
    expect(applied!.pointsRedeemed, 250);
    expect(applied.discountPesewas, 2500);

    // …and the request used the requested points + ride wire type.
    verify(() => repo.redeem(
          points: 250,
          bookingType: RedeemableBookingType.ride,
          bookingId: 'r1',
        )).called(1);
  });

  testWidgets('trusts a capped server response over the requested points',
      (tester) async {
    final repo = _MockLoyaltyRepository();
    // Client asked for 250 but the server only spent 100.
    when(() => repo.redeem(
          points: any(named: 'points'),
          bookingType: any(named: 'bookingType'),
          bookingId: any(named: 'bookingId'),
        )).thenAnswer((_) async => const LoyaltyRedemption(
          pointsRedeemed: 100,
          discountPesewas: 1000,
          newBalance: 400,
        ));

    final container = await _openSheet(tester, repo: repo);
    await tester.tap(find.text('Apply 250 points'));
    await tester.pumpAndSettle();

    final applied = container.read(appliedRedemptionProvider('r1'));
    expect(applied!.pointsRedeemed, 100);
    expect(applied.discountPesewas, 1000);
  });

  group('error codes map to friendly copy and keep the sheet open', () {
    Future<void> expectError(
      WidgetTester tester, {
      required ApiException error,
      required String copy,
      int balance = 500,
    }) async {
      final repo = _MockLoyaltyRepository();
      when(() => repo.redeem(
            points: any(named: 'points'),
            bookingType: any(named: 'bookingType'),
            bookingId: any(named: 'bookingId'),
          )).thenThrow(error);

      final container = await _openSheet(tester, repo: repo, balance: balance);
      await tester.tap(find.text('Apply 250 points'));
      await tester.pumpAndSettle();

      expect(find.text(copy), findsOneWidget);
      // Sheet is still open and nothing was applied to the booking.
      expect(find.text('Apply 250 points'), findsOneWidget);
      expect(container.read(appliedRedemptionProvider('r1')), isNull);
    }

    testWidgets('INSUFFICIENT_LOYALTY_POINTS', (tester) async {
      await expectError(
        tester,
        error: _apiError('INSUFFICIENT_LOYALTY_POINTS'),
        copy: 'You only have 500 points.',
      );
    });

    testWidgets('BOOKING_ALREADY_REDEEMED', (tester) async {
      await expectError(
        tester,
        error: _apiError('BOOKING_ALREADY_REDEEMED'),
        copy: 'Points already applied to this booking.',
      );
    });

    testWidgets('REDEMPTION_AMOUNT_TOO_SMALL', (tester) async {
      await expectError(
        tester,
        error: _apiError('REDEMPTION_AMOUNT_TOO_SMALL'),
        copy: "That's too few points to apply a discount.",
      );
    });

    testWidgets('ACTIVE_RIDE_NOT_FOUND', (tester) async {
      await expectError(
        tester,
        error: _apiError('ACTIVE_RIDE_NOT_FOUND', status: 404),
        copy: 'This booking is no longer active.',
      );
    });

    testWidgets('ACTIVE_JOB_NOT_FOUND', (tester) async {
      await expectError(
        tester,
        error: _apiError('ACTIVE_JOB_NOT_FOUND', status: 404),
        copy: 'This booking is no longer active.',
      );
    });

    testWidgets('CLIENT_PROFILE_REQUIRED', (tester) async {
      await expectError(
        tester,
        error: _apiError('CLIENT_PROFILE_REQUIRED', status: 403),
        copy: 'Complete your client profile to redeem points.',
      );
    });
  });
}
