import 'dart:async';
import 'dart:developer' as developer;

import 'package:api_client/api_client.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_models/shared_models.dart' show kFreeWaitAtPickupSeconds;

import '../../../core/di/providers.dart';
import '../../../core/providers/current_location_provider.dart';
import '../../../core/providers/socket_provider.dart';
import '../data/ride_booking_attempt_store.dart';
import '../data/ride_booking_coordinator.dart';
import '../data/ride_cancellation_coordinator.dart';
import '../utils/ride_error_messages.dart';
import 'ride_payment_method_provider.dart';
import 'ride_search_provider.dart';

// ── Models ────────────────────────────────────────────────────────────────────

/// Lifecycle of a ride request from the rider's POV.
///
/// - [idle]: no request in flight.
/// - [searching]: POST /rides is in flight; we don't yet know whether any
///   driver was notified.
/// - [driverFound]: backend reported `driversNotified > 0` — a driver has
///   the request open and the rider is waiting for them to tap Accept.
/// - [accepted]: a driver acked acceptance — surfaced via the `ride:state`
///   socket event with `status` in `accepted | driver_en_route | …`.
///   UI navigates to the tracking screen.
/// - [failed]: request errored, all drivers declined, or the search window
///   timed out — UI shows the failure card.
enum BookingPhase { idle, searching, driverFound, accepted, failed }

class VehicleOption {
  final String id;
  final String name;
  final String description;
  final int capacityPersons;
  final int farePesewas; // 100 pesewas = ₵1
  final String estimatedTime;
  final bool isMotorcycle;

  // Set from live API estimate; zero when using fallback mock.
  final double distanceKm;
  final int durationMins;
  final bool surgeActive;

  /// Raw multiplier from the backend. 1.0 = baseline, 1.5 = 50% surge.
  /// Surfaced so the surge banner can render the actual rate ("Surge 1.3×")
  /// instead of an ambient warning the user can't size up.
  final double surgeMultiplier;

  /// `false` when the backend found no eligible driver for this ride category
  /// within the maximum match radius. Availability is category-specific: one
  /// tier may remain bookable while another is disabled.
  final bool driversAvailable;

  const VehicleOption({
    required this.id,
    required this.name,
    required this.description,
    required this.capacityPersons,
    required this.farePesewas,
    required this.estimatedTime,
    required this.isMotorcycle,
    this.distanceKm = 0,
    this.durationMins = 0,
    this.surgeActive = false,
    this.surgeMultiplier = 1.0,
    this.driversAvailable = true,
  });

  String get fareDisplay {
    final ghs = farePesewas / 100;
    return 'GH₵ ${ghs.toStringAsFixed(2)}';
  }
}

/// Availability is category-specific. A route remains bookable when at least
/// one category has a dispatchable driver, even if the default/cheapest tier
/// does not.
bool hasAvailableRideOption(Iterable<VehicleOption> options) {
  return options.any((option) => option.driversAvailable);
}

VehicleOption? firstAvailableRideOption(Iterable<VehicleOption> options) {
  for (final option in options) {
    if (option.driversAvailable) return option;
  }
  return null;
}

