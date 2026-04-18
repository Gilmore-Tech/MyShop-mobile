import 'dart:developer' as developer;

import 'package:api_client/api_client.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/di/providers.dart';
import 'ride_search_provider.dart';

// ── Models ────────────────────────────────────────────────────────────────────

enum BookingPhase { idle, searching, driverFound }

class VehicleOption {
  final String id;
  final String name;
  final String description;
  final int capacityPersons;
  final int farePesewas; // 100 pesewas = ₵1
  final String estimatedTime;
  final bool isMotorcycle;

  const VehicleOption({
    required this.id,
    required this.name,
    required this.description,
    required this.capacityPersons,
    required this.farePesewas,
    required this.estimatedTime,
    required this.isMotorcycle,
  });

  String get fareDisplay {
    final ghs = farePesewas / 100;
    return 'GH₵ ${ghs.toStringAsFixed(2)}';
  }
}

class RecentDestination {
  final String id;
  final String label; // "Home", "Office"
  final String address;
  final bool isHome;

  const RecentDestination({
    required this.id,
    required this.label,
    required this.address,
    required this.isHome,
  });
}

class MatchedDriver {
  final String name;
  final String vehicle; // Full name e.g. "Midnight Black Toyota Camry Hybrid"
  final String plateNumber;
  final double rating;
  final int minutesAway;
  final int driversAvailable;
  // Extended fields shown on the driver found screen
  final int tripCount;
  final bool isVerified;
  final bool isPoliceChecked;
  final String maskedPhone; // e.g. "+233 ••• ••• 42"
  final String vehicleTier; // e.g. "Premier Comfort"
  final int baseFarePesewas;
  final int distanceFarePesewas;
  final double distanceKm;
  final int bookingFeePesewas;

  /// Short vehicle name shown during active tracking, e.g. "Toyota Vitz"
  final String vehicleShortName;
  /// Confirmed fare once ride starts (may differ from estimate due to surge)
  final int confirmedFarePesewas;
  /// Payment method label shown on tracking screen
  final String paymentMethod;

  const MatchedDriver({
    required this.name,
    required this.vehicle,
    required this.plateNumber,
    required this.rating,
    required this.minutesAway,
    required this.driversAvailable,
    this.tripCount = 0,
    this.isVerified = false,
    this.isPoliceChecked = false,
    this.maskedPhone = '',
    this.vehicleTier = '',
    this.baseFarePesewas = 0,
    this.distanceFarePesewas = 0,
    this.distanceKm = 0,
    this.bookingFeePesewas = 0,
    this.vehicleShortName = '',
    this.confirmedFarePesewas = 0,
    this.paymentMethod = 'MTN Mobile Money',
  });

  int get totalFarePesewas =>
      baseFarePesewas + distanceFarePesewas + bookingFeePesewas;

  /// Active ride fare — confirmed amount or falls back to estimate
  int get activeFarePesewas =>
      confirmedFarePesewas > 0 ? confirmedFarePesewas : totalFarePesewas;

  String _fmt(int pesewas) {
    final ghs = pesewas / 100;
    return 'GH₵ ${ghs.toStringAsFixed(2)}';
  }

  String get baseFareDisplay => _fmt(baseFarePesewas);
  String get distanceFareDisplay => _fmt(distanceFarePesewas);
  String get bookingFeeDisplay => _fmt(bookingFeePesewas);
  String get totalFareDisplay => _fmt(totalFarePesewas);
  String get activeFareDisplay => _fmt(activeFarePesewas);
}

// ── Static mock data ──────────────────────────────────────────────────────────

const vehicleOptions = [
  VehicleOption(
    id: 'ride_comfort',
    name: 'Ride Comfort',
    description: 'Newer cars with extra legroom',
    capacityPersons: 4,
    farePesewas: 4200,
    estimatedTime: '3 min',
    isMotorcycle: false,
  ),
  VehicleOption(
    id: 'moto_ride_1',
    name: 'Moto-Ride',
    description: 'Beat the heavy Kumasi traffic',
    capacityPersons: 1,
    farePesewas: 1200,
    estimatedTime: '1 min',
    isMotorcycle: true,
  ),
  VehicleOption(
    id: 'moto_ride_2',
    name: 'Moto-Ride',
    description: 'Beat the heavy Kumasi traffic',
    capacityPersons: 1,
    farePesewas: 1200,
    estimatedTime: '1 min',
    isMotorcycle: true,
  ),
];

