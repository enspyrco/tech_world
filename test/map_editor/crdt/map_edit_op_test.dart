import 'package:flutter_test/flutter_test.dart';
import 'package:tech_world/map_editor/crdt/map_edit_op.dart';

void main() {
  group('MapEditOp', () {
    test('serialization round-trip with string values', () {
      const op = MapEditOp(
        playerId: 'alice',
        counter: 5,
        x: 10,
        y: 20,
        layer: OpLayer.structure,
        oldValue: 'barrier',
        newValue: null,
      );

      final json = op.toJson();
      final decoded = MapEditOp.fromJson(json, playerId: 'alice', counter: 5);

      expect(decoded.x, 10);
      expect(decoded.y, 20);
      expect(decoded.layer, OpLayer.structure);
      expect(decoded.oldValue, 'barrier');
      expect(decoded.newValue, isNull);
    });

    test('serialization round-trip with map values (TileRef)', () {
      const op = MapEditOp(
        playerId: 'bob',
        counter: 3,
        x: 5,
        y: 7,
        layer: OpLayer.floor,
        oldValue: null,
        newValue: {'tilesetId': 'ext_terrains', 'tileIndex': 105},
      );

      final json = op.toJson();
      final decoded = MapEditOp.fromJson(json, playerId: 'bob', counter: 3);

      expect(decoded.layer, OpLayer.floor);
      expect(decoded.oldValue, isNull);
      expect(decoded.newValue, isA<Map>());
      expect(decoded.newValue['tilesetId'], 'ext_terrains');
      expect(decoded.newValue['tileIndex'], 105);
    });

    test('serialization omits null old/new values', () {
      const op = MapEditOp(
        playerId: 'alice',
        counter: 1,
        x: 0,
        y: 0,
        layer: OpLayer.terrain,
        oldValue: null,
        newValue: 'water',
      );

      final json = op.toJson();
      expect(json.containsKey('old'), isFalse);
      expect(json['new'], 'water');
    });

    test('inverse swaps old and new with fresh counter', () {
      const op = MapEditOp(
        playerId: 'alice',
        counter: 5,
        x: 1,
        y: 2,
        layer: OpLayer.structure,
        oldValue: null,
        newValue: 'barrier',
      );

      final inv = op.inverse(counter: 10);
      expect(inv.playerId, 'alice');
      expect(inv.counter, 10);
      expect(inv.x, 1);
      expect(inv.y, 2);
      expect(inv.oldValue, 'barrier');
      expect(inv.newValue, isNull);
    });

    test('equality considers all fields', () {
      const op1 = MapEditOp(
        playerId: 'a',
        counter: 1,
        x: 0,
        y: 0,
        layer: OpLayer.floor,
        oldValue: null,
        newValue: {'tilesetId': 'x', 'tileIndex': 1},
      );
      const op2 = MapEditOp(
        playerId: 'a',
        counter: 1,
        x: 0,
        y: 0,
        layer: OpLayer.floor,
        oldValue: null,
        newValue: {'tilesetId': 'x', 'tileIndex': 1},
      );
      const op3 = MapEditOp(
        playerId: 'a',
        counter: 2,
        x: 0,
        y: 0,
        layer: OpLayer.floor,
        oldValue: null,
        newValue: {'tilesetId': 'x', 'tileIndex': 1},
      );
      expect(op1, equals(op2));
      expect(op1, isNot(equals(op3)));
    });
  });

  group('MapEditBatch', () {
    test('serialization round-trip', () {
      final batch = MapEditBatch(
        playerId: 'alice',
        counter: 42,
        ops: const [
          MapEditOp(
            playerId: 'alice',
            counter: 42,
            x: 10,
            y: 20,
            layer: OpLayer.structure,
            oldValue: 'barrier',
            newValue: null,
          ),
          MapEditOp(
            playerId: 'alice',
            counter: 42,
            x: 10,
            y: 21,
            layer: OpLayer.floor,
            oldValue: null,
            newValue: {'tilesetId': 'ext_terrains', 'tileIndex': 105},
          ),
        ],
      );

      final json = batch.toJson();
      expect(json['type'], 'edit');
      expect(json['playerId'], 'alice');
      expect(json['counter'], 42);
      expect((json['ops'] as List).length, 2);

      final decoded = MapEditBatch.fromJson(json);
      expect(decoded.playerId, 'alice');
      expect(decoded.counter, 42);
      expect(decoded.ops.length, 2);
      expect(decoded.ops[0].layer, OpLayer.structure);
      expect(decoded.ops[1].layer, OpLayer.floor);
    });

    test('inverse reverses ops order and swaps values', () {
      final batch = MapEditBatch(
        playerId: 'alice',
        counter: 5,
        ops: const [
          MapEditOp(
            playerId: 'alice',
            counter: 5,
            x: 0,
            y: 0,
            layer: OpLayer.structure,
            oldValue: null,
            newValue: 'barrier',
          ),
          MapEditOp(
            playerId: 'alice',
            counter: 5,
            x: 1,
            y: 0,
            layer: OpLayer.structure,
            oldValue: null,
            newValue: 'terminal',
          ),
        ],
      );

      final inv = batch.inverse(counter: 10);
      expect(inv.counter, 10);
      expect(inv.ops.length, 2);
      // Reversed order.
      expect(inv.ops[0].x, 1);
      expect(inv.ops[0].newValue, isNull);
      expect(inv.ops[0].oldValue, 'terminal');
      expect(inv.ops[1].x, 0);
      expect(inv.ops[1].newValue, isNull);
      expect(inv.ops[1].oldValue, 'barrier');
    });
  });

  group('Helper functions', () {
    test('structureValueToJson maps open to null', () {
      expect(structureValueToJson('open'), isNull);
      expect(structureValueToJson('barrier'), 'barrier');
      expect(structureValueToJson('spawn'), 'spawn');
    });

    test('structureValueFromJson maps null to open', () {
      expect(structureValueFromJson(null), 'open');
      expect(structureValueFromJson('barrier'), 'barrier');
    });
  });
}
