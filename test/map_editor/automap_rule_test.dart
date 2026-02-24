import 'package:flutter_test/flutter_test.dart';
import 'package:tech_world/flame/tiles/tile_ref.dart';
import 'package:tech_world/map_editor/automap_rule.dart';
import 'package:tech_world/map_editor/map_editor_state.dart';

void main() {
  group('AutomapCondition', () {
    test('toJson/fromJson roundtrip with structureType', () {
      const condition = AutomapCondition(
        dx: 0,
        dy: -1,
        structureType: TileType.barrier,
      );

      final json = condition.toJson();
      final restored = AutomapCondition.fromJson(json);

      expect(restored.dx, 0);
      expect(restored.dy, -1);
      expect(restored.structureType, TileType.barrier);
      expect(restored.isEmpty, isNull);
    });

    test('toJson/fromJson roundtrip with isEmpty', () {
      const condition = AutomapCondition(
        dx: 1,
        dy: 0,
        isEmpty: true,
      );

      final json = condition.toJson();
      final restored = AutomapCondition.fromJson(json);

      expect(restored.dx, 1);
      expect(restored.dy, 0);
      expect(restored.structureType, isNull);
      expect(restored.isEmpty, true);
    });

    test('toJson/fromJson roundtrip with both fields', () {
      const condition = AutomapCondition(
        dx: -1,
        dy: 1,
        structureType: TileType.open,
        isEmpty: false,
      );

      final json = condition.toJson();
      final restored = AutomapCondition.fromJson(json);

      expect(restored.dx, -1);
      expect(restored.dy, 1);
      expect(restored.structureType, TileType.open);
      expect(restored.isEmpty, false);
    });

    test('toJson omits null fields', () {
      const condition = AutomapCondition(dx: 0, dy: 0);
      final json = condition.toJson();

      expect(json.containsKey('structureType'), isFalse);
      expect(json.containsKey('isEmpty'), isFalse);
      expect(json.containsKey('dx'), isTrue);
      expect(json.containsKey('dy'), isTrue);
    });

    test('equality', () {
      const a = AutomapCondition(dx: 0, dy: -1, structureType: TileType.open);
      const b = AutomapCondition(dx: 0, dy: -1, structureType: TileType.open);
      const c = AutomapCondition(dx: 1, dy: 0, structureType: TileType.open);

      expect(a, equals(b));
      expect(a, isNot(equals(c)));
    });
  });

  group('AutomapOutput', () {
    test('toJson/fromJson roundtrip', () {
      const output = AutomapOutput(
        targetLayer: 'object',
        tile: TileRef(tilesetId: 'my_tileset', tileIndex: 42),
      );

      final json = output.toJson();
      final restored = AutomapOutput.fromJson(json);

      expect(restored.targetLayer, 'object');
      expect(
        restored.tile,
        const TileRef(tilesetId: 'my_tileset', tileIndex: 42),
      );
    });

    test('equality', () {
      const a = AutomapOutput(
        targetLayer: 'object',
        tile: TileRef(tilesetId: 'test', tileIndex: 1),
      );
      const b = AutomapOutput(
        targetLayer: 'object',
        tile: TileRef(tilesetId: 'test', tileIndex: 1),
      );
      const c = AutomapOutput(
        targetLayer: 'floor',
        tile: TileRef(tilesetId: 'test', tileIndex: 1),
      );

      expect(a, equals(b));
      expect(a, isNot(equals(c)));
    });
  });

  group('AutomapRule', () {
    test('toJson/fromJson roundtrip', () {
      const rule = AutomapRule(
        id: 'test_rule',
        name: 'Test Rule',
        conditions: [
          AutomapCondition(dx: 0, dy: 0, structureType: TileType.open),
          AutomapCondition(dx: 0, dy: -1, structureType: TileType.barrier),
        ],
        output: AutomapOutput(
          targetLayer: 'object',
          tile: TileRef(tilesetId: 'tiles', tileIndex: 10),
        ),
        priority: 5,
      );

      final json = rule.toJson();
      final restored = AutomapRule.fromJson(json);

      expect(restored.id, 'test_rule');
      expect(restored.name, 'Test Rule');
      expect(restored.conditions.length, 2);
      expect(restored.conditions[0].structureType, TileType.open);
      expect(restored.conditions[1].dx, 0);
      expect(restored.conditions[1].dy, -1);
      expect(restored.conditions[1].structureType, TileType.barrier);
      expect(restored.output.targetLayer, 'object');
      expect(restored.output.tile.tileIndex, 10);
      expect(restored.priority, 5);
    });

    test('equality is based on id', () {
      const a = AutomapRule(
        id: 'rule_1',
        name: 'A',
        conditions: [],
        output: AutomapOutput(
          targetLayer: 'object',
          tile: TileRef(tilesetId: 'test', tileIndex: 1),
        ),
        priority: 1,
      );
      const b = AutomapRule(
        id: 'rule_1',
        name: 'B',
        conditions: [],
        output: AutomapOutput(
          targetLayer: 'object',
          tile: TileRef(tilesetId: 'test', tileIndex: 2),
        ),
        priority: 2,
      );
      const c = AutomapRule(
        id: 'rule_2',
        name: 'A',
        conditions: [],
        output: AutomapOutput(
          targetLayer: 'object',
          tile: TileRef(tilesetId: 'test', tileIndex: 1),
        ),
        priority: 1,
      );

      expect(a, equals(b));
      expect(a, isNot(equals(c)));
    });

    test('fromJson handles all TileType values', () {
      for (final type in TileType.values) {
        final json = {
          'id': 'test',
          'name': 'Test',
          'conditions': [
            {'dx': 0, 'dy': 0, 'structureType': type.name},
          ],
          'output': {
            'targetLayer': 'object',
            'tile': {'tilesetId': 't', 'tileIndex': 0},
          },
          'priority': 1,
        };

        final rule = AutomapRule.fromJson(json);
        expect(rule.conditions[0].structureType, type);
      }
    });
  });
}
