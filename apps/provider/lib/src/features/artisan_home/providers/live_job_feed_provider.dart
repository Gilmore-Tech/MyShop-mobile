import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_models/shared_models.dart';

import '../../../core/di/providers.dart';
import '../../auth/providers/auth_controller.dart';

/// The backend resolves the current artisan account and township for every read.
final townshipJobFeedProvider =
    FutureProvider.autoDispose<List<LiveFeedJob>>((ref) {
  ref.watch(currentAuthSessionIdentityProvider);
  return ref.watch(jobServiceProvider).getLiveFeed();
});

final liveJobFeedProvider = Provider.autoDispose<List<LiveFeedJob>>((ref) {
  final feed = ref.watch(townshipJobFeedProvider);
  if (feed.isLoading || feed.hasError) return const [];
  return feed.valueOrNull ?? const [];
});
