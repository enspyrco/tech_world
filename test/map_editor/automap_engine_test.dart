import 'package:flutter_test/flutter_test.dart';
import 'package:tech_world/flame/tiles/tile_ref.dart';
import 'package:tech_world/map_editor/automap_engine.dart';
import 'package:tech_world/map_editor/automap_rule.dart';
import 'package:tech_world/map_editor/map_editor_state.dart';

void main() {
  const shadowTile = TileRef(tilesetId: 'test', tileIndex: 42);
  const trimTile = TileRef(tilesetId: 'test', tileIndex: 99);

  const shadowRule = AutomapRule(
    id: 'shadow',
    name: 'Shadow',
    conditions: [
      AutomapCondition(dx: 0, dy: 0, structureType: TileType.open),
      AutomapCondition(dx: 0, dy: -1, structureType: TileType.barrier),
    ],
    output: AutomapOutput(targetLayer: 'object', tile: shadowTile),
    priority: 10,
  );

  const trimRule = AutomapRule(
    id: 'trim',
    name: 'Trim',
    conditions: [
      AutomapCondition(dx: 0, dy: 0, structureType: TileType.barrier),
      AutomapCondition(dx: 0, dy: -1, structureType: TileType.open),
    ],
    output: AutomapOutput(targetLayer: 'object', tile: trimTile),
    priority: 5,
  );

  TileType allOpen(int x, int y) => TileType.open;
  TileRef? noObjects(int x, int y) => null;

  group('evaluateRules', () {
    test('places shadow tile below a barrier', () {
      // Barrier at (10, 4), everything else open.
      TileType structure(int x, int y) {
        if (x == 10 && y == 4) return TileType.barrier;
        return TileType.open;
      }

      final result = evaluateRules(
        rules: [shadowRule],
        structureAt: structure,
        objectTileAt: noObjects,
      );

      expect(result.placements[(10, 5)], shadowTile);
      expect(result.affectedCells, contains((10, 5)));
    });

    test('does not place tile when conditions do not match', () {
      // All open — no barrier above any cell.
      final result = evaluateRules(
        rules: [shadowRule],
        structureAt: allOpen,
        objectTileAt: noObjects,
      );

      expect(result.placements, isEmpty);
      expect(result.affectedCells, isEmpty);
    });

    test('higher priority rule wins on conflict', () {
      // Two rules that match the same cell — higher priority should win.
      const tileA = TileRef(tilesetId: 'test', tileIndex: 1);
      const tileB = TileRef(tilesetId: 'test', tileIndex: 2);

      const ruleA = AutomapRule(
        id: 'a',
        name: 'A',
        conditions: [
          AutomapCondition(dx: 0, dy: 0, structureType: TileType.open),
        ],
        output: AutomapOutput(targetLayer: 'object', tile: tileA),
        priority: 20,
      );
      const ruleB = AutomapRule(
        id: 'b',
        name: 'B',
        conditions: [
          AutomapCondition(dx: 0, dy: 0, structureType: TileType.open),
        ],
        output: AutomapOutput(targetLayer: 'object', tile: tileB),
        priority: 10,
      );

      final result = evaluateRules(
        rules: [ruleB, ruleA], // deliberately disordered
        structureAt: allOpen,
        objectTileAt: noObjects,
      );

      // ruleA (priority 20) should win everywhere.
      expect(result.placements[(0, 0)]!.tileIndex, 1);
    });

    test('both rules produce placements on different cells', () {
      // Barrier at (5, 4) in a field of open tiles.
      TileType structure(int x, int y) {
        if (x == 5 && y == 4) return TileType.barrier;
        return TileType.open;
      }

      final result = evaluateRules(
        rules: [trimRule, shadowRule],
        structureAt: structure,
        objectTileAt: noObjects,
      );

      // Shadow at (5, 5) — open cell with barrier above.
      expect(result.placements[(5, 5)], shadowTile);
      // Trim at (5, 4) — barrier cell with open above.
      expect(result.placements[(5, 4)], trimTile);
    });

    test('respects isEmpty: true condition', () {
      const rule = AutomapRule(
        id: 'needs_empty',
        name: 'Needs Empty',
        conditions: [
          AutomapCondition(dx: 0, dy: 0, structureType: TileType.open),
          AutomapCondition(dx: 0, dy: 0, isEmpty: true),
        ],
        output: AutomapOutput(
          targetLayer: 'object',
          tile: TileRef(tilesetId: 'test', tileIndex: 50),
        ),
        priority: 10,
      );

      // Cell (3, 3) already has an object tile.
      TileRef? objectAt(int x, int y) {
        if (x == 3 && y == 3) {
          return const TileRef(tilesetId: 'existing', tileIndex: 0);
        }
        return null;
      }

      final result = evaluateRules(
        rules: [rule],
        structureAt: allOpen,
        objectTileAt: objectAt,
      );

      // (3, 3) should NOT be placed because it's not empty.
      expect(result.placements.containsKey((3, 3)), isFalse);
      // (0, 0) should be placed because it IS empty.
      expect(result.placements.containsKey((0, 0)), isTrue);
    });

    test('respects isEmpty: false condition', () {
      const rule = AutomapRule(
        id: 'needs_occupied',
        name: 'Needs Occupied',
        conditions: [
          AutomapCondition(dx: 0, dy: 0, isEmpty: false),
        ],
        output: AutomapOutput(
          targetLayer: 'object',
          tile: TileRef(tilesetId: 'test', tileIndex: 60),
        ),
        priority: 10,
      );

      TileRef? objectAt(int x, int y) {
        if (x == 7 && y == 7) {
          return const TileRef(tilesetId: 'existing', tileIndex: 0);
        }
        return null;
      }

      final result = evaluateRules(
        rules: [rule],
        structureAt: allOpen,
        objectTileAt: objectAt,
      );

      // Only (7, 7) has an object tile → only it matches.
      expect(result.placements.containsKey((7, 7)), isTrue);
      expect(result.placements.containsKey((0, 0)), isFalse);
    });

    test('returns empty result for empty rules list', () {
      final result = evaluateRules(
        rules: [],
        structureAt: allOpen,
        objectTileAt: noObjects,
      );

      expect(result.placements, isEmpty);
      expect(result.affectedCells, isEmpty);
    });

    test('handles edge cells correctly (barrier at row 0)', () {
      // Barrier at (0, 0). Shadow should appear at (0, 1), not crash.
      TileType structure(int x, int y) {
        if (x == 0 && y == 0) return TileType.barrier;
        return TileType.open;
      }

      final result = evaluateRules(
        rules: [shadowRule],
        structureAt: structure,
        objectTileAt: noObjects,
      );

      // (0, 1) is open and has barrier above at (0, 0) → shadow placed.
      expect(result.placements[(0, 1)], shadowTile);
      // (0, 0) is barrier, not open → no shadow here.
      expect(result.placements.containsKey((0, 0)), isFalse);
    });

    test('no shadow placed at row 0 (nothing above is barrier)', () {
      // All cells open — checking row 0 won't find a barrier at y=-1.
      final result = evaluateRules(
        rules: [shadowRule],
        structureAt: allOpen,
        objectTileAt: noObjects,
      );

      // Row 0 should have no placements (no barrier at y=-1).
      for (var x = 0; x < 50; x++) {
        expect(result.placements.containsKey((x, 0)), isFalse);
      }
    });
  });
}