const recentDestinations = [
  RecentDestination(
    id: 'home',
    label: 'Home',
    address: 'Asolwa Residential',
    isHome: true,
  ),
  RecentDestination(
    id: 'office',
    label: 'Office',
    address: 'Tech Hub, KNUST',
    isHome: false,
  ),
  RecentDestination(
    id: 'mall',
    label: 'City Mall',
    address: 'Lake Road, Suame',
    isHome: false,
  ),
];

const _mockMatchedDriver = MatchedDriver(
  name: 'Kofi Mensah',
  vehicle: 'Midnight Black Toyota Camry Hybrid',
  plateNumber: 'GR-4557-23',
  rating: 4.92,
  minutesAway: 3,
  driversAvailable: 3,
  tripCount: 1450,
  isVerified: true,
  isPoliceChecked: true,
  maskedPhone: '+233 ••• ••• 42',
  vehicleTier: 'Premier Comfort',
  baseFarePesewas: 1200,
  distanceFarePesewas: 1550,
  distanceKm: 5.2,
  bookingFeePesewas: 250,
  vehicleShortName: 'Toyota Vitz',
  confirmedFarePesewas: 4250,
  paymentMethod: 'Cash',
);

// ── Ride Receipt ─────────────────────────────────────────────────────────────

/// Immutable receipt returned after a ride is completed.
/// Populated from GET /v1/rides/:id once status == completed (EDD § Ride Module).
class RideReceipt {
  final String rideId;
  final String driverName;

  /// Short vehicle name + plate, e.g. "Toyota Vitz · GW-482-22"
  final String vehicleDisplay;
  final double driverRating;
  final int driverTripCount;
  final bool isDriverVerified;

  /// Human-readable timestamp, e.g. "Thursday, 24 Oct | 14:32"
  final String completedAt;
  final String pickupAddress;
  final String dropoffAddress;

  // ── Fare components (all in pesewas) ──
  final int baseFarePesewas;
  final double distanceKm;
  final int distanceFarePesewas;
  final int durationMins;
  final int timeFarePesewas;
  final double surgeMultiplier;
  final int surgeFarePesewas;
  final int subtotalPesewas;
  final int taxesPesewas;

  /// Positive value — displayed as a deduction (–GHS X.XX)
  final int promoDiscountPesewas;
  final int totalPaidPesewas;

  final String paymentMethod;

  /// "SUCCESS" | "PENDING" | "FAILED"
  final String paymentStatus;

  const RideReceipt({
    required this.rideId,
    required this.driverName,
    required this.vehicleDisplay,
    required this.driverRating,
    required this.driverTripCount,
    required this.isDriverVerified,
    required this.completedAt,
    required this.pickupAddress,
    required this.dropoffAddress,
    required this.baseFarePesewas,
    required this.distanceKm,
    required this.distanceFarePesewas,
    required this.durationMins,
    required this.timeFarePesewas,
    required this.surgeMultiplier,
    required this.surgeFarePesewas,
    required this.subtotalPesewas,
    required this.taxesPesewas,
    required this.promoDiscountPesewas,
    required this.totalPaidPesewas,
    required this.paymentMethod,
    required this.paymentStatus,
  });

  String get driverFirstName => driverName.split(' ').first;
}

// ── Tip State ─────────────────────────────────────────────────────────────────

class TipState {
  /// One of the preset amounts (in pesewas), or null if none selected.
  final int? selectedPresetPesewas;

  /// Amount typed in the custom field (in pesewas). 0 means empty.
  final int customPesewas;

  const TipState({this.selectedPresetPesewas, this.customPesewas = 0});

  /// Custom field wins when non-zero; otherwise use preset.
  int get effectivePesewas =>
      customPesewas > 0 ? customPesewas : (selectedPresetPesewas ?? 0);

  bool get hasAmount => effectivePesewas > 0;
}

class TipNotifier extends StateNotifier<TipState> {
  TipNotifier() : super(const TipState());

  /// Tapping the same preset again deselects it.
  void selectPreset(int pesewas) {
    final alreadySelected = state.selectedPresetPesewas == pesewas;
    state = alreadySelected
        ? const TipState()
        : TipState(selectedPresetPesewas: pesewas);
  }

  void setCustom(String text) {
    final parsed = double.tryParse(text);
    final pesewas = parsed != null ? (parsed * 100).round() : 0;
    state = TipState(customPesewas: pesewas);
  }

  void reset() => state = const TipState();
}

final tipStateProvider =
    StateNotifierProvider<TipNotifier, TipState>((_) => TipNotifier());

// ── Mock receipt ──────────────────────────────────────────────────────────────

