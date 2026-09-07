import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:myshop_provider/src/core/services/recovering_location_stream.dart';

void main() {
  test('native stream failure restarts and delivers fresh locations', () async {
    final first = StreamController<int>();
    final second = StreamController<int>();
    var opens = 0;
    var errors = 0;
    final positions = <int>[];
    final restarted = Completer<void>();
    final subscription = recoveringLocationStream(() {
      if (++opens == 1) return first.stream;
      restarted.complete();
      return second.stream;
    }, initialDelay: const Duration(milliseconds: 10))
        .listen(positions.add, onError: (Object _) => errors++);
    first.add(1);
    first.addError(StateError('native location service interrupted'));
    await restarted.future.timeout(const Duration(seconds: 2));
    expect(errors, 1);
    expect(opens, 2);
    second.add(2);
    await Future<void>.delayed(Duration.zero);
    expect(positions, [1, 2]);
    await subscription.cancel();
    await first.close();
    await second.close();
  });

  testWidgets('Offline cancellation prevents a pending restart',
      (tester) async {
    var opens = 0;
    final subscription = recoveringLocationStream<int>(() {
      opens++;
      return const Stream<int>.empty();
    }).listen((_) {});
    await tester.pump();
    await subscription.cancel();
    await tester.pump(const Duration(minutes: 1));
    expect(opens, 1);
  });
}
