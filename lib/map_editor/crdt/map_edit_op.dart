import 'package:tech_world/flame/tiles/tile_ref.dart';

/// Which layer a map edit operation targets.
enum OpLayer { structure, floor, objects, terrain }

/// A single cell edit in the map editor CRDT.
///
/// Each op records who made the edit, a Lamport counter for ordering,
/// the cell coordinates, and the old/new values for undo support.
///
/// Value encoding per layer:
/// - `structure`: `String?` — `'barrier'`, `'spawn'`, `'terminal'`, or `null` (open)
/// - `floor` / `objects`: `Map<String, dynamic>?` — [TileRef.toJson] or `null`
/// - `terrain`: `String?` — terrain ID or `null`
class MapEditOp {
  const MapEditOp({
    required this.playerId,
    required this.counter,
    required this.x,
    required this.y,
    required this.layer,
    this.oldValue,
    this.newValue,
  });

  final String playerId;

  /// Lamport clock value — monotonically increasing per player.
  final int counter;

  final int x;
  final int y;
  final OpLayer layer;

  /// Previous value at this cell (for undo). Null means the cell was empty.
  final dynamic oldValue;

  /// New value for this cell. Null means erase.
  final dynamic newValue;

  /// Create the inverse operation (swap old ↔ new) with a fresh [counter].
  MapEditOp inverse({required int counter}) {
    return MapEditOp(
      playerId: playerId,
      counter: counter,
      x: x,
      y: y,
      layer: layer,
      oldValue: newValue,
      newValue: oldValue,
    );
  }

  /// Deserialize from JSON (as sent over data channel).
  factory MapEditOp.fromJson(Map<String, dynamic> json, {
    required String playerId,
    required int counter,
  }) {
    return MapEditOp(
      playerId: playerId,
      counter: counter,
      x: json['x'] as int,
      y: json['y'] as int,
      layer: OpLayer.values.byName(json['layer'] as String),
      oldValue: json['old'],
      newValue: json['new'],
    );
  }

  /// Serialize to JSON for data channel transmission.
  ///
  /// [playerId] and [counter] are sent at the batch level, not per-op.
  Map<String, dynamic> toJson() {
    return {
      'x': x,
      'y': y,
      'layer': layer.name,
      if (oldValue != null) 'old': oldValue,
      if (newValue != null) 'new': newValue,
    };
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MapEditOp &&
          playerId == other.playerId &&
          counter == other.counter &&
          x == other.x &&
          y == other.y &&
          layer == other.layer &&
          opValueEquals(oldValue, other.oldValue) &&
          opValueEquals(newValue, other.newValue);

  @override
  int get hashCode => Object.hash(playerId, counter, x, y, layer);

  @override
  String toString() =>
      'MapEditOp($playerId, c=$counter, ($x,$y), ${layer.name}, $oldValue→$newValue)';
}

/// A batch of edits sharing the same player and counter.
///
/// Batches are the unit of transmission and undo. For example, a terrain
/// paint at (x,y) may produce floor-layer ops for 9 cells (target + 8
/// neighbors), all in one batch.
class MapEditBatch {
  const MapEditBatch({
    required this.playerId,
    required this.counter,
    required this.ops,
  });

  final String playerId;
  final int counter;
  final List<MapEditOp> ops;

  /// Create the inverse batch for undo, with a fresh [counter].
  ///
  /// Ops are reversed so that undo applies in the opposite order.
  MapEditBatch inverse({required int counter}) {
    return MapEditBatch(
      playerId: playerId,
      counter: counter,
      ops: ops.reversed.map((op) => op.inverse(counter: counter)).toList(),
    );
  }

  /// Deserialize from a JSON map (data channel format).
  factory MapEditBatch.fromJson(Map<String, dynamic> json) {
    final playerId = json['playerId'] as String;
    final counter = json['counter'] as int;
    final opsJson = json['ops'] as List<dynamic>;
    return MapEditBatch(
      playerId: playerId,
      counter: counter,
      ops: opsJson
          .map((e) => MapEditOp.fromJson(
                e as Map<String, dynamic>,
                playerId: playerId,
                counter: counter,
              ))
          .toList(),
    );
  }

  /// Serialize to JSON for data channel transmission.
  Map<String, dynamic> toJson() {
    return {
      'type': 'edit',
      'playerId': playerId,
      'counter': counter,
      'ops': ops.map((op) => op.toJson()).toList(),
    };
  }

  @override
  String toString() =>
      'MapEditBatch($playerId, c=$counter, ${ops.length} ops)';
}

/// Shallow-deep equality for op values.
///
/// Compares Maps by key-value pairs (one level deep) and everything else
/// with `==`. Sufficient for the JSON-serializable values used in ops
/// (String, int, null, and flat `Map<String, dynamic>` from TileRef).
bool opValueEquals(dynamic a, dynamic b) {
  if (a is Map && b is Map) {
    if (a.length != b.length) return false;
    for (final key in a.keys) {
      if (!b.containsKey(key) || a[key] != b[key]) return false;
    }
    return true;
  }
  return a == b;
}

/// Helper to encode a structure [TileType] name to the wire format.
///
/// Returns `'barrier'`, `'spawn'`, `'terminal'`, or `null` for open.
String? structureValueToJson(String tileTypeName) {
  if (tileTypeName == 'open') return null;
  return tileTypeName;
}

/// Helper to decode a structure value from wire format back to [TileType] name.
String structureValueFromJson(dynamic value) {
  if (value == null) return 'open';
  return value as String;
}

/// Encode a [TileRef] to the wire format, or null if absent.
Map<String, dynamic>? tileRefToOpValue(TileRef? ref) => ref?.toJson();

/// Decode a tile ref from the wire format.
TileRef? tileRefFromOpValue(dynamic value) {
  if (value == null) return null;
  return TileRef.fromJson(value as Map<String, dynamic>);
}