const _mockRideReceipt = RideReceipt(
  rideId: 'RID-92834',
  driverName: 'Kwesi Mensah',
  vehicleDisplay: 'Toyota Vitz · GW-482-22',
  driverRating: 4.9,
  driverTripCount: 1450,
  isDriverVerified: true,
  completedAt: 'Thursday, 24 Oct | 14:32',
  pickupAddress: 'Makola Market, Accra Central',
  dropoffAddress: 'Kotoka International Airport (T3)',
  baseFarePesewas: 1200,
  distanceKm: 8.4,
  distanceFarePesewas: 3250,
  durationMins: 24,
  timeFarePesewas: 600,
  surgeMultiplier: 1.2,
  surgeFarePesewas: 920,
  subtotalPesewas: 5970,
  taxesPesewas: 180,
  promoDiscountPesewas: 500,
  totalPaidPesewas: 5650,
  paymentMethod: 'MTN Mobile Money',
  paymentStatus: 'SUCCESS',
);

final rideReceiptProvider = Provider<RideReceipt>((_) => _mockRideReceipt);

// ── Providers ─────────────────────────────────────────────────────────────────

/// Set to true by the socket handler when a driver match arrives via WebSocket.
/// The polling loop in [simulateDriverMatching] checks this to exit early.
final rideMatchedViaSocketProvider = StateProvider<bool>((_) => false);

/// Currently selected vehicle option id
final selectedVehicleProvider = StateProvider<String>(
  (_) => vehicleOptions.first.id,
);

/// Booking phase: idle → searching → driverFound
final bookingPhaseProvider =
    StateNotifierProvider<BookingPhaseNotifier, BookingPhase>(
  (_) => BookingPhaseNotifier(),
);

class BookingPhaseNotifier extends StateNotifier<BookingPhase> {
  BookingPhaseNotifier() : super(BookingPhase.idle);

  void startSearch() => state = BookingPhase.searching;
  void driverFound() => state = BookingPhase.driverFound;
  void reset() => state = BookingPhase.idle;
}

/// Driver matched after search completes
final matchedDriverProvider = StateProvider<MatchedDriver?>((_) => null);

/// The ID of the active ride returned by POST /rides.
final activeRideIdProvider = StateProvider<String?>((_) => null);

/// Countdown timer (seconds remaining during search phase)
final searchCountdownProvider =
    StateNotifierProvider<CountdownNotifier, int>((_) => CountdownNotifier(45));

class CountdownNotifier extends StateNotifier<int> {
  CountdownNotifier(super.seconds);

  void tick() {
    if (state > 0) state--;
  }

  void reset() => state = 45;
}

/// ETA countdown (minutes) during an active ride
final rideEtaProvider =
    StateNotifierProvider<EtaNotifier, int>((_) => EtaNotifier(4));

class EtaNotifier extends StateNotifier<int> {
  EtaNotifier(super.minutes);

  void setEta(int minutes) => state = minutes;

  void decrement() {
    if (state > 0) state--;
  }
}

/// Phase of the live ride once a driver has accepted.
///   enRoute     — driver is heading to the pickup (ETA pill visible)
///   arrived     — driver has reached the pickup; waiting countdown running
///   inProgress  — trip has started; ETA counts down toward destination
enum RideTrackingPhase { enRoute, arrived, inProgress }

final rideTrackingPhaseProvider = StateProvider<RideTrackingPhase>(
  (_) => RideTrackingPhase.enRoute,
);

/// ETA countdown (minutes) while the trip is in progress.
final tripEtaProvider =
    StateNotifierProvider<EtaNotifier, int>((_) => EtaNotifier(12));

/// Free waiting period (seconds) once the driver has arrived.
/// Default 180 (3 minutes) matches the "Free cancellation within 3 minutes"
/// policy surfaced elsewhere in the UI.
final waitingCountdownProvider =
    StateNotifierProvider<WaitingCountdownNotifier, int>(
  (_) => WaitingCountdownNotifier(180),
);

class WaitingCountdownNotifier extends StateNotifier<int> {
  WaitingCountdownNotifier(super.seconds);

  /// Decrements unbounded — once it passes 0, negative values represent
  /// overtime (waiting that will be added to the fare).
  void tick() => state--;

  void reset([int seconds = 180]) => state = seconds;
}

