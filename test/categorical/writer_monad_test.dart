import 'package:flutter_test/flutter_test.dart';
import 'package:tech_world/events/types.dart';

/// Writer monad (WithEvents) law tests.
///
/// `WithEvents<T> = (T, List<AppEvent>)` is a Writer monad where:
///   - M = `List<AppEvent>` (the monoid, under concatenation)
///   - `pure(a) = (a, [])`
///   - `bind((a, w), f) = let (b, w') = f(a) in (b, w + w')`
///
/// Laws tested:
///   1. Left unit:  pure(a) >>= f  ==  f(a)
///   2. Right unit: m >>= pure     ==  m
///   3. Associativity: (m >>= f) >>= g  ==  m >>= (x => f(x) >>= g)
///   4. Event accumulation: events from all steps are preserved

/// Pure: lift a value into the Writer monad with empty event log.
WithEvents<T> pure<T>(T value) => (value, <AppEvent>[]);

/// Bind: Kleisli composition for the Writer monad.
WithEvents<B> bind<A, B>(
  WithEvents<A> m,
  WithEvents<B> Function(A) f,
) {
  final (a, w1) = m;
  final (b, w2) = f(a);
  return (b, [...w1, ...w2]);
}

void main() {
  // Use concrete AppEvent subclasses from the codebase.
  final event1 = PlayerMoved(
    destX: 1,
    destY: 2,
    timestamp: DateTime(2025, 1, 1),
  );
  final event2 = TerminalOpened(
    challengeId: 'test_challenge',
    terminalX: 3,
    terminalY: 4,
    timestamp: DateTime(2025, 1, 2),
  );
  final event3 = TerminalClosed(timestamp: DateTime(2025, 1, 3));

  // Kleisli arrows for testing.
  WithEvents<int> f(int x) => (x + 1, [event1]);
  WithEvents<String> g(int x) => ('result_$x', [event2]);
  group('Writer monad (WithEvents<T>) laws', () {
    test('left unit: pure(a) >>= f == f(a)', () {
      const a = 42;
      final lhs = bind(pure(a), f);
      final rhs = f(a);

      expect(lhs.$1, equals(rhs.$1), reason: 'Values must match');
      expect(lhs.$2.length, equals(rhs.$2.length),
          reason: 'Event counts must match');
    });

    test('right unit: m >>= pure == m', () {
      final m = (42, <AppEvent>[event1, event2]);
      final result = bind(m, pure<int>);

      expect(result.$1, equals(m.$1), reason: 'Value must be preserved');
      expect(result.$2.length, equals(m.$2.length),
          reason: 'Event count must be preserved');
    });

    test('associativity: (m >>= f) >>= g == m >>= (x => f(x) >>= g)', () {
      final m = pure(10);

      // Left association
      final lhs = bind(bind(m, f), g);

      // Right association
      final rhs = bind(m, (int x) => bind(f(x), g));

      expect(lhs.$1, equals(rhs.$1), reason: 'Values must match');
      expect(lhs.$2.length, equals(rhs.$2.length),
          reason: 'Event counts must match');
      // Both should have event1 then event2
      expect(lhs.$2.length, 2);
    });

    test('event accumulation: events from all steps are preserved', () {
      final m = (10, <AppEvent>[event1]);
      WithEvents<int> step1(int x) => (x * 2, [event2]);
      WithEvents<String> step2(int x) => ('done_$x', [event3]);

      final result = bind(bind(m, step1), step2);

      expect(result.$1, equals('done_20'));
      expect(result.$2.length, equals(3),
          reason: 'All 3 events from m, step1, step2');
      expect(result.$2[0], same(event1));
      expect(result.$2[1], same(event2));
      expect(result.$2[2], same(event3));
    });

    test('monoid identity: empty event list is identity for concatenation', () {
      final m = (42, <AppEvent>[event1]);
      final result = bind(m, (int x) => pure(x));

      expect(result.$2, hasLength(1));
      expect(result.$2[0], same(event1));
    });

    test('monoid associativity: event list concatenation is associative', () {
      final a = <AppEvent>[event1];
      final b = <AppEvent>[event2];
      final c = <AppEvent>[event3];

      final lhs = [...[...a, ...b], ...c];
      final rhs = [...a, ...[...b, ...c]];

      expect(lhs.length, equals(rhs.length));
      for (var i = 0; i < lhs.length; i++) {
        expect(lhs[i], same(rhs[i]));
      }
    });
  });
}
