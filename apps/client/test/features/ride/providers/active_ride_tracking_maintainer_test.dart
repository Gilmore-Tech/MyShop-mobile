import 'package:api_client/api_client.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:myshop_client/src/core/di/providers.dart';
import 'package:myshop_client/src/core/providers/socket_provider.dart';
import 'package:myshop_client/src/features/ride/providers/ride_provider.dart';

class _Socket extends Mock implements SocketService {}

class _Rides extends Mock implements RideService {}

void main() {
  for (final phase in [
    RideTrackingPhase.enRoute,
    RideTrackingPhase.inProgress
  ]) {
    testWidgets('recovery runs during $phase and stops on disposal',
        (tester) async {
      final socket = _Socket();
      final rides = _Rides();
      when(() => socket.isConnected).thenReturn(true);
      when(() => rides.getRide('ride-a'))
          .thenAnswer((_) async => {'status': 'requested'});
      final container = ProviderContainer(overrides: [
        socketServiceProvider.overrideWithValue(socket),
        rideServiceProvider.overrideWithValue(rides),
      ]);
      container.read(activeRideIdProvider.notifier).state = 'ride-a';
      container.read(rideTrackingPhaseProvider.notifier).state = phase;
      final subscription =
          container.listen(activeRideTrackingMaintainerProvider, (_, __) {});
      await tester.pump();
      verify(() => socket.emit('client:track:ride', {'rideId': 'ride-a'}))
          .called(1);
      await tester.pump(
          Duration(seconds: phase == RideTrackingPhase.inProgress ? 5 : 12));
      verify(() => rides.getRide('ride-a')).called(1);
      subscription.close();
      await tester.pump();
      clearInteractions(socket);
      clearInteractions(rides);
      await tester.pump(const Duration(seconds: 30));
      verifyNever(() => rides.getRide(any()));
      verifyNever(() => socket.emit(any(), any()));
      container.dispose();
    });
  }
}
