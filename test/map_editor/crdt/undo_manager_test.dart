import 'package:flutter_test/flutter_test.dart';
import 'package:tech_world/map_editor/crdt/map_edit_op.dart';
import 'package:tech_world/map_editor/crdt/undo_manager.dart';

void main() {
  late UndoManager manager;

  setUp(() {
    manager = UndoManager(playerId: 'alice');
  });

  group('counter', () {
    test('starts at 0 and increments', () {
      expect(manager.clock, 0);
      expect(manager.nextCounter(), 1);
      expect(manager.nextCounter(), 2);
      expect(manager.clock, 2);
    });

    test('advanceClock advances to max', () {
      manager.nextCounter(); // 1
      manager.advanceClock(10);
      expect(manager.clock, 10);
      expect(manager.nextCounter(), 11);
    });

    test('advanceClock ignores lower values', () {
      manager.advanceClock(10);
      manager.advanceClock(5);
      expect(manager.clock, 10);
    });
  });

  group('push/undo/redo', () {
    test('starts empty', () {
      expect(manager.canUndo, isFalse);
      expect(manager.canRedo, isFalse);
    });

    test('push enables undo', () {
      manager.push(_makeBatch('alice', 1));
      expect(manager.canUndo, isTrue);
      expect(manager.canRedo, isFalse);
    });

    test('undo produces inverse batch with fresh counter', () {
      final counter = manager.nextCounter(); // 1
      manager.push(_makeBatch('alice', counter, newValue: 'barrier'));
      final inverse = manager.createUndo();

      expect(inverse, isNotNull);
      expect(inverse!.counter, 2); // nextCounter() was called
      expect(inverse.ops[0].newValue, isNull); // inverted
      expect(inverse.ops[0].oldValue, 'barrier'); // inverted
      expect(manager.canUndo, isFalse);
      expect(manager.canRedo, isTrue);
    });

    test('redo re-applies forward batch with fresh counter', () {
      final counter = manager.nextCounter(); // 1
      manager.push(_makeBatch('alice', counter, newValue: 'barrier'));
      manager.createUndo(); // counter becomes 2
      final forward = manager.createRedo();

      expect(forward, isNotNull);
      expect(forward!.counter, 3); // fresh counter
      expect(forward.ops[0].newValue, 'barrier');
      expect(manager.canUndo, isTrue);
      expect(manager.canRedo, isFalse);
    });

    test('push clears redo stack', () {
      manager.push(_makeBatch('alice', 1));
      manager.createUndo();
      expect(manager.canRedo, isTrue);

      manager.push(_makeBatch('alice', 3));
      expect(manager.canRedo, isFalse);
    });

    test('multiple undo/redo cycle', () {
      // Push 3 edits.
      manager.push(_makeBatch('alice', 1, newValue: 'a'));
      manager.push(_makeBatch('alice', 2, newValue: 'b'));
      manager.push(_makeBatch('alice', 3, newValue: 'c'));

      // Undo 2.
      final undo1 = manager.createUndo();
      expect(undo1!.ops[0].oldValue, 'c');
      final undo2 = manager.createUndo();
      expect(undo2!.ops[0].oldValue, 'b');

      expect(manager.canUndo, isTrue); // 1 left
      expect(manager.canRedo, isTrue); // 2 available

      // Redo 1.
      final redo1 = manager.createRedo();
      expect(redo1!.ops[0].newValue, 'b');
    });

    test('createUndo returns null when empty', () {
      expect(manager.createUndo(), isNull);
    });

    test('createRedo returns null when empty', () {
      expect(manager.createRedo(), isNull);
    });

    test('clear empties both stacks', () {
      manager.push(_makeBatch('alice', 1));
      manager.createUndo();
      expect(manager.canRedo, isTrue);

      manager.clear();
      expect(manager.canUndo, isFalse);
      expect(manager.canRedo, isFalse);
    });
  });
}

MapEditBatch _makeBatch(
  String playerId,
  int counter, {
  dynamic newValue,
  dynamic oldValue,
}) {
  return MapEditBatch(
    playerId: playerId,
    counter: counter,
    ops: [
      MapEditOp(
        playerId: playerId,
        counter: counter,
        x: 0,
        y: 0,
        layer: OpLayer.structure,
        oldValue: oldValue,
        newValue: newValue,
      ),
    ],
  );
}
