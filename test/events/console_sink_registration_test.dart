import 'package:flutter_test/flutter_test.dart';
import 'package:tech_world/events/sinks/console_sink.dart';

void main() {
  group('consoleSinkEnabledFor (claude-tasks#4472)', () {
    // The real call site is `consoleSinkEnabledFor(debug: kDebugMode, web:
    // kIsWeb)`, and BOTH arguments are compile-time constants — `flutter test`
    // only ever runs debug-native, so a test can never observe the guard from
    // the outside. The mode it would need to run in is the mode that cannot
    // host the test. Passing the flags in is the only level at which the
    // release-web case is checkable at all. Same split as `Autopilot.allowedIn`.

    test('release WEB registers the console sink — the gap this closes', () {
      expect(consoleSinkEnabledFor(debug: false, web: true), isTrue,
          reason: 'web has no file sink (no app-documents dir in a browser), '
              'so without the console a release web client has NO sink and '
              'every _log.* call goes nowhere');
    });

    test('release NATIVE does not — the file sinks are its record', () {
      expect(consoleSinkEnabledFor(debug: false, web: false), isFalse,
          reason: 'native release keeps its durable record in events.jsonl; '
              'adding a console there would be noise, not observability');
    });

    test('debug registers on both platforms', () {
      expect(consoleSinkEnabledFor(debug: true, web: false), isTrue);
      expect(consoleSinkEnabledFor(debug: true, web: true), isTrue);
    });

    test('the matrix is total — all four combinations are pinned', () {
      // Guards against a future edit that makes one arm depend on something
      // not passed in: every input pair must still produce a decision here.
      final seen = <String, bool>{};
      for (final d in [true, false]) {
        for (final w in [true, false]) {
          seen['debug=$d,web=$w'] = consoleSinkEnabledFor(debug: d, web: w);
        }
      }
      expect(seen, hasLength(4));
      expect(seen.values.where((v) => v).length, 3,
          reason: 'exactly one combination (release native) declines');
    });
  });
}
