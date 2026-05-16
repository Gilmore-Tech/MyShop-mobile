import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/di/providers.dart';

/// Lightweight view of the client's own received ratings — the average
/// stars + total count surfaced on the Profile header.
///
/// Backed by `GET /ratings/me`, which aggregates revealed ratings where
/// the caller is `ratee_id`. The blind 24-hour reveal window applies
/// here too: a fresh rating only shows up after both parties submit
/// (or the window elapses), so this stays empty for first-time clients
/// even right after a completed booking.
class MyRatingsSummary {
  const MyRatingsSummary({
    required this.average,
    required this.count,
  });

  /// Mean stars across revealed ratings — already rounded server-side
  /// to one decimal. `0` when [count] is zero.
  final double average;

  /// Number of revealed ratings the user has received.
  final int count;

  bool get hasRatings => count > 0;

  /// Display string with one decimal, e.g. `"4.8"`. Empty when [count]
  /// is zero so the UI can render a "New" pill instead of `0.0`.
  String get averageDisplay =>
      hasRatings ? average.toStringAsFixed(1) : '';
}

final myRatingsProvider = FutureProvider<MyRatingsSummary>((ref) async {
  final service = ref.watch(ratingServiceProvider);
  final data = await service.getMyRatings();
  final avg = (data['average'] as num?)?.toDouble() ?? 0.0;
  final count = (data['count'] as num?)?.toInt() ?? 0;
  return MyRatingsSummary(average: avg, count: count);
});
