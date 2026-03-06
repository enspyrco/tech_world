import 'package:tech_world/map_editor/crdt/map_edit_op.dart';

/// Last-Writer-Wins conflict resolution for the map editor CRDT.
///
/// Tracks the latest `(counter, playerId)` for each `(x, y, layer)` cell.
/// An incoming operation wins if its counter is higher, or if counters tie
/// and its playerId is lexicographically greater.
///
/// This guarantees convergence: all clients applying the same set of
/// operations (in any order) will arrive at the same final state.
class CellVersionMap {
  /// Version entries keyed by (x, y, layer).
  ///
  /// Value is (counter, playerId) of the winning write.
  final Map<(int, int, OpLayer), (int, String)> _versions = {};

  /// Whether [op] should be applied to the local state.
  ///
  /// Returns true if no version exists for this cell, or if the op's
  /// `(counter, playerId)` beats the existing version.
  bool shouldApply(MapEditOp op) {
    final key = (op.x, op.y, op.layer);
    final existing = _versions[key];
    if (existing == null) return true;
    final (counter, playerId) = existing;
    if (op.counter > counter) return true;
    if (op.counter == counter && op.playerId.compareTo(playerId) > 0) {
      return true;
    }
    return false;
  }

  /// Record an op's version. Call this after applying an op locally.
  void record(MapEditOp op) {
    final key = (op.x, op.y, op.layer);
    _versions[key] = (op.counter, op.playerId);
  }

  /// Record all ops in a batch.
  void recordBatch(MapEditBatch batch) {
    for (final op in batch.ops) {
      record(op);
    }
  }

  /// Get the current version for a cell, or null if untracked.
  (int, String)? versionAt(int x, int y, OpLayer layer) {
    return _versions[(x, y, layer)];
  }

  /// Clear all tracked versions.
  void clear() => _versions.clear();

  /// Number of tracked cells (for diagnostics).
  int get length => _versions.length;

  /// Serialize all versions for sync protocol.
  ///
  /// Format: `{"x,y,layer": [counter, "playerId"], ...}`
  Map<String, dynamic> toJson() {
    final result = <String, dynamic>{};
    for (final entry in _versions.entries) {
      final (x, y, layer) = entry.key;
      final (counter, playerId) = entry.value;
      result['$x,$y,${layer.name}'] = [counter, playerId];
    }
    return result;
  }

  /// Deserialize versions from sync protocol.
  void loadFromJson(Map<String, dynamic> json) {
    _versions.clear();
    for (final entry in json.entries) {
      final parts = entry.key.split(',');
      final x = int.parse(parts[0]);
      final y = int.parse(parts[1]);
      final layer = OpLayer.values.byName(parts[2]);
      final value = entry.value as List<dynamic>;
      _versions[(x, y, layer)] = (value[0] as int, value[1] as String);
    }
  }
}
