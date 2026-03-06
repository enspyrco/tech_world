import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:tech_world/map_editor/crdt/cell_version_map.dart';
import 'package:tech_world/map_editor/crdt/map_edit_op.dart';

void main() {
  late CellVersionMap vmap;

  setUp(() {
    vmap = CellVersionMap();
  });

  group('shouldApply', () {
    test('accepts first write to a cell', () {
      const op = MapEditOp(
        playerId: 'alice',
        counter: 1,
        x: 0,
        y: 0,
        layer: OpLayer.structure,
        newValue: 'barrier',
      );
      expect(vmap.shouldApply(op), isTrue);
    });

    test('accepts higher counter', () {
      const first = MapEditOp(
        playerId: 'alice',
        counter: 1,
        x: 0,
        y: 0,
        layer: OpLayer.structure,
        newValue: 'barrier',
      );
      const second = MapEditOp(
        playerId: 'bob',
        counter: 2,
        x: 0,
        y: 0,
        layer: OpLayer.structure,
        newValue: null,
      );

      vmap.record(first);
      expect(vmap.shouldApply(second), isTrue);
    });

    test('rejects lower counter', () {
      const first = MapEditOp(
        playerId: 'alice',
        counter: 5,
        x: 0,
        y: 0,
        layer: OpLayer.structure,
        newValue: 'barrier',
      );
      const second = MapEditOp(
        playerId: 'bob',
        counter: 3,
        x: 0,
        y: 0,
        layer: OpLayer.structure,
        newValue: null,
      );

      vmap.record(first);
      expect(vmap.shouldApply(second), isFalse);
    });

    test('breaks ties by playerId (lexicographic)', () {
      const opAlice = MapEditOp(
        playerId: 'alice',
        counter: 5,
        x: 0,
        y: 0,
        layer: OpLayer.structure,
        newValue: 'barrier',
      );
      const opBob = MapEditOp(
        playerId: 'bob',
        counter: 5,
        x: 0,
        y: 0,
        layer: OpLayer.structure,
        newValue: null,
      );

      // alice wins first (no prior version).
      vmap.record(opAlice);

      // bob > alice lexicographically, so bob wins the tie.
      expect(vmap.shouldApply(opBob), isTrue);

      vmap.record(opBob);

      // alice < bob, so alice loses the tie.
      expect(vmap.shouldApply(opAlice), isFalse);
    });

    test('different layers are independent', () {
      const structOp = MapEditOp(
        playerId: 'alice',
        counter: 5,
        x: 0,
        y: 0,
        layer: OpLayer.structure,
        newValue: 'barrier',
      );
      const floorOp = MapEditOp(
        playerId: 'bob',
        counter: 1,
        x: 0,
        y: 0,
        layer: OpLayer.floor,
        newValue: {'tilesetId': 'x', 'tileIndex': 1},
      );

      vmap.record(structOp);
      // Floor layer at (0,0) has no version, so counter=1 should win.
      expect(vmap.shouldApply(floorOp), isTrue);
    });
  });

  group('serialization', () {
    test('toJson/loadFromJson round-trip', () {
      const op1 = MapEditOp(
        playerId: 'alice',
        counter: 3,
        x: 1,
        y: 2,
        layer: OpLayer.structure,
      );
      const op2 = MapEditOp(
        playerId: 'bob',
        counter: 5,
        x: 3,
        y: 4,
        layer: OpLayer.floor,
      );
      vmap.record(op1);
      vmap.record(op2);

      final json = vmap.toJson();
      final restored = CellVersionMap();
      restored.loadFromJson(json);

      expect(restored.versionAt(1, 2, OpLayer.structure), (3, 'alice'));
      expect(restored.versionAt(3, 4, OpLayer.floor), (5, 'bob'));
    });
  });

  group('convergence fuzz test', () {
    test('all orderings produce identical version maps', () {
      // Generate 50 random ops across 3 players with unique counters.
      // In a real system, each player's counter is monotonically increasing,
      // so (playerId, counter) pairs are unique.
      final genRng = Random(42);
      final players = ['alice', 'bob', 'charlie'];
      final counters = {'alice': 0, 'bob': 0, 'charlie': 0};
      final ops = <MapEditOp>[];

      for (var i = 0; i < 50; i++) {
        final player = players[genRng.nextInt(3)];
        counters[player] = counters[player]! + 1;
        ops.add(MapEditOp(
          playerId: player,
          counter: counters[player]!,
          x: genRng.nextInt(10),
          y: genRng.nextInt(10),
          layer: OpLayer.values[genRng.nextInt(OpLayer.values.length)],
          newValue: genRng.nextBool() ? 'barrier' : null,
        ));
      }

      // Apply in 10 random orderings and record final state.
      CellVersionMap? reference;
      for (var trial = 0; trial < 10; trial++) {
        final shuffleRng = Random(trial * 1000);
        final shuffled = List<MapEditOp>.from(ops)..shuffle(shuffleRng);
        final vm = CellVersionMap();
        for (final op in shuffled) {
          if (vm.shouldApply(op)) {
            vm.record(op);
          }
        }

        if (reference == null) {
          reference = vm;
        } else {
          // Compare all tracked cells.
          final refJson = reference.toJson();
          final trialJson = vm.toJson();
          expect(
            trialJson,
            equals(refJson),
            reason: 'Trial $trial diverged from reference',
          );
        }
      }
    });

    test('convergence with value tracking', () {
      // Ensure all orderings produce the same winning values.
      // Use unique (playerId, counter) pairs as real Lamport clocks would.
      final genRng = Random(123);
      final players = ['p1', 'p2', 'p3'];
      final counters = {'p1': 0, 'p2': 0, 'p3': 0};
      final ops = <MapEditOp>[];

      for (var i = 0; i < 50; i++) {
        final player = players[genRng.nextInt(3)];
        counters[player] = counters[player]! + 1;
        final value = 'v${genRng.nextInt(10)}';
        ops.add(MapEditOp(
          playerId: player,
          counter: counters[player]!,
          x: genRng.nextInt(5),
          y: genRng.nextInt(5),
          layer: OpLayer.structure,
          newValue: value,
        ));
      }

      // Track winning values per cell.
      Map<(int, int, OpLayer), dynamic>? referenceValues;

      for (var trial = 0; trial < 10; trial++) {
        final shuffleRng = Random(trial * 1000);
        final shuffled = List<MapEditOp>.from(ops)..shuffle(shuffleRng);
        final vm = CellVersionMap();
        final values = <(int, int, OpLayer), dynamic>{};

        for (final op in shuffled) {
          if (vm.shouldApply(op)) {
            vm.record(op);
            values[(op.x, op.y, op.layer)] = op.newValue;
          }
        }

        if (referenceValues == null) {
          referenceValues = values;
        } else {
          expect(
            values,
            equals(referenceValues),
            reason: 'Trial $trial values diverged',
          );
        }
      }
    });
  });
}
