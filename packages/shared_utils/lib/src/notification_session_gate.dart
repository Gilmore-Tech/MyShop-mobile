import 'dart:async';

enum NotificationSessionPhase { restoring, authenticated, unavailable }

class NotificationSessionSnapshot<T> {
  const NotificationSessionSnapshot._(this.phase, this.session);

  const NotificationSessionSnapshot.restoring()
      : this._(NotificationSessionPhase.restoring, null);

  const NotificationSessionSnapshot.authenticated(T session)
      : this._(NotificationSessionPhase.authenticated, session);

  const NotificationSessionSnapshot.unavailable()
      : this._(NotificationSessionPhase.unavailable, null);

  final NotificationSessionPhase phase;
  final T? session;
}

/// Holds a cold-start notification intent until session restoration resolves.
///
/// Only bootstrap states are retried. An explicitly signed-out or incomplete
/// registration state is terminal, so a stale notification can never steer an
/// unauthenticated user into a protected screen.
Future<T?> waitForNotificationSession<T>({
  required NotificationSessionSnapshot<T> Function() probe,
  Duration timeout = const Duration(seconds: 20),
  Duration pollInterval = const Duration(milliseconds: 100),
}) async {
  final stopwatch = Stopwatch()..start();
  while (true) {
    final snapshot = probe();
    switch (snapshot.phase) {
      case NotificationSessionPhase.authenticated:
        return snapshot.session;
      case NotificationSessionPhase.unavailable:
        return null;
      case NotificationSessionPhase.restoring:
        if (stopwatch.elapsed >= timeout) return null;
        await Future<void>.delayed(pollInterval);
    }
  }
}
