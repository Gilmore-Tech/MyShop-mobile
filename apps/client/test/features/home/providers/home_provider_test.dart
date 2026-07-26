import 'package:api_client/api_client.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:myshop_client/src/core/di/providers.dart';
import 'package:myshop_client/src/features/home/providers/home_provider.dart';

class _MockRideService extends Mock implements RideService {}

class _MockJobService extends Mock implements JobService {}

void main() {
  late _MockRideService rides;
  late _MockJobService jobs;

  setUp(() {
    rides = _MockRideService();
    jobs = _MockJobService();
  });

  ProviderContainer container() => ProviderContainer(
        overrides: [
          rideServiceProvider.overrideWithValue(rides),
          jobServiceProvider.overrideWithValue(jobs),
        ],
      );

  test('loads only three per source and returns newest three across roles',
      () async {
    when(() => rides.listRides(page: 1, limit: 3)).thenAnswer(
      (_) async => [
        {
          'id': 'ride-new',
          'status': 'completed',
          'pickupAddress': 'Adum, Kumasi',
          'dropoffAddress': 'Ahodwo, Kumasi',
          'createdAt': '2026-07-26T10:00:00.000Z',
        },
        {
          'id': 'ride-old',
          'status': 'requested',
          'pickupAddress': 'Bantama, Kumasi',
          'dropoffAddress': 'Asokwa, Kumasi',
          'createdAt': '2026-07-26T08:00:00.000Z',
        },
      ],
    );
    when(() => jobs.listJobs(page: 1, limit: 3)).thenAnswer(
      (_) async => [
        {
          'id': 'job-new',
          'status': 'artisan_en_route',
          'description': 'Repair leaking sink',
          'addressText': 'Daban, Kumasi',
          'category': {'name': 'Plumbing'},
          'createdAt': '2026-07-26T11:00:00.000Z',
        },
        {
          'id': 'job-middle',
          'status': 'cancelled',
          'description': 'Replace a wall socket',
          'addressText': 'Nhyiaeso, Kumasi',
          'category': {'name': 'Electrical'},
          'createdAt': '2026-07-26T09:00:00.000Z',
        },
      ],
    );
    final scope = container();
    addTearDown(scope.dispose);

    final result = await scope.read(homeRecentActivityProvider.future);

    expect(
      result.map((item) => item.id),
      ['job-new', 'ride-new', 'job-middle'],
    );
    expect(result.first.type, HomeActivityType.job);
    expect(result.first.status, HomeActivityStatus.inProgress);
    expect(result[1].title, 'Ride to Ahodwo');
    expect(result.last.status, HomeActivityStatus.cancelled);
    verify(() => rides.listRides(page: 1, limit: 3)).called(1);
    verify(() => jobs.listJobs(page: 1, limit: 3)).called(1);
  });

  test('surfaces a source failure instead of claiming there is no activity',
      () async {
    when(() => rides.listRides(page: 1, limit: 3))
        .thenAnswer((_) async => const []);
    when(() => jobs.listJobs(page: 1, limit: 3))
        .thenThrow(StateError('jobs unavailable'));
    final scope = container();
    addTearDown(scope.dispose);

    await expectLater(
      scope.read(homeRecentActivityProvider.future),
      throwsA(isA<StateError>()),
    );
  });

  test('ignores malformed records without inventing activity dates', () async {
    when(() => rides.listRides(page: 1, limit: 3)).thenAnswer(
      (_) async => [
        {'id': 'missing-created-at', 'status': 'completed'},
      ],
    );
    when(() => jobs.listJobs(page: 1, limit: 3)).thenAnswer(
      (_) async => [
        {
          'id': '',
          'status': 'completed',
          'createdAt': '2026-07-26T11:00:00.000Z',
        },
      ],
    );
    final scope = container();
    addTearDown(scope.dispose);

    final result = await scope.read(homeRecentActivityProvider.future);

    expect(result, isEmpty);
  });
}