/// Creates a ride via the backend and polls until a driver is matched.
///
/// Call this after the client confirms the ride on the fare-estimate screen.
/// Falls back to mock data if the API call fails so the flow is never blocked
/// during development.
Future<void> simulateDriverMatching(Ref ref) async {
  final rideService = ref.read(rideServiceProvider);
  final search = ref.read(rideSearchProvider);

  ref.read(bookingPhaseProvider.notifier).startSearch();
  ref.read(searchCountdownProvider.notifier).reset();
  ref.read(rideMatchedViaSocketProvider.notifier).state = false;

  // ── 1. Create ride via POST /rides ──────────────────────────────────────
  String? rideId;
  try {
    final pickup = search.pickup;
    final destination = search.destination;

    final result = await rideService.createRide(
      pickupLat: pickup?.lat ?? 6.6884,
      pickupLng: pickup?.lng ?? -1.6244,
      destinationLat: destination?.lat ?? 6.7000,
      destinationLng: destination?.lng ?? -1.6300,
      pickupAddress: pickup?.address,
      destinationAddress: destination?.address,
    );

    rideId = result['id'] as String?;
    ref.read(activeRideIdProvider.notifier).state = rideId;
    developer.log('Ride created: $rideId', name: 'RideProvider');
  } on ApiException catch (e) {
    developer.log(
      'createRide failed (${e.statusCode}): ${e.message}',
      name: 'RideProvider',
    );
    // Fall through — we'll use mock data below if rideId is null.
  } catch (e) {
    developer.log('createRide error: $e', name: 'RideProvider');
  }

  // ── 2. Poll GET /rides/:id until driver matched or timeout ─────────────
  if (rideId != null) {
    const maxPolls = 45;
    const pollInterval = Duration(seconds: 2);

    for (var i = 0; i < maxPolls; i++) {
      await Future.delayed(pollInterval);

      // Exit early if a WebSocket event already delivered the driver match.
      if (ref.read(rideMatchedViaSocketProvider)) return;

      ref.read(searchCountdownProvider.notifier).tick();
      ref.read(searchCountdownProvider.notifier).tick(); // 2 ticks per 2s

      try {
        final ride = await rideService.getRide(rideId);
        final status = ride['status'] as String? ?? '';
        final driver =
            ride['driver'] as Map<String, dynamic>? ?? <String, dynamic>{};

        if (status == 'accepted' || status == 'driver_assigned') {
          final matched = MatchedDriver(
            name: driver['name'] as String? ?? 'Driver',
            vehicle: driver['vehicle'] as String? ?? '',
            plateNumber: driver['plateNumber'] as String? ?? '',
            rating: (driver['rating'] as num?)?.toDouble() ?? 4.5,
            minutesAway: (driver['eta'] as num?)?.toInt() ?? 3,
            driversAvailable: 1,
            tripCount: (driver['tripCount'] as num?)?.toInt() ?? 0,
            isVerified: driver['isVerified'] as bool? ?? false,
            isPoliceChecked: driver['isPoliceChecked'] as bool? ?? false,
            maskedPhone: driver['maskedPhone'] as String? ?? '',
            vehicleTier: driver['vehicleTier'] as String? ?? '',
            baseFarePesewas:
                (ride['baseFare'] as num?)?.toInt() ?? 0,
            distanceFarePesewas:
                (ride['distanceFare'] as num?)?.toInt() ?? 0,
            distanceKm:
                (ride['distanceKm'] as num?)?.toDouble() ?? 0,
            bookingFeePesewas:
                (ride['bookingFee'] as num?)?.toInt() ?? 0,
            vehicleShortName: driver['vehicleShortName'] as String? ?? '',
            confirmedFarePesewas:
                (ride['totalFare'] as num?)?.toInt() ?? 0,
            paymentMethod: ride['paymentMethod'] as String? ?? 'Cash',
          );

          ref.read(matchedDriverProvider.notifier).state = matched;
          ref.read(bookingPhaseProvider.notifier).driverFound();
          return;
        }

        if (status == 'cancelled' || status == 'no_drivers') {
          developer.log('Ride $status — stopping poll', name: 'RideProvider');
          ref.read(bookingPhaseProvider.notifier).reset();
          return;
        }
      } on ApiException catch (e) {
        developer.log(
          'getRide poll failed (${e.statusCode}): ${e.message}',
          name: 'RideProvider',
        );
      }
    }

    // Timeout — no driver matched after max polls
    developer.log('Driver matching timed out', name: 'RideProvider');
    ref.read(bookingPhaseProvider.notifier).reset();
    return;
  }

  // ── 3. Fallback to mock when API unavailable ───────────────────────────
  for (var i = 0; i < 8; i++) {
    await Future.delayed(const Duration(seconds: 1));
    ref.read(searchCountdownProvider.notifier).tick();
  }

  ref.read(matchedDriverProvider.notifier).state = _mockMatchedDriver;
  ref.read(bookingPhaseProvider.notifier).driverFound();
}