VehicleOption? availableRideOptionById(
  Iterable<VehicleOption> options,
  String optionId,
) {
  for (final option in options) {
    if (option.id == optionId && option.driversAvailable) return option;
  }
  return null;
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

  /// Average revealed rating (0–5). Null when the driver hasn't received
  /// any revealed ratings yet — display widgets render "New" in that case
  /// rather than faking a number. Older code defaulted to `4.5` for null,
  /// which was a misleading "good review" for fresh drivers.
  final double? rating;
  final int minutesAway;
  final int driversAvailable;
  // Extended fields shown on the driver found screen
  final int tripCount;
  final bool isVerified;
  final bool isPoliceChecked;
  final String phone; // real, dialable number e.g. "+233241234542"
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

  /// Driver's profile photo URL — empty when the backend payload omits it.
  final String photoUrl;

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
    this.phone = '',
    this.vehicleTier = '',
    this.baseFarePesewas = 0,
    this.distanceFarePesewas = 0,
    this.distanceKm = 0,
    this.bookingFeePesewas = 0,
    this.vehicleShortName = '',
    this.confirmedFarePesewas = 0,
    this.paymentMethod = 'MTN Mobile Money',
    this.photoUrl = '',
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

class RideFareFields {
  const RideFareFields({
    required this.baseFarePesewas,
    required this.distanceFarePesewas,
    required this.timeFarePesewas,
    required this.bookingFeePesewas,
    required this.taxesPesewas,
    required this.promoDiscountPesewas,
    required this.loyaltyDiscountPesewas,
    required this.totalFarePesewas,
    required this.distanceKm,
    required this.durationMins,
    required this.surgeMultiplier,
    required this.surgeFarePesewas,
    required this.subtotalPesewas,
  });

  factory RideFareFields.fromSnapshot(Map<String, dynamic> snapshot) {
    final baseFare = _readInt(snapshot, const ['baseFarePesewas', 'baseFare']);
    final distanceFare =
        _readInt(snapshot, const ['distanceFarePesewas', 'distanceFare']);
    final timeFare = _readInt(snapshot, const ['timeFarePesewas', 'timeFare']);
    final bookingFee =
        _readInt(snapshot, const ['bookingFeePesewas', 'bookingFee']);
    final taxes = _readInt(snapshot, const ['taxesPesewas', 'taxes']);
    final promoDiscount = _readInt(
      snapshot,
      const ['promoDiscountPesewas', 'discountPesewas', 'promoDiscount'],
    );
    final loyaltyDiscount = _readInt(
      snapshot,
      const ['loyaltyDiscountPesewas', 'loyaltyDiscount'],
    );
    final surgeFare =
        _readInt(snapshot, const ['surgeFarePesewas', 'surgeFare']);
    final componentTotal = baseFare +
        distanceFare +
        timeFare +
        bookingFee +
        taxes +
        surgeFare -
        promoDiscount;
    final total = _readInt(
      snapshot,
      const [
        'totalPaidPesewas',
        'amountPaidPesewas',
        'totalFarePesewas',
        'totalFare',
        'finalFarePesewas',
        'estimatedFarePesewas',
      ],
      fallback: componentTotal > 0 ? componentTotal : 0,
    );

    return RideFareFields(
      baseFarePesewas: baseFare,
      distanceFarePesewas: distanceFare,
      timeFarePesewas: timeFare,
      bookingFeePesewas: bookingFee,
      taxesPesewas: taxes,
      promoDiscountPesewas: promoDiscount,
      loyaltyDiscountPesewas: loyaltyDiscount,
      totalFarePesewas: total,
      distanceKm: _readDistanceKm(
        snapshot,
        const ['actualDistanceKm', 'distanceKm', 'estimatedDistanceKm'],
        const [
          'actualDistanceMeters',
          'distanceMeters',
          'estimatedDistanceMeters',
        ],
      ),
      durationMins: _readDurationMins(
        snapshot,
        const ['actualDurationMins', 'durationMins', 'estimatedDurationMins'],
        const [
          'actualDurationSeconds',
          'durationSeconds',
          'estimatedDurationSeconds',
        ],
      ),
      surgeMultiplier: _readDouble(
        snapshot,
        const ['surgeMultiplier'],
        fallback: 1.0,
      ),
      surgeFarePesewas: surgeFare,
      subtotalPesewas: _readInt(
        snapshot,
        const [
          'grossFarePesewas',
          'subtotalPesewas',
          'subtotal',
          'prePromoFarePesewas',
        ],
        fallback: total + promoDiscount + loyaltyDiscount,
      ),
    );
  }

  final int baseFarePesewas;
  final int distanceFarePesewas;
  final int timeFarePesewas;
  final int bookingFeePesewas;
  final int taxesPesewas;
  final int promoDiscountPesewas;
  final int loyaltyDiscountPesewas;
  final int totalFarePesewas;
  final double distanceKm;
  final int durationMins;
  final double surgeMultiplier;
  final int surgeFarePesewas;
  final int subtotalPesewas;
}

int _readInt(
  Map<String, dynamic> source,
  List<String> keys, {
  int fallback = 0,
}) {
  for (final key in keys) {
    final value = source[key];
    if (value is num) return value.toInt();
    if (value is String) {
      final parsed = num.tryParse(value);
      if (parsed != null) return parsed.toInt();
    }
  }
  return fallback;
}

double _readDouble(
  Map<String, dynamic> source,
  List<String> keys, {
  double fallback = 0,
}) {
  for (final key in keys) {
    final value = source[key];
    if (value is num) return value.toDouble();
    if (value is String) {
      final parsed = num.tryParse(value);
      if (parsed != null) return parsed.toDouble();
    }
  }
  return fallback;
}

double _readDistanceKm(
  Map<String, dynamic> source,
  List<String> kmKeys,
  List<String> meterKeys,
) {
  final km = _readNullableDouble(source, kmKeys);
  if (km != null) return km;

  final meters = _readNullableDouble(source, meterKeys);
  if (meters != null) return meters / 1000;

  return 0;
}

int _readDurationMins(
  Map<String, dynamic> source,
  List<String> minuteKeys,
  List<String> secondKeys,
) {
  final minutes = _readNullableDouble(source, minuteKeys);
  if (minutes != null) return minutes.toInt();

  final seconds = _readNullableDouble(source, secondKeys);
  if (seconds != null) return (seconds / 60).round();

  return 0;
}

double? _readNullableDouble(Map<String, dynamic> source, List<String> keys) {
  for (final key in keys) {
    final value = source[key];
    if (value is num) return value.toDouble();
    if (value is String) {
      final parsed = num.tryParse(value);
      if (parsed != null) return parsed.toDouble();
    }
  }
  return null;
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
    description: 'Beat the heavy traffic',
    capacityPersons: 1,
    farePesewas: 1200,
    estimatedTime: '1 min',
    isMotorcycle: true,
  ),
  VehicleOption(
    id: 'moto_ride_2',
    name: 'Moto-Ride',
    description: 'Beat the heavy traffic',
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

// ── Ride Receipt ─────────────────────────────────────────────────────────────

/// Immutable receipt returned after a ride is completed.
/// Populated from GET /v1/rides/:id once status == completed (EDD § Ride Module).
class RideReceipt {
  final String rideId;
  final String driverName;

  /// Short vehicle name + plate, e.g. "Toyota Vitz · GW-482-22"
  final String vehicleDisplay;

  /// Average revealed rating (0–5). Null when the driver has no
  /// revealed ratings yet — display widgets render "New" rather than
  /// faking 0.0★.
  final double? driverRating;
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
  final int loyaltyDiscountPesewas;
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
    required this.loyaltyDiscountPesewas,
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

// ── Receipt provider ────────────────────────────────────────────────────────
//
// Populated from a `ride:state` snapshot the moment the backend reports
// `status=completed` (see `socket_provider.dart` and `_hydrateFromRest`).
// Stays null until then; consumers should render a fallback for the rare
// race where the screen mounts before the snapshot arrives (e.g. a deep-
// link straight into /ride-complete).
final rideReceiptProvider = StateProvider<RideReceipt?>((_) => null);

/// Build a [RideReceipt] from the canonical `ride:state` snapshot shape.
/// Fare fields are deliberately alias-tolerant because older snapshots used
/// `totalFare` / `baseFare`, while newer endpoints use `finalFarePesewas` /
/// `baseFarePesewas`. One parser keeps estimate, tracking, and receipt screens
/// from drifting when the backend returns either shape.
RideReceipt buildRideReceiptFromSnapshot(Map<String, dynamic> snapshot) {
  final driver = snapshot['driver'] is Map<String, dynamic>
      ? snapshot['driver'] as Map<String, dynamic>
      : const <String, dynamic>{};
  final firstName = driver['firstName'] as String?;
  final lastName = driver['lastName'] as String?;
  final assembledName = (firstName != null || lastName != null)
      ? [firstName, lastName].whereType<String>().join(' ').trim()
      : null;
  final driverName = (driver['name'] as String?) ??
      assembledName ??
      (driver['fullName'] as String?) ??
      'Driver';
  final shortVehicle = (driver['vehicleShortName'] as String?) ??
      (driver['vehicle'] as String?) ??
      '';
  final plate = driver['plateNumber'] as String? ?? '';
  final vehicleDisplay = [
    shortVehicle,
    if (plate.isNotEmpty) plate,
  ].where((p) => p.isNotEmpty).join(' · ');
  final fare = RideFareFields.fromSnapshot(snapshot);
  final completedAtRaw = snapshot['completedAt'] as String?;
  final completedAt = completedAtRaw != null
      ? _formatCompletedAt(DateTime.tryParse(completedAtRaw))
      : '';
  final paymentMethodRaw = snapshot['paymentMethod'] as String? ?? 'cash';
  return RideReceipt(
    rideId: snapshot['id'] as String? ?? snapshot['rideId'] as String? ?? '',
    driverName: driverName,
    vehicleDisplay: vehicleDisplay,
    driverRating: (driver['rating'] as num?)?.toDouble(),
    driverTripCount: (driver['tripCount'] as num?)?.toInt() ?? 0,
    isDriverVerified: driver['isVerified'] as bool? ?? false,
    completedAt: completedAt,
    pickupAddress: snapshot['pickupAddress'] as String? ?? '',
    dropoffAddress: snapshot['dropoffAddress'] as String? ?? '',
    baseFarePesewas: fare.baseFarePesewas,
    distanceKm: fare.distanceKm,
    distanceFarePesewas: fare.distanceFarePesewas,
    durationMins: fare.durationMins,
    timeFarePesewas: fare.timeFarePesewas,
    surgeMultiplier: fare.surgeMultiplier,
    surgeFarePesewas: fare.surgeFarePesewas,
    subtotalPesewas: fare.subtotalPesewas,
    taxesPesewas: fare.taxesPesewas,
    promoDiscountPesewas: fare.promoDiscountPesewas,
    loyaltyDiscountPesewas: fare.loyaltyDiscountPesewas,
    totalPaidPesewas: fare.totalFarePesewas,
    paymentMethod: _formatPaymentMethod(paymentMethodRaw),
    paymentStatus: 'SUCCESS',
  );
}

String _formatCompletedAt(DateTime? at) {
  if (at == null) return '';
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  const weekdays = [
    'Monday',
    'Tuesday',
    'Wednesday',
    'Thursday',
    'Friday',
    'Saturday',
    'Sunday',
  ];
  final local = at.toLocal();
  final hh = local.hour.toString().padLeft(2, '0');
  final mm = local.minute.toString().padLeft(2, '0');
  return '${weekdays[local.weekday - 1]}, ${local.day} '
      '${months[local.month - 1]} | $hh:$mm';
}

String _formatPaymentMethod(String raw) => formatRidePaymentMethodLabel(raw);

// ── Providers ─────────────────────────────────────────────────────────────────

/// Set to true by the socket handler when a driver match arrives via WebSocket.
/// The polling loop in [simulateDriverMatching] checks this to exit early.
final rideMatchedViaSocketProvider = StateProvider<bool>((_) => false);

/// Count of drivers the matcher pushed the ride request to, surfaced in the
/// POST /rides response. Used by the matching screen to show a meaningful
/// number while we're in [BookingPhase.driverFound] (waiting for accept) —
/// the [matchedDriverProvider] is still null at that point, so we can't
/// derive the count from there.
final driversNotifiedProvider = StateProvider<int>((_) => 0);

/// Currently selected vehicle option id
final selectedVehicleProvider = StateProvider<String>(
  (_) => vehicleOptions.first.id,
);

/// Booking phase: idle → searching → driverFound | failed
final bookingPhaseProvider =
    StateNotifierProvider<BookingPhaseNotifier, BookingPhase>(
  (_) => BookingPhaseNotifier(),
);

/// Human-readable reason for [BookingPhase.failed] — surfaced on the
/// driver-matching screen so the rider sees what went wrong.
final bookingFailureMessageProvider = StateProvider<String?>((_) => null);

/// Why the backend just (re-)dispatched. Drives the rider's matching screen
/// copy: 'initial' → "Notifying N driver(s)…"; 'decline' → "Driver declined,
/// searching again"; 'timeout' → "Driver didn't respond, expanding search".
enum MatcherReason { initial, decline, timeout }

MatcherReason parseMatcherReason(String? raw) {
  switch (raw) {
    case 'initial':
      return MatcherReason.initial;
    case 'decline':
      return MatcherReason.decline;
    case 'timeout':
    default:
      return MatcherReason.timeout;
  }
}

/// Backend matcher progress snapshot pushed by the `ride:matcher_progress`
/// socket event on every dispatch/expansion attempt. Drives the rider's
/// matching screen copy so a sequence of declines isn't a silent spinner.
class MatcherProgress {
  const MatcherProgress({
    required this.attempt,
    required this.driversTried,
    required this.driversRemaining,
    required this.radiusKm,
    required this.reason,
  });

  /// Re-dispatch attempt counter (1-indexed). Increments on every expansion.
  final int attempt;

  /// Cumulative count of distinct drivers we've notified so far.
  final int driversTried;

  /// Drivers in the just-broadcast batch (the ones currently deciding).
  final int driversRemaining;

  /// Radius the matcher just searched at, in kilometres.
  final double radiusKm;

  /// What triggered this event — set by the backend.
  final MatcherReason reason;
}

final matcherProgressProvider = StateProvider<MatcherProgress?>((_) => null);

/// Rider-side worst-case matching wait ceiling.
///
/// BR-39 allows new delivery attempts for five minutes after dispatch becomes
/// ready. An attempt whose full ten-second receipt window fits may then retain
/// a fresh 45-second decision window, so the authoritative worst case is 345
/// seconds. Keep another 30 seconds for worker/socket propagation and the
/// final REST reconciliation.
///
/// The backend remains the source of truth for the final outcome; this local
/// ceiling only bounds our socket re-join / REST hydration loop.
const int kRideMatchingSearchCeilingSeconds = 375;

class BookingPhaseNotifier extends StateNotifier<BookingPhase> {
  BookingPhaseNotifier() : super(BookingPhase.idle);

  void startSearch() => state = BookingPhase.searching;
  void driverFound() => state = BookingPhase.driverFound;
  void accepted() => state = BookingPhase.accepted;
  void fail() => state = BookingPhase.failed;
  void reset() => state = BookingPhase.idle;
}

/// Driver matched after search completes
final matchedDriverProvider = StateProvider<MatchedDriver?>((_) => null);

/// The ID of the active ride returned by POST /rides.
final activeRideIdProvider = StateProvider<String?>((_) => null);

/// Countdown timer (seconds remaining during search phase). Sized to cover
/// the backend's full BR-39 matching budget: five minutes in which a new
/// delivery attempt may start, the final timely recipient's fresh 45-second
/// decision window, and a 30-second propagation/reconciliation buffer. Without this buffer the
/// local loop fires `failWith` ahead of the backend's real verdict — the
/// rider sees a generic "couldn't find a driver in time" while the matcher
/// is still trying. Keep this in lockstep with `MAX_MATCH_RADIUS_KM`,
/// `RIDE_RADIUS_EXPANSION_KM`, `RIDE_DRIVER_ACCEPTANCE_WINDOW_SECS`.
final searchCountdownProvider = StateNotifierProvider<CountdownNotifier, int>(
  (_) => CountdownNotifier(kRideMatchingSearchCeilingSeconds),
);

class CountdownNotifier extends StateNotifier<int> {
  CountdownNotifier(super.seconds);

  void tick() {
    if (state > 0) state--;
  }

  void reset() => state = kRideMatchingSearchCeilingSeconds;
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

/// Live driver coordinates while a ride is active. Updated by the
/// `driver:location` socket listener in `core/providers/socket_provider.dart`
/// (per-fix, smooth) and seeded from `ride:state` snapshots when the
/// snapshot includes driver coordinates.
///
/// Null while the rider is en-route to matching, or whenever the backend
/// hasn't yet pushed a fix for this ride.
class LiveDriverPosition {
  const LiveDriverPosition({
    required this.latitude,
    required this.longitude,
    this.heading,
    this.updatedAt,
  });

  final double latitude;
  final double longitude;
  final double? heading;
  final DateTime? updatedAt;
}

final liveDriverPositionProvider =
    StateProvider<LiveDriverPosition?>((_) => null);

/// Tracking-screen maintenance loop. Runs while the rider is on an
/// active ride; auto-disposes when they leave. Two safety belts:
///
///   1. **Re-emit `client:track:ride` every tick.** The initial join is
///      fire-and-forget, and a socket disconnect/reconnect during the
///      ride can drop the rider from the room. Re-emitting cheaply on
///      every tick keeps the room membership healthy.
///   2. **One-shot REST hydrate every 12 s.** If `ride:state` events
///      stop reaching us (room race, dropped emit, anything), a periodic
///      `GET /rides/:id` keeps the local state honest. We hydrate when
///      the backend's status is *ahead* of what we have locally — never
///      regress, never clobber a fresher snapshot.
///
/// Watched from the tracking screen so it stops the moment the rider
/// leaves. Intentionally not a polling fallback for the primary flow —
/// `ride:state` is still the authoritative path; this is a self-healing
/// belt for when the gateway misbehaves.
final activeRideTrackingMaintainerProvider =
    StreamProvider.autoDispose<void>((ref) async* {
  final rideId = ref.watch(activeRideIdProvider);
  if (rideId == null || rideId.isEmpty) return;
  final rideService = ref.read(rideServiceProvider);
  final socket = ref.read(socketServiceProvider);

  Future<void> rejoinRoom() async {
    try {
      if (socket.isConnected) {
        socket.emit('client:track:ride', {'rideId': rideId});
      }
    } catch (_) {}
  }

  Future<void> hydrateIfStale() async {
    // Re-uses the same `_hydrateFromRest` path the matching loop calls,
    // so all derived providers flip identically whether the snapshot
    // came in over WS or REST. Pass `ref.read` as a tear-off so the
    // shared helper can write into providers without holding a
    // ProviderContainer.
    await _hydrateFromRest(ref.read, rideService, rideId);
  }

  yield null;
  // First tick — rejoin only. Don't hammer GET on screen mount; let the
  // socket do its job for the first interval.
  await rejoinRoom();

  while (true) {
    // Tighten the cadence once the trip is in_progress: the rider is
    // staring at the screen waiting for the "End Trip" → /ride-complete
    // transition, and a missed `ride:state` broadcast there is the most
    // visible failure mode (the rider sits on a stale screen for ~12 s
    // before the next refresh). Earlier phases stick to 12 s — this is
    // still a self-heal, not the primary path.
    final phase = ref.read(rideTrackingPhaseProvider);
    final interval = phase == RideTrackingPhase.inProgress
        ? const Duration(seconds: 5)
        : const Duration(seconds: 12);
    await Future<void>.delayed(interval);
    await rejoinRoom();
    await hydrateIfStale();
    yield null;
  }
});

/// Phase of the live ride once a driver has accepted. Driven entirely by
/// `ride:state` snapshot events broadcast from the backend — the rider's UI
/// is a passive reflection of what the driver has reported, no client-side
/// simulation timers.
///   enRoute     — driver is heading to the pickup (ETA pill visible)
///   arrived     — driver has reached the pickup; waiting countdown running
///   inProgress  — trip has started; ETA counts down toward destination
///   completed   — trip finished; tracking screen routes to /ride-complete
///   cancelled   — driver or system aborted mid-trip; tracking screen
///                 shows a snackbar and routes back to home
enum RideTrackingPhase { enRoute, arrived, inProgress, completed, cancelled }

final rideTrackingPhaseProvider = StateProvider<RideTrackingPhase>(
  (_) => RideTrackingPhase.enRoute,
);

/// Server timestamp for when the driver reached pickup. The rider waiting
/// timer uses this instead of "when this device received the event", so delayed
/// socket delivery doesn't make the client and driver countdowns drift apart.
final rideArrivalAnchorProvider = StateProvider<DateTime?>((_) => null);

/// ETA countdown (minutes) while the trip is in progress.
final tripEtaProvider =
    StateNotifierProvider<EtaNotifier, int>((_) => EtaNotifier(12));

/// Free waiting period (seconds) once the driver has arrived. Shared with the
/// driver app so both countdowns stay on the same 3-minute policy window.
final waitingCountdownProvider =
    StateNotifierProvider<WaitingCountdownNotifier, int>(
  (_) => WaitingCountdownNotifier(kFreeWaitAtPickupSeconds),
);

class WaitingCountdownNotifier extends StateNotifier<int> {
  WaitingCountdownNotifier(this._freeWaitSeconds) : super(_freeWaitSeconds);

  final int _freeWaitSeconds;
  DateTime? _anchor;

  /// Decrements unbounded — once it passes 0, negative values represent
  /// overtime (waiting that will be added to the fare). Recompute from the
  /// arrival anchor so background timer throttling cannot desync the display.
  void tick() => _recompute();

  void reset([int? seconds]) {
    _anchor = null;
    state = seconds ?? _freeWaitSeconds;
  }

  void resetFromArrival(DateTime? arrivedAt, {int? freeWaitSeconds}) {
    _anchor = (arrivedAt ?? DateTime.now()).toUtc();
    _recompute(freeWaitSeconds);
  }

  void _recompute([int? overrideFreeWaitSeconds]) {
    final anchor = _anchor;
    final freeWaitSeconds = overrideFreeWaitSeconds ?? _freeWaitSeconds;
    if (anchor == null) {
      state = freeWaitSeconds;
      return;
    }
    final elapsed = DateTime.now().toUtc().difference(anchor).inSeconds;
    state = freeWaitSeconds - elapsed;
  }
}

/// Creates a ride via the backend and polls until a driver is matched.
///
/// Call this after the client confirms the ride on the fare-estimate screen.
/// Failures (couldn't request, no drivers, timeout, cancelled) flip
/// [bookingPhaseProvider] to [BookingPhase.failed] and store a message in
/// [bookingFailureMessageProvider] so the matching screen can render a
/// real error state instead of a fake driver.
///
/// Takes a [ProviderContainer] (not a [WidgetRef]) because the caller
/// navigates away from the fare-estimate screen on the same frame as
/// kicking this off — using the screen's `WidgetRef` past the next
/// `await` would throw `StateError: Cannot use "ref" after the widget
/// was disposed`. The container outlives any single widget.
Future<void> requestRideAndMatchDriver(
  ProviderContainer ref, {
  List<Map<String, dynamic>> pretripStops = const [],
}) async {
  final rideService = ref.read(rideServiceProvider);
  final bookingCoordinator = ref.read(rideBookingCoordinatorProvider);
  final search = ref.read(rideSearchProvider);

  ref.read(bookingPhaseProvider.notifier).startSearch();
  ref.read(searchCountdownProvider.notifier).reset();
  ref.read(rideMatchedViaSocketProvider.notifier).state = false;
  ref.read(bookingFailureMessageProvider.notifier).state = null;
  ref.read(driversNotifiedProvider.notifier).state = 0;
  ref.read(matcherProgressProvider.notifier).state = null;
  ref.read(liveDriverPositionProvider.notifier).state = null;
  ref.read(rideArrivalAnchorProvider.notifier).state = null;

  void failWith(String message) {
    ref.read(bookingFailureMessageProvider.notifier).state = message;
    ref.read(bookingPhaseProvider.notifier).fail();
  }

  // ── 1. Create ride via POST /rides ──────────────────────────────────────
  String? rideId;
  try {
    final pickup = search.pickup;
    final destination = search.destination;
    // Pickup falls back to the cached device fix so an unset pickup still
    // resolves to a real coordinate near the user (rather than the pilot
    // city centre, which would mis-route the driver).
    final cached = ref.read(currentDevicePositionProvider);

    final selectedMethod = ref.read(selectedRidePaymentMethodProvider);
    // The selected vehicle option id IS the ride category slug (e.g. 'regular',
    // 'comfort') — backend prices and matches on it. Mutually exclusive: a
    // Comfort booking only reaches Comfort-approved drivers.
    final selectedCategory = ref.read(selectedVehicleProvider);
    final pickupLat = pickup?.lat ?? cached?.latitude ?? 6.6884;
    final pickupLng = pickup?.lng ?? cached?.longitude ?? -1.6244;
    final destinationLat = destination?.lat ?? 6.7000;
    final destinationLng = destination?.lng ?? -1.6300;
    final pickupAddress = pickup?.address;
    final destinationAddress = destination?.address;
    final stops = pretripStops.isEmpty ? null : pretripStops;
    final rideCategory = selectedCategory.isEmpty ? null : selectedCategory;
    final requestFingerprint = rideBookingRequestFingerprint({
      'pickupLat': pickupLat,
      'pickupLng': pickupLng,
      'dropoffLat': destinationLat,
      'dropoffLng': destinationLng,
      if (pickupAddress != null) 'pickupAddress': pickupAddress,
      if (destinationAddress != null) 'dropoffAddress': destinationAddress,
      if (stops != null) 'stops': stops,
      'paymentMethod': selectedMethod.wireValue,
      if (rideCategory != null) 'rideCategory': rideCategory,
    });
    final resolution = await bookingCoordinator.resolveOrCreate(
      requestFingerprint: requestFingerprint,
      create: (bookingKey) => rideService.createRide(
        bookingKey: bookingKey,
        pickupLat: pickupLat,
        pickupLng: pickupLng,
        destinationLat: destinationLat,
        destinationLng: destinationLng,
        pickupAddress: pickupAddress,
        destinationAddress: destinationAddress,
        stops: stops,
        paymentMethod: selectedMethod.wireValue,
        rideCategory: rideCategory,
      ),
    );
    final result = resolution.response;
    developer.log(
      resolution.recovered
          ? 'Recovered a pending ride booking attempt'
          : 'Ride booking attempt accepted by server',
      name: 'RideProvider',
    );

    // Backend has shipped the ride id under a few different shapes during
    // development — accept any of them so a wire-format change doesn't
    // strand the client at "no ride id". Order matches likelihood.
    rideId = _extractRideId(result);
    ref.read(activeRideIdProvider.notifier).state = rideId;

    // POST /rides returns `driversNotified` — the count of drivers the
    // matcher pushed the request to. As soon as that's > 0 we know a
    // driver has the request open on their screen, so we flip the rider
    // out of the "searching" radar into the "driver found" state. The
    // final `accepted` transition (and the navigation to the tracking
    // screen) only happens once a driver actually taps Accept.
    final notified = (result['driversNotified'] as num?)?.toInt() ?? 0;
    ref.read(driversNotifiedProvider.notifier).state = notified;
    if (notified > 0) {
      ref.read(bookingPhaseProvider.notifier).driverFound();
    }

    // Try to join the ride's tracking room immediately. If the socket is
    // still mid-handshake at this point the emit silently no-ops — the
    // socket-provider's connectionStream listener will (re-)join once the
    // handshake completes.
    if (rideId != null) {
      try {
        final socket = ref.read(socketServiceProvider);
        if (socket.isConnected) {
          socket.emit('client:track:ride', {'rideId': rideId});
          developer.log('Joined ride room: $rideId', name: 'RideProvider');
        } else {
          developer.log(
              'Socket not yet connected — track:ride deferred to onConnect',
              name: 'RideProvider');
        }
      } catch (e) {
        developer.log(
          'client:track:ride emit failed with ${e.runtimeType}',
          name: 'RideProvider',
        );
      }
    }
  } on RideBookingLookupUncertainException catch (e) {
    developer.log(
      'Booking recovery was inconclusive '
      '(status=${e.statusCode}, code=${e.errorCode ?? 'unknown'})',
      name: 'RideProvider',
      level: 800,
    );
    failWith(
      "We couldn't confirm your previous ride request, so no new request was sent. Check your connection and try again.",
    );
    return;
  } on ApiException catch (e) {
    developer.log(
      'createRide failed (status=${e.statusCode}, '
      'code=${e.errorCode ?? 'unknown'})',
      name: 'RideProvider',
    );
    failWith(rideRequestErrorMessage(e));
    return;
  } catch (e) {
    developer.log(
      'createRide failed with ${e.runtimeType}',
      name: 'RideProvider',
    );
    failWith("Couldn't request a ride. Please try again.");
    return;
  }

  if (rideId == null) {
    failWith("The server didn't return a ride ID. Please try again.");
    return;
  }

  // ── 2. Wait for `ride:state` snapshot or timeout ───────────────────────
  // Primary path is the backend's `ride:state` push. Two safety belts run
  // alongside the wait:
  //
  //   1. Re-emit `client:track:ride` whenever the socket is connected.
  //      The initial join in step 1 above is fire-and-forget; on a cold
  //      network or Render cold start the socket may not yet be open,
  //      and the connection-stream deferred-join can miss on edge cases.
  //      Re-emitting every couple of seconds while we're still waiting
  //      is cheap and ensures the rider lands in the ride room.
  //
  //   2. Periodic REST hydrate every 10s. If the backend has already
  //      moved the ride past `requested` (driver accepted, cancelled,
  //      etc.) but no `ride:state` reached us, pull the state via REST
  //      and apply it locally. The previous version did exactly one
  //      one-shot at the 10s mark — fine when the driver accepts in <10s,
  //      but if the driver took 11s+ the hydrate saw `status: requested`
  //      and bailed, leaving the rider stranded for the rest of the
  //      45s window. Polling at 10s intervals (≈ 5 calls per matching
  //      window) sits well under the backend's 30 req/min throttle.
  // 375 s == BR-39's 300 s new-attempt budget + the final timely recipient's
  // 45 s decision window + 30 s for worker/socket/REST reconciliation.
  // Loop bails early on success, failure, or rider cancel — this is just
  // the worst-case ceiling so we don't outlast the backend's verdict.
  final socket = ref.read(socketServiceProvider);
  for (var i = 0; i < kRideMatchingSearchCeilingSeconds; i++) {
    await Future<void>.delayed(const Duration(seconds: 1));
    if (ref.read(rideMatchedViaSocketProvider)) return;
    if (ref.read(bookingPhaseProvider) == BookingPhase.failed) return;
    ref.read(searchCountdownProvider.notifier).tick();

    // Belt 1 — re-emit the room join every 2s while still waiting.
    if (i % 2 == 0 && socket.isConnected) {
      try {
        socket.emit('client:track:ride', {'rideId': rideId});
      } catch (_) {
        // Socket may have flipped to disconnected mid-emit; the next
        // tick will retry.
      }
    }

    // Belt 2 — REST hydrate every 10s through the matching window.
    if (i > 0 && i % 10 == 0) {
      unawaited(_hydrateFromRest(ref.read, rideService, rideId));
    }
  }

  // Loop ceiling reached. Do one final server read first so a last-second
  // accept/cancel wins. If the backend is still silent after the full matching
  // budget, stop the rider UI and best-effort cancel the stale requested ride.
  // Leaving the phase in searching/driverFound here is what caused production
  // reports of "searching for driver" staying on screen forever.
  await _hydrateFromRest(ref.read, rideService, rideId);
  final phaseAfterFinalHydrate = ref.read(bookingPhaseProvider);
  if (ref.read(rideMatchedViaSocketProvider) ||
      phaseAfterFinalHydrate == BookingPhase.accepted ||
      phaseAfterFinalHydrate == BookingPhase.failed) {
    return;
  }

  developer.log(
    'Matching loop ceiling reached ($kRideMatchingSearchCeilingSeconds s) — '
    'failing stale request locally. phase=$phaseAfterFinalHydrate',
    name: 'RideProvider',
  );

  try {
    await rideService.cancelRide(
      rideId,
      reason: 'client_matching_timeout_recovery',
    );
    await ref.read(rideBookingAttemptStoreProvider).clear();
  } on ApiException catch (e) {
    developer.log(
      'cancel stale matching ride failed (status=${e.statusCode}, '
      'code=${e.errorCode ?? 'unknown'})',
      name: 'RideProvider',
      level: 800,
    );
    // A concurrent driver accept can make cancellation invalid. Re-check once
    // before surfacing the failure card.
    await _hydrateFromRest(ref.read, rideService, rideId);
    final phaseAfterCancelFailure = ref.read(bookingPhaseProvider);
    if (ref.read(rideMatchedViaSocketProvider) ||
        phaseAfterCancelFailure == BookingPhase.accepted ||
        phaseAfterCancelFailure == BookingPhase.failed) {
      return;
    }
  } catch (e) {
    developer.log(
      'cancel stale matching ride failed with ${e.runtimeType}',
      name: 'RideProvider',
      level: 800,
    );
  }

  ref.read(matchedDriverProvider.notifier).state = null;
  failWith(noDriversAvailableMessage);
}

/// One-shot REST hydrate when socket-based snapshot delivery has been
/// silent for too long. Pulls `GET /rides/:id`, and if the backend has
/// already moved the ride to a state the snapshot listener cares about,
/// drops the payload through that same listener so all the providers
/// flip the way they would have on a real `ride:state` event.
/// Generic reader that can be backed by either a [ProviderContainer.read]
/// or a [Ref.read] tear-off. Both share the same generic signature, so we
/// can reuse [hydrateActiveRideFromRest] from the matching loop (which
/// lives outside any widget and uses a container), the tracking maintainer
/// (which lives inside a StreamProvider and uses a ref), and the recovery
/// bridge (which lives inside another Provider and also uses a ref).
typedef RideStateReader = T Function<T>(ProviderListenable<T>);

/// Public re-entry point for hydrating the rider's ride state from REST.
/// Used by the matching loop's belt, the tracking screen's maintenance
/// loop, and the cold-start recovery bridge — all of which need the same
/// shape of "ask the server for the current ride and push it through the
/// same providers a `ride:state` socket event would touch".
Future<void> hydrateActiveRideFromRest(
  RideStateReader read,
  RideService rideService,
  String rideId,
) =>
    _hydrateFromRest(read, rideService, rideId);

Future<void> _hydrateFromRest(
  RideStateReader read,
  RideService rideService,
  String rideId,
) async {
  try {
    developer.log('REST fallback hydrating ride $rideId', name: 'RideProvider');
    final json = await rideService.getRide(rideId);
    final status = json['status'] as String? ?? '';
    final cancelledBy = json['cancelledBy'] as String?;
    final cancellationReason =
        (json['cancellationReason'] ?? json['reason']) as String?;
    // Only fire the hydrate path when the backend has actually moved past
    // `requested` — otherwise we'd push a half-built MatchedDriver.
    if (status == 'requested') return;
    // Apply through the same handler the socket uses so all derived
    // providers flip identically. We're not in socket_provider's scope
    // here, but `applyRideSnapshot` is private; instead, push the raw
    // status fields into the public providers.
    if (status == 'cancelled' || _isNoDriversTerminal(status)) {
      if (status == 'cancelled') {
        unawaited(read(rideBookingAttemptStoreProvider).clear());
      }
      final noDrivers = _isNoDriversTerminal(
        status,
        reason: cancellationReason,
        cancelledBy: cancelledBy,
      );
      read(bookingFailureMessageProvider.notifier).state = noDrivers
          ? noDriversAvailableMessage
          : cancelledBy == 'driver'
              ? 'The driver cancelled this ride.'
              : 'This ride was cancelled.';
      read(bookingPhaseProvider.notifier).fail();
      // CRITICAL: also flip the tracking phase. The live-map tracking screen
      // watches rideTrackingPhaseProvider (NOT bookingPhase), so without this a
      // cancel detected via the REST poll left the rider stuck on the map. The
      // tracking screen's listener turns this into the "ride cancelled" snackbar
      // + route home (mirrors the socket path and the `completed` branch below).
      read(rideTrackingPhaseProvider.notifier).state =
          RideTrackingPhase.cancelled;
      return;
    }
    // Completed — populate the receipt so the post-trip screens have real
    // data. Tracking-phase flip is handled by the socket-side handler in
    // socket_provider; this REST path mirrors it for the recovery case.
    if (status == 'completed') {
      unawaited(read(rideBookingAttemptStoreProvider).clear());
      read(rideTrackingPhaseProvider.notifier).state =
          RideTrackingPhase.completed;
      read(rideArrivalAnchorProvider.notifier).state = null;
      read(rideReceiptProvider.notifier).state =
          buildRideReceiptFromSnapshot(json);
      return;
    }
    // Active — synthesise a `ride:state`-style snapshot and let the
    // existing socket-side handler do the work. We don't have access to
    // it from here, so manually push the providers; this code path is
    // identical to the socket handler's `accepted` branch.
    final driver =
        json['driver'] as Map<String, dynamic>? ?? <String, dynamic>{};
    final firstName = driver['firstName'] as String?;
    final lastName = driver['lastName'] as String?;
    final assembledName = (firstName != null || lastName != null)
        ? [firstName, lastName].whereType<String>().join(' ').trim()
        : null;
    final fare = RideFareFields.fromSnapshot(json);
    final matched = MatchedDriver(
      name: (driver['name'] as String?) ??
          assembledName ??
          (driver['fullName'] as String?) ??
          'Driver',
      vehicle: driver['vehicle'] as String? ?? '',
      plateNumber: driver['plateNumber'] as String? ?? '',
      rating: (driver['rating'] as num?)?.toDouble(),
      minutesAway: (driver['eta'] as num?)?.toInt() ?? 3,
      driversAvailable: 1,
      tripCount: (driver['tripCount'] as num?)?.toInt() ?? 0,
      isVerified: driver['isVerified'] as bool? ?? false,
      isPoliceChecked: driver['isPoliceChecked'] as bool? ?? false,
      phone: (driver['phone'] as String?) ??
          (driver['maskedPhone'] as String?) ??
          '',
      vehicleTier: driver['vehicleTier'] as String? ?? '',
      baseFarePesewas: fare.baseFarePesewas,
      distanceFarePesewas: fare.distanceFarePesewas,
      distanceKm: fare.distanceKm,
      bookingFeePesewas: fare.bookingFeePesewas,
      vehicleShortName: driver['vehicleShortName'] as String? ?? '',
      confirmedFarePesewas: fare.totalFarePesewas,
      paymentMethod: json['paymentMethod'] as String? ?? 'Cash',
      photoUrl: (driver['photoUrl'] as String?) ??
          (driver['profilePhotoUrl'] as String?) ??
          (driver['avatarUrl'] as String?) ??
          '',
    );
    read(matchedDriverProvider.notifier).state = matched;
    read(bookingPhaseProvider.notifier).accepted();
    read(rideMatchedViaSocketProvider.notifier).state = true;

    // Seed pickup/destination into rideSearchProvider. The tracking map
    // (`RideRouteMap`) reads its markers, polyline target, and initial
    // camera off this provider; without it a recovered ride lands the
    // rider on a blank Kumasi-centred map with no destination pin and no
    // route — exactly the bug we were chasing post-relaunch.
    final pickupLat = (json['pickupLat'] ?? json['pickupLatitude']) as num?;
    final pickupLng = (json['pickupLng'] ?? json['pickupLongitude']) as num?;
    final dropoffLat = (json['dropoffLat'] ?? json['dropoffLatitude']) as num?;
    final dropoffLng = (json['dropoffLng'] ?? json['dropoffLongitude']) as num?;
    final pickupAddress = json['pickupAddress'] as String? ?? '';
    final dropoffAddress = json['dropoffAddress'] as String? ?? '';
    if (pickupLat != null && pickupLng != null) {
      read(rideSearchProvider.notifier).setLocation(
        RideSearchField.pickup,
        RideLocation(
          name: pickupAddress.isNotEmpty ? pickupAddress : 'Pickup',
          address: pickupAddress,
          lat: pickupLat.toDouble(),
          lng: pickupLng.toDouble(),
        ),
      );
    }
    if (dropoffLat != null && dropoffLng != null) {
      read(rideSearchProvider.notifier).setLocation(
        RideSearchField.destination,
        RideLocation(
          name: dropoffAddress.isNotEmpty ? dropoffAddress : 'Destination',
          address: dropoffAddress,
          lat: dropoffLat.toDouble(),
          lng: dropoffLng.toDouble(),
        ),
      );
    }

    // Map the live tracking phase from the current backend status.
    switch (status) {
      case 'driver_en_route':
        read(rideArrivalAnchorProvider.notifier).state = null;
        read(rideTrackingPhaseProvider.notifier).state =
            RideTrackingPhase.enRoute;
      case 'arrived_at_pickup' || 'arrived':
        final arrivedAt = _dateFromJson(
          json['arrivedAtPickupAt'] ?? json['statusChangedAt'],
        );
        read(rideArrivalAnchorProvider.notifier).state =
            arrivedAt ?? read(rideArrivalAnchorProvider) ?? DateTime.now();
        read(rideTrackingPhaseProvider.notifier).state =
            RideTrackingPhase.arrived;
      case 'in_progress':
        read(rideTrackingPhaseProvider.notifier).state =
            RideTrackingPhase.inProgress;
    }
    // Backend's RideSnapshot serves driver coords as currentLat/currentLng
    // (see apps/api/src/modules/ride/ride-snapshot.service.ts). Keep the
    // older aliases as defensive fallbacks.
    final dLat =
        (driver['currentLat'] ?? driver['latitude'] ?? driver['lat']) as num?;
    final dLng =
        (driver['currentLng'] ?? driver['longitude'] ?? driver['lng']) as num?;
    if (dLat != null && dLng != null) {
      read(liveDriverPositionProvider.notifier).state = LiveDriverPosition(
        latitude: dLat.toDouble(),
        longitude: dLng.toDouble(),
        updatedAt: DateTime.now(),
      );
    }
  } on ApiException catch (e) {
    developer.log(
      'REST fallback hydrate failed (status=${e.statusCode}, '
      'code=${e.errorCode ?? 'unknown'})',
      name: 'RideProvider',
      level: 800,
    );
  } catch (e) {
    developer.log(
      'REST fallback hydrate failed with ${e.runtimeType}',
      name: 'RideProvider',
      level: 800,
    );
  }
}

bool _isNoDriversTerminal(
  String status, {
  String? reason,
  String? cancelledBy,
}) {
  final normalizedStatus = status.toLowerCase();
  final normalizedReason = (reason ?? '').toLowerCase();
  final normalizedCancelledBy = (cancelledBy ?? '').toLowerCase();

  return normalizedStatus == 'no_drivers' ||
      normalizedStatus == 'no_driver' ||
      normalizedReason == 'no_drivers_available' ||
      normalizedReason == 'no_driver_available' ||
      normalizedReason == 'no_drivers' ||
      normalizedCancelledBy == 'system';
}

/// Cancel an in-flight ride request from the matching screen. Local state is
/// reset only after the API response or a read-back proves the backend row is
/// cancelled; otherwise the caller must keep the ride visible.
Future<bool> cancelInFlightRideRequest(ProviderContainer ref) async {
  final rideId = ref.read(activeRideIdProvider);
  if (rideId != null && rideId.isNotEmpty) {
    final cancellation = await cancelRideWithAuthority(
      rideService: ref.read(rideServiceProvider),
      rideId: rideId,
      reason: 'rider_cancelled_during_search',
    );
    if (!cancellation.confirmedCancelled) {
      developer.log(
        'cancelRide not confirmed; local matching state preserved '
        '(reconciled=${cancellation.reconciled})',
        name: 'RideProvider',
        level: 900,
      );
      ref.read(bookingFailureMessageProvider.notifier).state =
          cancellation.message;
      return false;
    }
    await ref.read(rideBookingAttemptStoreProvider).clear();
  }
  ref.read(activeRideIdProvider.notifier).state = null;
  ref.read(matchedDriverProvider.notifier).state = null;
  ref.read(bookingFailureMessageProvider.notifier).state = null;
  ref.read(driversNotifiedProvider.notifier).state = 0;
  ref.read(matcherProgressProvider.notifier).state = null;
  ref.read(liveDriverPositionProvider.notifier).state = null;
  ref.read(rideArrivalAnchorProvider.notifier).state = null;
  ref.read(bookingPhaseProvider.notifier).reset();
  return true;
}

DateTime? _dateFromJson(dynamic value) {
  if (value is DateTime) return value;
  if (value is String && value.isNotEmpty) return DateTime.tryParse(value);
  return null;
}

/// Tries the wire shapes the backend has used for ride-create responses:
///   { id }            ← canonical
///   { rideId }        ← older naming
///   { ride: { id } }  ← when the controller wraps the entity
String? _extractRideId(Map<String, dynamic> result) {
  final direct = result['id'];
  if (direct is String && direct.isNotEmpty) return direct;

  final rideIdKey = result['rideId'];
  if (rideIdKey is String && rideIdKey.isNotEmpty) return rideIdKey;

  final nested = result['ride'];
  if (nested is Map<String, dynamic>) {
    final nestedId = nested['id'];
    if (nestedId is String && nestedId.isNotEmpty) return nestedId;
  }

  return null;
}
