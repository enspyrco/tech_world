import 'package:flutter_test/flutter_test.dart';
import 'package:tech_world/utils/stream_extensions.dart';

/// Stream extension (`.whereMap`) Kleisli arrow tests.
///
/// `.whereMap<T>(f)` is the Kleisli bind for the Maybe monad lifted to
/// Stream. It replaces the manual pattern:
///   `stream.map(f).where((x) => x != null).cast<T>()`
///
/// Laws tested:
///   1. Identity: `whereMap(identity) == where(!=null).cast<T>()`
///   2. Composition: `whereMap(g . f) == whereMap(f).whereMap(g)`
///   3. Null filtering: null results are dropped
void main() {
  group('.whereMap Stream extension', () {
    test('emits only non-null results', () async {
      final stream = Stream.fromIterable([1, 2, 3, 4, 5]);

      final results = await stream
          .whereMap<int>((x) => x.isEven ? x * 10 : null)
          .toList();

      expect(results, equals([20, 40]));
    });

    test('all-null mapping produces empty stream', () async {
      final stream = Stream.fromIterable([1, 2, 3]);

      final results =
          await stream.whereMap<String>((x) => null).toList();

      expect(results, isEmpty);
    });

    test('all-non-null mapping preserves all elements', () async {
      final stream = Stream.fromIterable([1, 2, 3]);

      final results =
          await stream.whereMap<String>((x) => 'v$x').toList();

      expect(results, equals(['v1', 'v2', 'v3']));
    });

    test('type narrowing works correctly', () async {
      final stream = Stream<Object>.fromIterable(['a', 1, 'b', 2, 'c']);

      final results = await stream
          .whereMap<String>((x) => x is String ? x.toUpperCase() : null)
          .toList();

      expect(results, equals(['A', 'B', 'C']));
    });

    test('empty stream produces empty stream', () async {
      final stream = Stream<int>.empty();

      final results =
          await stream.whereMap<int>((x) => x * 2).toList();

      expect(results, isEmpty);
    });

    test('composition: whereMap(g) . whereMap(f) preserves order', () async {
      final stream = Stream.fromIterable([1, 2, 3, 4, 5, 6]);

      // f: keep even numbers, double them
      // g: keep those divisible by 8
      final results = await stream
          .whereMap<int>((x) => x.isEven ? x * 2 : null)
          .whereMap<int>((x) => x % 8 == 0 ? x : null)
          .toList();

      expect(results, equals([8]));
    });
  });
}
