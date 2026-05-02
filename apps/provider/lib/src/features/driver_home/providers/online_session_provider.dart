import 'dart:async';
import 'dart:developer' as developer;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_models/shared_models.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/providers/provider_status_provider.dart';

/// Tracks how long the driver has been online today.
///
/// Backend's `GET /payments/earnings` doesn't return hours-online, so the
/// accumulation lives client-side. The contract:
///   - When [providerStatusProvider] flips from `offline` → `online`/`busy`,
///     we stamp the moment in memory.
///   - When it flips back to `offline`, the elapsed seconds get added to
///     a per-day counter persisted in [SharedPreferences] under
///     `driver_online_seconds_<yyyy-MM-dd>`. Per-day buckets so the count
///     resets cleanly at midnight without us having to clear anything.
///   - While online, the live ticker emits `persisted + (now - sessionStart)`
///     every second so the home-screen "HOURS" stat counts up in real time.
///
/// Caveats:
///   - We don't run a background isolate. If the OS kills the app while
///     the driver is online, the session up to that point is lost. Backend
///     would need to own this for a perfect reading.
///   - Day rollover at midnight while still online: the ticker keeps the
///     full session against today's bucket; on next offline transition we
///     write to whichever day is current. That's a small over-count for
///     the new day on the boundary, which is acceptable.

/// `prefs` instance, opened once.
final _prefsProvider = FutureProvider<SharedPreferences>(
  (_) => SharedPreferences.getInstance(),
);

/// Records the moment the current online session started, in
/// `DateTime.now().millisecondsSinceEpoch`. Null while offline.
final onlineSessionStartProvider = StateProvider<int?>((_) => null);

String _dayKey(DateTime now) {
  final d = now;
  final m = d.month.toString().padLeft(2, '0');
  final dd = d.day.toString().padLeft(2, '0');
  return 'driver_online_seconds_${d.year}-$m-$dd';
}

/// Subscribes to provider-status changes and updates the persisted
/// per-day counter on every offline transition. Activated by the driver
/// shell so it lives for the app's lifetime.
final onlineSessionRecorderProvider = Provider<void>((ref) {
  ref.listen<DriverStatus>(providerStatusProvider, (prev, next) async {
    final wasOnline = prev != null &&
        (prev == DriverStatus.online || prev == DriverStatus.busy);
    final isOnline = next == DriverStatus.online || next == DriverStatus.busy;

    if (!wasOnline && isOnline) {
      ref.read(onlineSessionStartProvider.notifier).state =
          DateTime.now().millisecondsSinceEpoch;
      return;
    }

    if (wasOnline && !isOnline) {
      final startMs = ref.read(onlineSessionStartProvider);
      ref.read(onlineSessionStartProvider.notifier).state = null;
      if (startMs == null) return;
      final elapsedSecs =
          ((DateTime.now().millisecondsSinceEpoch - startMs) / 1000)
              .round()
              .clamp(0, 24 * 60 * 60);
      try {
        final prefs = await ref.read(_prefsProvider.future);
        final key = _dayKey(DateTime.now());
        final current = prefs.getInt(key) ?? 0;
        await prefs.setInt(key, current + elapsedSecs);
        developer.log(
          'session ended — added ${elapsedSecs}s to $key (total ${current + elapsedSecs}s)',
          name: 'OnlineSession',
        );
      } catch (e) {
        developer.log('failed to persist online session: $e',
            name: 'OnlineSession', level: 800);
      }
    }
  }, fireImmediately: true);
});

/// Live ticker — emits the running total of seconds online today every
/// second while online, otherwise emits the persisted value once.
///
/// Returns total seconds; the UI converts to a "Xh Ym" label.
final onlineSecondsTodayProvider = StreamProvider<int>((ref) async* {
  final prefs = await ref.watch(_prefsProvider.future);
  // Re-emit whenever the session start flips (online ↔ offline) so the
  // stream picks up "I just went online".
  final startMs = ref.watch(onlineSessionStartProvider);
  final key = _dayKey(DateTime.now());
  final base = prefs.getInt(key) ?? 0;

  if (startMs == null) {
    yield base;
    return;
  }
  while (true) {
    final live = ((DateTime.now().millisecondsSinceEpoch - startMs) / 1000)
        .round()
        .clamp(0, 24 * 60 * 60);
    yield base + live;
    await Future<void>.delayed(const Duration(seconds: 1));
  }
});

/// Synchronous fallback for screens that just want a number — folds the
/// stream's loading/error states into 0. Mirrors `onlineSecondsTodayProvider`
/// without forcing every consumer to handle [AsyncValue].
final onlineSecondsTodayValueProvider = Provider<int>((ref) {
  return ref.watch(onlineSecondsTodayProvider).maybeWhen(
        data: (s) => s,
        orElse: () => 0,
      );
});

/// Format seconds as "Xh Ym" / "Ym" / "Xh".
String formatOnlineSeconds(int seconds) {
  if (seconds <= 0) return '0m';
  final hours = seconds ~/ 3600;
  final minutes = (seconds % 3600) ~/ 60;
  if (hours == 0) return '${minutes}m';
  if (minutes == 0) return '${hours}h';
  return '${hours}h ${minutes}m';
}
