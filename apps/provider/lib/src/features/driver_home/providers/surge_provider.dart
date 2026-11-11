import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/di/providers.dart';
import '../../../core/providers/app_lifecycle_provider.dart';
import '../../auth/providers/auth_controller.dart';
import '../data/surge_areas_service.dart';

/// Socket invalidations request fresh authority; they never paint stale payloads.
final surgeAreasRevisionProvider = StateProvider<int>((_) => 0);
final surgeAreasServiceProvider =
    Provider((ref) => SurgeAreasService(ref.watch(dioProvider)));
final surgeAreasProvider =
    StateNotifierProvider.autoDispose<SurgeAreasNotifier, List<SurgeMapArea>>(
        (ref) {
  final foregrounded = ref.watch(appForegroundedProvider);
  final session = ref.watch(currentAuthSessionIdentityProvider);
  final notifier = SurgeAreasNotifier(
    load: ref.read(surgeAreasServiceProvider).fetch,
    enabled: foregrounded && session != null,
  );
  ref.listen<int>(surgeAreasRevisionProvider, (_, __) => notifier.refresh());
  return notifier;
});

class SurgeAreasNotifier extends StateNotifier<List<SurgeMapArea>> {
  SurgeAreasNotifier(
      {required this.load, this.enabled = true, DateTime Function()? now})
      : now = now ?? DateTime.now,
        super(const []) {
    if (!enabled) return;
    _initial = Timer(Duration.zero, refresh);
    _refreshTimer =
        Timer.periodic(const Duration(seconds: 10), (_) => refresh());
    _expiryTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      final active =
          state.where((area) => area.expiresAt.isAfter(this.now())).toList();
      if (active.length != state.length) {
        state = active;
        unawaited(refresh());
      }
    });
  }
  final Future<List<SurgeMapArea>> Function() load;
  final bool enabled;
  final DateTime Function() now;
  Timer? _initial;
  Timer? _refreshTimer;
  Timer? _expiryTimer;
  bool _loading = false;
  bool _refreshAgain = false;

  Future<void> refresh() async {
    if (!mounted || !enabled) return;
    if (_loading) {
      _refreshAgain = true;
      return;
    }
    _loading = true;
    try {
      final areas = await load();
      if (mounted && !_refreshAgain) {
        state = areas.where((area) => area.expiresAt.isAfter(now())).toList();
      }
    } catch (_) {
      // Retain only still-valid authority; the expiry timer clears it even
      // during an outage or when an older backend has no area endpoint yet.
      if (mounted) {
        state = state.where((area) => area.expiresAt.isAfter(now())).toList();
      }
    } finally {
      _loading = false;
      if (mounted && _refreshAgain) {
        _refreshAgain = false;
        unawaited(refresh());
      }
    }
  }

  @override
  void dispose() {
    _initial?.cancel();
    _refreshTimer?.cancel();
    _expiryTimer?.cancel();
    super.dispose();
  }
}
