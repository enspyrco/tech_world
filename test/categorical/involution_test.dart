import 'package:flutter_test/flutter_test.dart';
import 'package:tech_world/map_editor/crdt/map_edit_op.dart';

/// MapEditOp.inverse involution law tests.
///
/// An involution is a function f such that f(f(x)) == x.
/// MapEditOp.inverse swaps old/new values. Since the counter is
/// intentionally fresh per call, the involution holds on the
/// (x, y, layer, oldValue, newValue) payload — the content that
/// determines undo correctness.
void main() {
  group('MapEditOp.inverse involution', () {
    test('inverse(inverse(op)) recovers original payload', () {
      final op = MapEditOp(
        playerId: 'alice',
        counter: 1,
        x: 3,
        y: 4,
        layer: OpLayer.floor,
        oldValue: {'tileset': 'grass', 'index': 0},
        newValue: {'tileset': 'stone', 'index': 1},
      );

      final inv = op.inverse(counter: 2);
      final invInv = inv.inverse(counter: 3);

      // The payload (everything except counter) must match
      expect(invInv.x, equals(op.x));
      expect(invInv.y, equals(op.y));
      expect(invInv.layer, equals(op.layer));
      expect(invInv.playerId, equals(op.playerId));
      expect(opValueEquals(invInv.oldValue, op.oldValue), isTrue,
          reason: 'oldValue must round-trip');
      expect(opValueEquals(invInv.newValue, op.newValue), isTrue,
          reason: 'newValue must round-trip');
    });

    test('inverse swaps old and new', () {
      final op = MapEditOp(
        playerId: 'bob',
        counter: 1,
        x: 0,
        y: 0,
        layer: OpLayer.structure,
        oldValue: 'barrier',
        newValue: null,
      );

      final inv = op.inverse(counter: 2);

      expect(inv.oldValue, isNull, reason: 'old becomes new');
      expect(inv.newValue, equals('barrier'), reason: 'new becomes old');
    });

    test('inverse of null->value is value->null', () {
      final op = MapEditOp(
        playerId: 'charlie',
        counter: 1,
        x: 5,
        y: 5,
        layer: OpLayer.terrain,
        oldValue: null,
        newValue: 'grass',
      );

      final inv = op.inverse(counter: 2);

      expect(inv.oldValue, equals('grass'));
      expect(inv.newValue, isNull);
    });

    test('counter is fresh (not part of involution)', () {
      final op = MapEditOp(
        playerId: 'alice',
        counter: 10,
        x: 0,
        y: 0,
        layer: OpLayer.floor,
        oldValue: 'a',
        newValue: 'b',
      );

      final inv = op.inverse(counter: 20);
      expect(inv.counter, equals(20), reason: 'Counter is the supplied value');

      final invInv = inv.inverse(counter: 30);
      expect(invInv.counter, equals(30),
          reason: 'Counter is intentionally fresh, not restored');
    });
  });

  group('MapEditBatch.inverse', () {
    test('inverse reverses op order and swaps old/new', () {
      final batch = MapEditBatch(
        playerId: 'alice',
        counter: 1,
        ops: [
          MapEditOp(
            playerId: 'alice',
            counter: 1,
            x: 0,
            y: 0,
            layer: OpLayer.floor,
            oldValue: 'a',
            newValue: 'b',
          ),
          MapEditOp(
            playerId: 'alice',
            counter: 1,
            x: 1,
            y: 1,
            layer: OpLayer.floor,
            oldValue: 'c',
            newValue: 'd',
          ),
        ],
      );

      final inv = batch.inverse(counter: 2);

      expect(inv.ops.length, equals(2));
      // Order is reversed
      expect(inv.ops[0].x, equals(1));
      expect(inv.ops[1].x, equals(0));
      // Values are swapped
      expect(inv.ops[0].oldValue, equals('d'));
      expect(inv.ops[0].newValue, equals('c'));
      expect(inv.ops[1].oldValue, equals('b'));
      expect(inv.ops[1].newValue, equals('a'));
    });
  });

  group('MapEditOp toJson/fromJson round-trip', () {
    test('round-trip preserves op payload', () {
      final op = MapEditOp(
        playerId: 'alice',
        counter: 5,
        x: 3,
        y: 7,
        layer: OpLayer.terrain,
        oldValue: 'grass',
        newValue: 'stone',
      );

      final json = op.toJson();
      final restored = MapEditOp.fromJson(
        json,
        playerId: 'alice',
        counter: 5,
      );

      expect(restored, isNotNull);
      expect(restored!.x, equals(op.x));
      expect(restored.y, equals(op.y));
      expect(restored.layer, equals(op.layer));
      expect(restored.oldValue, equals(op.oldValue));
      expect(restored.newValue, equals(op.newValue));
    });

    test('fromJson returns null for unknown layer', () {
      final json = {'x': 0, 'y': 0, 'layer': 'hologram'};
      final result = MapEditOp.fromJson(
        json,
        playerId: 'alice',
        counter: 1,
      );
      expect(result, isNull);
    });
  });
}
