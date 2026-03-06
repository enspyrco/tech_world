import 'dart:math';

import 'package:tech_world/map_editor/crdt/map_edit_op.dart';

/// Per-player undo/redo stack backed by Lamport-stamped batches.
///
/// Undo and redo work by creating *new* inverse batches with fresh counters,
/// so they participate in normal CRDT conflict resolution. If another player
/// edited the same cell since, the undo's higher counter wins — which is
/// correct because explicit undo intent should override.
class UndoManager {
  UndoManager({required this.playerId, this.maxUndoDepth = 500});

  final String playerId;

  /// Maximum number of batches kept in the undo stack.
  final int maxUndoDepth;

  int _counter = 0;

  final List<MapEditBatch> _undoStack = [];
  final List<MapEditBatch> _redoStack = [];

  /// Get the next counter value (pre-increment).
  int nextCounter() => ++_counter;

  /// Advance the local clock when receiving a remote operation.
  ///
  /// Ensures the Lamport clock property: local counter is always greater
  /// than any observed remote counter.
  void advanceClock(int remoteClock) {
    _counter = max(_counter, remoteClock);
  }

  /// The current clock value (for diagnostics/sync).
  int get clock => _counter;

  /// Push a batch onto the undo stack after a local edit.
  ///
  /// Clears the redo stack since the edit timeline has diverged.
  void push(MapEditBatch batch) {
    _undoStack.add(batch);
    if (_undoStack.length > maxUndoDepth) {
      _undoStack.removeAt(0);
    }
    _redoStack.clear();
  }

  /// Whether there are operations to undo.
  bool get canUndo => _undoStack.isNotEmpty;

  /// Whether there are operations to redo.
  bool get canRedo => _redoStack.isNotEmpty;

  /// Create an undo batch from the most recent edit.
  ///
  /// Returns null if the undo stack is empty. The returned batch has a
  /// fresh counter and inverted old/new values.
  MapEditBatch? createUndo() {
    if (_undoStack.isEmpty) return null;
    final batch = _undoStack.removeLast();
    final counter = nextCounter();
    final inverse = batch.inverse(counter: counter);
    _redoStack.add(batch);
    return inverse;
  }

  /// Create a redo batch from the most recently undone edit.
  ///
  /// Returns null if the redo stack is empty. The returned batch has a
  /// fresh counter and the original (forward) values.
  MapEditBatch? createRedo() {
    if (_redoStack.isEmpty) return null;
    final original = _redoStack.removeLast();
    final counter = nextCounter();
    // Re-apply the original ops but with the new counter.
    final forward = MapEditBatch(
      playerId: original.playerId,
      counter: counter,
      ops: original.ops
          .map((op) => MapEditOp(
                playerId: op.playerId,
                counter: counter,
                x: op.x,
                y: op.y,
                layer: op.layer,
                oldValue: op.oldValue,
                newValue: op.newValue,
              ))
          .toList(),
    );
    _undoStack.add(original);
    return forward;
  }

  /// Clear both stacks (e.g., when loading a new map).
  void clear() {
    _undoStack.clear();
    _redoStack.clear();
  }
}
