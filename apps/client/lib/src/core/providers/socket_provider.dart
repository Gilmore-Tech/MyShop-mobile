import 'dart:developer' as developer;

import 'package:api_client/api_client.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/auth/providers/auth_controller.dart';
import '../../features/activity/providers/activity_provider.dart';
import '../../features/notifications/providers/notifications_provider.dart';
import '../../features/ride/providers/ride_provider.dart';
import '../../features/services/providers/bid_detail_provider.dart';
import '../di/providers.dart';
import 'nav_badge_provider.dart';

/// Provides the [SocketService] singleton for the client app.
final socketServiceProvider = Provider<SocketService>((ref) {
  final config = ref.watch(apiConfigProvider);
  final tokenStorage = ref.watch(appTokenStorageProvider);
  final service = SocketService(
    config: config,
    tokenStorage: tokenStorage,
  );
  ref.onDispose(service.dispose);
  return service;
});

/// Manages the Socket.IO connection lifecycle for the client app.
///
/// Automatically connects when the user is authenticated and disconnects
/// when they log out. Listens for real-time events and pushes updates
/// into the appropriate state providers.
final socketConnectionProvider = Provider<void>((ref) {
  final authState = ref.watch(clientAuthControllerProvider);
  final socket = ref.read(socketServiceProvider);

  if (authState is AuthAuthenticated) {
    _connectAndListen(ref, socket);
  } else {
    socket.disconnect();
  }
});

void _connectAndListen(Ref ref, SocketService socket) {
  socket.connect().then((_) {
    // ── Ride status updates ──────────────────────────────────────────────
    socket.on('ride:status', (data) {
      developer.log('Received ride:status event', name: 'WS');
      if (data is! Map<String, dynamic>) return;
      try {
        final status = data['status'] as String? ?? '';
        final driver =
            data['driver'] as Map<String, dynamic>? ?? <String, dynamic>{};

        switch (status) {
          case 'accepted' || 'driver_assigned':
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
              baseFarePesewas: (data['baseFare'] as num?)?.toInt() ?? 0,
              distanceFarePesewas:
                  (data['distanceFare'] as num?)?.toInt() ?? 0,
              distanceKm: (data['distanceKm'] as num?)?.toDouble() ?? 0,
              bookingFeePesewas: (data['bookingFee'] as num?)?.toInt() ?? 0,
              vehicleShortName: driver['vehicleShortName'] as String? ?? '',
              confirmedFarePesewas:
                  (data['totalFare'] as num?)?.toInt() ?? 0,
              paymentMethod: data['paymentMethod'] as String? ?? 'Cash',
            );
            ref.read(matchedDriverProvider.notifier).state = matched;
            ref.read(bookingPhaseProvider.notifier).driverFound();
            ref.read(rideMatchedViaSocketProvider.notifier).state = true;

          case 'en_route':
            ref.read(rideTrackingPhaseProvider.notifier).state =
                RideTrackingPhase.enRoute;

          case 'arrived':
            ref.read(rideTrackingPhaseProvider.notifier).state =
                RideTrackingPhase.arrived;

          case 'in_progress':
            ref.read(rideTrackingPhaseProvider.notifier).state =
                RideTrackingPhase.inProgress;

          case 'completed':
            // Ride completed — activity list should refresh
            if (ref.exists(activityNotifierProvider)) {
              ref.read(activityNotifierProvider.notifier).reload();
            }
            ref.read(navBadgeProvider.notifier).increment('/activity');

          case 'cancelled' || 'no_drivers':
            ref.read(bookingPhaseProvider.notifier).reset();
        }
      } catch (e) {
        developer.log('Failed to handle ride:status: $e',
            name: 'WS', level: 900);
      }
    });

    // ── Job status updates ───────────────────────────────────────────────
    socket.on('job:status', (data) {
      developer.log('Received job:status event', name: 'WS');
      try {
        if (ref.exists(activityNotifierProvider)) {
          ref.read(activityNotifierProvider.notifier).reload();
        }
        ref.read(navBadgeProvider.notifier).increment('/activity');
      } catch (e) {
        developer.log('Failed to handle job:status: $e',
            name: 'WS', level: 900);
      }
    });

    // ── Artisan confirmed a bid ──────────────────────────────────────────
    socket.on('job:artisan_confirmed', (data) {
      developer.log('Received job:artisan_confirmed event', name: 'WS');
      try {
        final etaLabel = data is Map<String, dynamic>
            ? data['etaLabel'] as String? ?? ''
            : '';
        if (ref.exists(bidDetailActionProvider)) {
          ref
              .read(bidDetailActionProvider.notifier)
              .onArtisanConfirmed(etaLabel: etaLabel);
        }
      } catch (e) {
        developer.log('Failed to handle job:artisan_confirmed: $e',
            name: 'WS', level: 900);
      }
    });

    // ── New bid on a job ─────────────────────────────────────────────────
    socket.on('job:bid_new', (data) {
      developer.log('Received job:bid_new event', name: 'WS');
      try {
        if (ref.exists(activityNotifierProvider)) {
          ref.read(activityNotifierProvider.notifier).reload();
        }
        ref.read(navBadgeProvider.notifier).increment('/activity');
      } catch (e) {
        developer.log('Failed to handle job:bid_new: $e',
            name: 'WS', level: 900);
      }
    });

    // ── New notification ─────────────────────────────────────────────────
    socket.on('notification:new', (data) {
      developer.log('Received notification:new event', name: 'WS');
      try {
        if (ref.exists(notifsProvider)) {
          ref.read(notifsProvider.notifier).reload();
        }
        ref.read(navBadgeProvider.notifier).increment('/profile');
      } catch (e) {
        developer.log('Failed to handle notification:new: $e',
            name: 'WS', level: 900);
      }
    });

    // ── Profile updated ──────────────────────────────────────────────────
    socket.on('profile:updated', (data) {
      developer.log('Received profile:updated event', name: 'WS');
      try {
        ref.read(clientAuthControllerProvider.notifier).refreshProfile();
      } catch (e) {
        developer.log('Failed to handle profile:updated: $e',
            name: 'WS', level: 900);
      }
    });
  });
}
