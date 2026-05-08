import 'package:flutter_test/flutter_test.dart';
import 'package:tech_world/map_editor/crdt/cell_version_map.dart';
import 'package:tech_world/map_editor/crdt/map_edit_op.dart';

/// CRDT (CellVersionMap) join-semilattice law tests.
///
/// LWW registers form a join-semilattice with merge = max(counter, playerId).
/// Laws:
///   1. Commutativity: merge(a, b) == merge(b, a)
///   2. Associativity: merge(a, merge(b, c)) == merge(merge(a, b), c)
///   3. Idempotence: merge(a, a) == a
///
/// These laws guarantee CRDT convergence: all clients applying the same
/// set of operations in any order arrive at the same state.
void main() {
  /// Build a MapEditOp for testing with the given playerId and counter.
  MapEditOp op({
    required String playerId,
    required int counter,
    int x = 0,
    int y = 0,
    OpLayer layer = OpLayer.floor,
  }) {
    return MapEditOp(
      playerId: playerId,
      counter: counter,
      x: x,
      y: y,
      layer: layer,
      newValue: 'test',
    );
  }

  /// Apply op to map and return the resulting version for the cell.
  (int, String) applyAndGet(CellVersionMap map, MapEditOp o) {
    if (map.shouldApply(o)) {
      map.record(o);
    }
    return map.versionAt(o.x, o.y, o.layer)!;
  }

  /// Merge two ops into a fresh CellVersionMap and return the winning version.
  (int, String) merge(MapEditOp a, MapEditOp b) {
    final map = CellVersionMap();
    applyAndGet(map, a);
    applyAndGet(map, b);
    return map.versionAt(a.x, a.y, a.layer)!;
  }

  group('CellVersionMap CRDT semilattice laws', () {
    test('commutativity: merge(a, b) == merge(b, a)', () {
      final a = op(playerId: 'alice', counter: 1);
      final b = op(playerId: 'bob', counter: 2);

      final ab = merge(a, b);
      final ba = merge(b, a);

      expect(ab, equals(ba), reason: 'merge must be commutative');
    });

    test('commutativity with same counter (tiebreak on playerId)', () {
      final a = op(playerId: 'alice', counter: 5);
      final b = op(playerId: 'bob', counter: 5);

      final ab = merge(a, b);
      final ba = merge(b, a);

      expect(ab, equals(ba), reason: 'tiebreak must be commutative');
      // 'bob' > 'alice' lexicographically, so bob wins
      expect(ab.$2, equals('bob'));
    });

    test('associativity: merge(a, merge(b, c)) == merge(merge(a, b), c)', () {
      final a = op(playerId: 'alice', counter: 1);
      final b = op(playerId: 'bob', counter: 3);
      final c = op(playerId: 'charlie', counter: 2);

      // Left association: merge(merge(a, b), c)
      final mapLeft = CellVersionMap();
      applyAndGet(mapLeft, a);
      applyAndGet(mapLeft, b);
      applyAndGet(mapLeft, c);
      final left = mapLeft.versionAt(0, 0, OpLayer.floor)!;

      // Right association: merge(a, merge(b, c))
      final mapRight = CellVersionMap();
      applyAndGet(mapRight, b);
      applyAndGet(mapRight, c);
      applyAndGet(mapRight, a);
      final right = mapRight.versionAt(0, 0, OpLayer.floor)!;

      expect(left, equals(right), reason: 'merge must be associative');
    });

    test('idempotence: merge(a, a) == a', () {
      final a = op(playerId: 'alice', counter: 5);

      final map = CellVersionMap();
      applyAndGet(map, a);
      final before = map.versionAt(0, 0, OpLayer.floor)!;

      // Apply same op again
      applyAndGet(map, a);
      final after = map.versionAt(0, 0, OpLayer.floor)!;

      expect(after, equals(before), reason: 'merge must be idempotent');
    });

    test('convergence: three orderings all agree', () {
      final ops = [
        op(playerId: 'alice', counter: 1),
        op(playerId: 'bob', counter: 3),
        op(playerId: 'charlie', counter: 2),
      ];

      // All 6 permutations of 3 ops
      final permutations = [
        [0, 1, 2],
        [0, 2, 1],
        [1, 0, 2],
        [1, 2, 0],
        [2, 0, 1],
        [2, 1, 0],
      ];

      final results = <(int, String)>[];
      for (final perm in permutations) {
        final map = CellVersionMap();
        for (final i in perm) {
          applyAndGet(map, ops[i]);
        }
        results.add(map.versionAt(0, 0, OpLayer.floor)!);
      }

      // All permutations must produce the same result
      for (var i = 1; i < results.length; i++) {
        expect(results[i], equals(results[0]),
            reason: 'Permutation $i must converge to same result as 0');
      }
    });
  });

  group('CellVersionMap round-trip (toJson/loadFromJson)', () {
    test('round-trip preserves all entries', () {
      final map = CellVersionMap();
      map.record(op(playerId: 'alice', counter: 1, x: 0, y: 0));
      map.record(
        op(
          playerId: 'bob',
          counter: 2,
          x: 3,
          y: 4,
          layer: OpLayer.terrain,
        ),
      );

      final json = map.toJson();
      final restored = CellVersionMap();
      restored.loadFromJson(json);

      expect(restored.versionAt(0, 0, OpLayer.floor), equals((1, 'alice')));
      expect(
        restored.versionAt(3, 4, OpLayer.terrain),
        equals((2, 'bob')),
      );
      expect(restored.length, equals(2));
    });

    test('loadFromJson skips unknown layers gracefully', () {
      final json = {
        '0,0,floor': [1, 'alice'],
        '1,1,hologram': [2, 'bob'], // Unknown layer
      };
      final map = CellVersionMap();
      map.loadFromJson(json);

      expect(map.length, equals(1));
      expect(map.versionAt(0, 0, OpLayer.floor), equals((1, 'alice')));
    });
  });
}
