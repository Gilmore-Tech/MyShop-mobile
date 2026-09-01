import 'package:shared_models/shared_models.dart';
import 'package:test/test.dart';

void main() {
  test('parses a complete destination preview from the canonical contract', () {
    final preview = RideDestinationChangePreview.fromJson({
      'rideId': 'ride-123',
      'routeRevision': 4,
      'confirmationToken': 'opaque-preview-token',
      'tokenExpiresAt': '2026-09-01T12:30:00Z',
      'oldDestination': {
        'address': 'Adum, Kumasi',
        'lat': 6.6885,
        'lng': -1.6244,
      },
      'newDestination': {
        'address': 'KNUST, Kumasi',
        'lat': 6.6732,
        'lng': -1.5654,
      },
      'oldFarePesewas': 4000,
      'newFarePesewas': 4700,
      'fareDeltaPesewas': 700,
      'projectedDistanceMeters': 8200,
      'projectedDurationSeconds': 1320,
      'promo': {'code': 'SAVE10', 'discountPesewas': 300},
      'toll': {'label': 'Airport toll', 'amountPesewas': 250},
    });

    expect(preview.routeRevision, 4);
    expect(preview.fareDeltaPesewas, 700);
    expect(preview.projectedDistanceKm, 8.2);
    expect(preview.projectedDurationMins, 22);
    expect(preview.promo?.code, 'SAVE10');
    expect(preview.toll?.amountPesewas, 250);
  });

  test('rejects a server fare delta that does not reconcile', () {
    expect(
      () => RideDestinationChangePreview.fromJson({
        'rideId': 'ride-123',
        'routeRevision': 4,
        'confirmationToken': 'opaque-preview-token',
        'oldDestination': {'address': 'Old', 'lat': 6.68, 'lng': -1.62},
        'newDestination': {'address': 'New', 'lat': 6.70, 'lng': -1.60},
        'oldFarePesewas': 4000,
        'newFarePesewas': 4700,
        'fareDeltaPesewas': 900,
        'projectedDistanceMeters': 8000,
        'projectedDurationSeconds': 1200,
      }),
      throwsFormatException,
    );
  });

  test('accepts a thin revision event and a full ride refetch projection', () {
    final thin = RideRouteUpdate.fromJson({
      'rideId': 'ride-123',
      'route_revision': 5,
    });
    final full = RideRouteUpdate.fromRideJson({
      'id': 'ride-123',
      'routeRevision': 5,
      'dropoffAddress': 'KNUST, Kumasi',
      'dropoffLat': 6.6732,
      'dropoffLng': -1.5654,
      'estimatedFarePesewas': 4700,
      'estimatedDistanceMeters': 8200,
      'estimatedDurationSeconds': 1320,
    });

    expect(thin.hasRouteProjection, isFalse);
    expect(full.hasRouteProjection, isTrue);
    expect(full.hasCompleteRouteProjection, isTrue);
    expect(full.destination?.address, 'KNUST, Kumasi');
    expect(full.projectedDistanceMeters, 8200);
    expect(full.projectedDurationSeconds, 1320);
  });

  test('destination-only events require an authoritative REST refetch', () {
    final update = RideRouteUpdate.fromJson({
      'rideId': 'ride-123',
      'routeRevision': 5,
      'destination': {
        'address': 'KNUST, Kumasi',
        'lat': 6.6732,
        'lng': -1.5654,
      },
    });

    expect(update.hasRouteProjection, isTrue);
    expect(update.hasCompleteRouteProjection, isFalse);
  });

  test(
    'legacy route snapshots without a revision hydrate as revision zero',
    () {
      final update = RideRouteUpdate.fromRideJson({
        'id': 'ride-legacy',
        'dropoffAddress': 'Adum, Kumasi',
        'dropoffLat': 6.6885,
        'dropoffLng': -1.6244,
      });

      expect(update.routeRevision, 0);
      expect(update.destination?.address, 'Adum, Kumasi');
    },
  );

  test('Ride parses and preserves the monotonic route revision', () {
    final ride = Ride.fromJson({
      'id': 'ride-123',
      'status': 'in_progress',
      'routeRevision': 7,
      'dropoffAddress': 'KNUST',
      'dropoffLat': 6.67,
      'dropoffLng': -1.56,
    });

    expect(ride.routeRevision, 7);
    expect(ride.copyWith(status: RideStatus.completed).routeRevision, 7);
  });
}
