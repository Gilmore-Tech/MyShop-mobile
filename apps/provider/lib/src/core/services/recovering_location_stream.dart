import 'dart:async';

/// Restarts a failed or unexpectedly closed native location subscription.
/// Cancellation also cancels pending restarts, so Offline/logout cannot leave
/// an orphan location service running. No permission prompts belong here.
Stream<T> recoveringLocationStream<T>(
  Stream<T> Function() open, {
  Duration initialDelay = const Duration(seconds: 2),
  Duration maxDelay = const Duration(seconds: 30),
}) {
  late StreamController<T> controller;
  StreamSubscription<T>? subscription;
  Timer? retry;
  var cancelled = false;
  var failures = 0;
  late void Function() start;

  Future<void> restart() async {
    final previous = subscription;
    subscription = null;
    await previous?.cancel();
    if (cancelled || retry != null) return;
    final delay = Duration(
      microseconds: (initialDelay.inMicroseconds * (1 << failures.clamp(0, 5)))
          .clamp(0, maxDelay.inMicroseconds),
    );
    failures++;
    retry = Timer(delay, () {
      retry = null;
      if (!cancelled) start();
    });
  }

  start = () {
    if (cancelled) return;
    try {
      subscription = open().listen(
        (value) {
          failures = 0;
          controller.add(value);
        },
        onError: (Object error, StackTrace stack) {
          controller.addError(error, stack);
          unawaited(restart());
        },
        onDone: () => unawaited(restart()),
        cancelOnError: false,
      );
    } catch (error, stack) {
      controller.addError(error, stack);
      unawaited(restart());
    }
  };
  controller = StreamController<T>(
    onListen: start,
    onCancel: () async {
      cancelled = true;
      retry?.cancel();
      await subscription?.cancel();
    },
  );
  return controller.stream;
}
