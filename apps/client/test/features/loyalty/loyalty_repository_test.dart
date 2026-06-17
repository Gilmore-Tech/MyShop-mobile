import 'package:api_client/api_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:myshop_client/src/features/loyalty/data/loyalty_repository.dart';
import 'package:myshop_client/src/features/loyalty/domain/loyalty_models.dart';

class _MockUserService extends Mock implements UserService {}

class _MockLoyaltyService extends Mock implements LoyaltyService {}

class _MockConfigService extends Mock implements PlatformConfigService {}

Map<String, dynamic> _userJson({required int balance}) => {
      'id': 'u1',
      'phone': '+233200000000',
      'fullName': 'Ama Owusu',
      'languagePref': 'en',
      'status': 'active',
      'createdAt': '2026-01-01T00:00:00.000Z',
      'updatedAt': '2026-01-01T00:00:00.000Z',
      'client': {
        'id': 'c1',
        'loyaltyPointsBalance': balance,
      },
    };

void main() {
  late _MockUserService userService;
  late _MockLoyaltyService loyaltyService;
  late _MockConfigService configService;
  late LoyaltyRepository repo;

  setUpAll(() {
    registerFallbackValue(RedeemableBookingType.ride);
  });

  setUp(() {
    userService = _MockUserService();
    loyaltyService = _MockLoyaltyService();
    configService = _MockConfigService();
    repo = LoyaltyRepository(
      userService: userService,
      loyaltyService: loyaltyService,
      configService: configService,
    );
  });

  test('fetchBalance reads client.loyaltyPointsBalance from /users/me',
      () async {
    when(() => userService.getMe())
        .thenAnswer((_) async => _userJson(balance: 320));
    expect(await repo.fetchBalance(), 320);
  });

  test('fetchBalance defaults to 0 when no client profile', () async {
    when(() => userService.getMe()).thenAnswer((_) async => {
          'id': 'u1',
          'phone': '+233200000000',
          'fullName': 'Ama',
          'languagePref': 'en',
          'status': 'active',
          'createdAt': '2026-01-01T00:00:00.000Z',
          'updatedAt': '2026-01-01T00:00:00.000Z',
        });
    expect(await repo.fetchBalance(), 0);
  });

  test('redeem forwards the wire booking type and returns typed result',
      () async {
    when(() => loyaltyService.redeemPoints(
          points: any(named: 'points'),
          bookingType: any(named: 'bookingType'),
          bookingId: any(named: 'bookingId'),
        )).thenAnswer((_) async => {
          'pointsRedeemed': 200,
          'discountPesewas': 2000,
          'newBalance': 120,
        });

    final result = await repo.redeem(
      points: 200,
      bookingType: RedeemableBookingType.job,
      bookingId: 'j1',
    );

    expect(result.pointsRedeemed, 200);
    expect(result.discountPesewas, 2000);
    expect(result.newBalance, 120);
    verify(() => loyaltyService.redeemPoints(
          points: 200,
          bookingType: 'job',
          bookingId: 'j1',
        )).called(1);
  });

  test('fetchTransactions maps the envelope into a typed page', () async {
    when(() => loyaltyService.getTransactions(
          page: any(named: 'page'),
          limit: any(named: 'limit'),
        )).thenAnswer((_) async => {
          'items': [
            {'transactionType': 'earned_ride', 'points': 5, 'balanceAfter': 5},
          ],
          'meta': {'page': 1, 'limit': 20, 'total': 1, 'totalPages': 2},
        });

    final page = await repo.fetchTransactions(page: 1, limit: 20);
    expect(page.items, hasLength(1));
    expect(page.hasMore, isTrue);
  });

  group('fetchRate', () {
    test('reads config values', () async {
      when(() => configService.getNumber('loyalty_ghs_per_point_pesewas'))
          .thenAnswer((_) async => 15);
      when(() => configService.getNumber('loyalty_max_redemption_percent'))
          .thenAnswer((_) async => 40);

      final rate = await repo.fetchRate();
      expect(rate.pointPesewas, 15);
      expect(rate.maxRedemptionPercent, 40);
    });

    test('falls back to defaults when config is missing', () async {
      when(() => configService.getNumber(any())).thenAnswer((_) async => null);
      final rate = await repo.fetchRate();
      expect(rate.pointPesewas, LoyaltyRate.fallback.pointPesewas);
      expect(
          rate.maxRedemptionPercent, LoyaltyRate.fallback.maxRedemptionPercent);
    });

    test('falls back to defaults when config read throws', () async {
      when(() => configService.getNumber(any()))
          .thenThrow(const NetworkException(message: 'offline'));
      final rate = await repo.fetchRate();
      expect(rate.pointPesewas, LoyaltyRate.fallback.pointPesewas);
    });
  });
}
