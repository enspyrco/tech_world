import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:tech_world/flame/shared/constants.dart';
import 'package:tech_world/flame/tiles/tile_ref.dart';
import 'package:tech_world/livekit/livekit_service.dart';
import 'package:tech_world/map_editor/crdt/cell_version_map.dart';
import 'package:tech_world/map_editor/crdt/map_edit_op.dart';
import 'package:tech_world/map_editor/crdt/undo_manager.dart';
import 'package:tech_world/map_editor/map_editor_state.dart';

/// Orchestrates collaborative map editing over LiveKit data channels.
///
/// Sits between the UI (MapEditorPanel) and the local state (MapEditorState),
/// capturing edits as CRDT operations, broadcasting them, and applying
/// incoming remote edits with LWW conflict resolution.
class MapSyncService {
  MapSyncService({
    required LiveKitService liveKitService,
    required MapEditorState editorState,
    required String localPlayerId,
  })  : _liveKitService = liveKitService,
        _editorState = editorState,
        _undoManager = UndoManager(playerId: localPlayerId),
        _localPlayerId = localPlayerId {
    _dataSubscription = _liveKitService.dataReceived
        .where((msg) =>
            msg.topic == _editTopic || msg.topic == _syncTopic)
        .listen(_onDataReceived);
  }

  static const _editTopic = 'map-edit';
  static const _syncTopic = 'map-edit-sync';

  final LiveKitService _liveKitService;
  final MapEditorState _editorState;
  final UndoManager _undoManager;
  final CellVersionMap _versionMap = CellVersionMap();
  final String _localPlayerId;
  StreamSubscription<DataChannelMessage>? _dataSubscription;

  /// Notifier that fires when undo/redo availability changes.
  final ValueNotifier<int> undoRedoChanged = ValueNotifier<int>(0);

  /// Whether there are operations to undo.
  bool get canUndo => _undoManager.canUndo;

  /// Whether there are operations to redo.
  bool get canRedo => _undoManager.canRedo;

  // -------------------------------------------------------------------------
  // Sync state for late-join
  // -------------------------------------------------------------------------

  bool _isSyncing = false;
  final List<MapEditBatch> _syncBuffer = [];

  // -------------------------------------------------------------------------
  // Public API — called by MapEditorPanel
  // -------------------------------------------------------------------------

  /// Paint a structure tile at (x, y) using the current tool.
  void paintTile(int x, int y) {
    if (!_inBounds(x, y)) return;

    final oldValue = _structureToValue(_editorState.tileAt(x, y));
    _editorState.paintTile(x, y);
    final newValue = _structureToValue(_editorState.tileAt(x, y));

    if (oldValue == newValue) return;

    final counter = _undoManager.nextCounter();
    final op = MapEditOp(
      playerId: _localPlayerId,
      counter: counter,
      x: x,
      y: y,
      layer: OpLayer.structure,
      oldValue: oldValue,
      newValue: newValue,
    );
    final batch = MapEditBatch(
      playerId: _localPlayerId,
      counter: counter,
      ops: [op],
    );

    _pushAndPublish(batch);
  }

  /// Paint a tile ref at (x, y) on the active tile layer.
  void paintTileRef(int x, int y) {
    if (!_inBounds(x, y)) return;

    final layer = _editorState.activeLayer == ActiveLayer.objects
        ? OpLayer.objects
        : OpLayer.floor;
    final layerData = layer == OpLayer.objects
        ? _editorState.objectLayerData
        : _editorState.floorLayerData;

    // Capture old values for the brush footprint.
    final brush = _editorState.currentBrush;
    final ops = <MapEditOp>[];
    final counter = _undoManager.nextCounter();

    if (brush == null) {
      // Eraser — single cell.
      final oldRef = layerData.tileAt(x, y);
      _editorState.paintTileRef(x, y);
      final newRef = layerData.tileAt(x, y);
      if (tileRefToOpValue(oldRef) != tileRefToOpValue(newRef)) {
        ops.add(MapEditOp(
          playerId: _localPlayerId,
          counter: counter,
          x: x,
          y: y,
          layer: layer,
          oldValue: tileRefToOpValue(oldRef),
          newValue: tileRefToOpValue(newRef),
        ));
      }
    } else {
      // Multi-tile brush — capture all cells in footprint.
      final oldRefs = <(int, int), TileRef?>{};
      for (var dy = 0; dy < brush.height; dy++) {
        for (var dx = 0; dx < brush.width; dx++) {
          final tx = x + dx;
          final ty = y + dy;
          if (_inBounds(tx, ty)) {
            oldRefs[(tx, ty)] = layerData.tileAt(tx, ty);
          }
        }
      }

      _editorState.paintTileRef(x, y);

      for (final entry in oldRefs.entries) {
        final (tx, ty) = entry.key;
        final oldRef = entry.value;
        final newRef = layerData.tileAt(tx, ty);
        final oldVal = tileRefToOpValue(oldRef);
        final newVal = tileRefToOpValue(newRef);
        if (!_deepEquals(oldVal, newVal)) {
          ops.add(MapEditOp(
            playerId: _localPlayerId,
            counter: counter,
            x: tx,
            y: ty,
            layer: layer,
            oldValue: oldVal,
            newValue: newVal,
          ));
        }
      }
    }

    // Also capture any auto-barrier changes on the structure grid.
    // (Auto-barriers are created when painting barrier-tagged tiles.)
    // We skip this for simplicity — auto-barriers are deterministic
    // from the tile layer state and will be recomputed on remote apply.

    if (ops.isEmpty) return;

    final batch = MapEditBatch(
      playerId: _localPlayerId,
      counter: counter,
      ops: ops,
    );
    _pushAndPublish(batch);
  }

  /// Paint terrain at (x, y) using the active terrain brush.
  ///
  /// Terrain painting re-evaluates the target cell plus 8 neighbors. We
  /// capture the full diff on the terrain and floor layers, producing a
  /// batch that remote clients can apply directly without bitmask
  /// recomputation.
  void paintTerrain(int x, int y) {
    if (!_inBounds(x, y)) return;

    final counter = _undoManager.nextCounter();
    final ops = <MapEditOp>[];

    // Capture terrain and floor state for target + 8 neighbors BEFORE paint.
    final affectedCells = _terrainAffectedCells(x, y);
    final oldTerrain = <(int, int), String?>{};
    final oldFloor = <(int, int), TileRef?>{};
    for (final (cx, cy) in affectedCells) {
      oldTerrain[(cx, cy)] = _editorState.terrainGrid.terrainAt(cx, cy);
      oldFloor[(cx, cy)] = _editorState.floorLayerData.tileAt(cx, cy);
    }

    // Apply the terrain paint locally.
    _editorState.paintTerrain(x, y);

    // Diff to produce ops.
    for (final (cx, cy) in affectedCells) {
      final newTerrain = _editorState.terrainGrid.terrainAt(cx, cy);
      if (oldTerrain[(cx, cy)] != newTerrain) {
        ops.add(MapEditOp(
          playerId: _localPlayerId,
          counter: counter,
          x: cx,
          y: cy,
          layer: OpLayer.terrain,
          oldValue: oldTerrain[(cx, cy)],
          newValue: newTerrain,
        ));
      }

      final newFloor = _editorState.floorLayerData.tileAt(cx, cy);
      final oldFloorVal = tileRefToOpValue(oldFloor[(cx, cy)]);
      final newFloorVal = tileRefToOpValue(newFloor);
      if (!_deepEquals(oldFloorVal, newFloorVal)) {
        ops.add(MapEditOp(
          playerId: _localPlayerId,
          counter: counter,
          x: cx,
          y: cy,
          layer: OpLayer.floor,
          oldValue: oldFloorVal,
          newValue: newFloorVal,
        ));
      }
    }

    if (ops.isEmpty) return;

    final batch = MapEditBatch(
      playerId: _localPlayerId,
      counter: counter,
      ops: ops,
    );
    _pushAndPublish(batch);
  }

  /// Erase terrain at (x, y).
  void eraseTerrainAt(int x, int y) {
    if (!_inBounds(x, y)) return;

    final counter = _undoManager.nextCounter();
    final ops = <MapEditOp>[];

    final affectedCells = _terrainAffectedCells(x, y);
    final oldTerrain = <(int, int), String?>{};
    final oldFloor = <(int, int), TileRef?>{};
    for (final (cx, cy) in affectedCells) {
      oldTerrain[(cx, cy)] = _editorState.terrainGrid.terrainAt(cx, cy);
      oldFloor[(cx, cy)] = _editorState.floorLayerData.tileAt(cx, cy);
    }

    _editorState.eraseTerrainAt(x, y);

    for (final (cx, cy) in affectedCells) {
      final newTerrain = _editorState.terrainGrid.terrainAt(cx, cy);
      if (oldTerrain[(cx, cy)] != newTerrain) {
        ops.add(MapEditOp(
          playerId: _localPlayerId,
          counter: counter,
          x: cx,
          y: cy,
          layer: OpLayer.terrain,
          oldValue: oldTerrain[(cx, cy)],
          newValue: newTerrain,
        ));
      }

      final newFloor = _editorState.floorLayerData.tileAt(cx, cy);
      final oldFloorVal = tileRefToOpValue(oldFloor[(cx, cy)]);
      final newFloorVal = tileRefToOpValue(newFloor);
      if (!_deepEquals(oldFloorVal, newFloorVal)) {
        ops.add(MapEditOp(
          playerId: _localPlayerId,
          counter: counter,
          x: cx,
          y: cy,
          layer: OpLayer.floor,
          oldValue: oldFloorVal,
          newValue: newFloorVal,
        ));
      }
    }

    if (ops.isEmpty) return;

    final batch = MapEditBatch(
      playerId: _localPlayerId,
      counter: counter,
      ops: ops,
    );
    _pushAndPublish(batch);
  }

  /// Undo the last local edit.
  void undo() {
    final batch = _undoManager.createUndo();
    if (batch == null) return;
    _applyBatchLocally(batch);
    _versionMap.recordBatch(batch);
    _publishBatch(batch);
    _notifyUndoRedo();
  }

  /// Redo the last undone edit.
  void redo() {
    final batch = _undoManager.createRedo();
    if (batch == null) return;
    _applyBatchLocally(batch);
    _versionMap.recordBatch(batch);
    _publishBatch(batch);
    _notifyUndoRedo();
  }

  // -------------------------------------------------------------------------
  // Late-join sync
  // -------------------------------------------------------------------------

  /// Request a full state sync from other editors in the room.
  ///
  /// Buffers incoming edits during sync to avoid races.
  Future<void> requestSync() async {
    _isSyncing = true;
    _syncBuffer.clear();

    await _liveKitService.publishJson(
      {'type': 'sync-request', 'playerId': _localPlayerId},
      topic: _syncTopic,
      reliable: true,
    );

    // The sync response will arrive via _onDataReceived.
    // If no response comes within 5 seconds, stop waiting.
    await Future.delayed(const Duration(seconds: 5));
    _flushSyncBuffer();
  }

  // -------------------------------------------------------------------------
  // Internals
  // -------------------------------------------------------------------------

  void _onDataReceived(DataChannelMessage msg) {
    if (msg.senderId == _localPlayerId) return; // Ignore own messages.
    final json = msg.json;
    if (json == null) return;

    if (msg.topic == _editTopic) {
      final batch = MapEditBatch.fromJson(json);
      if (_isSyncing) {
        _syncBuffer.add(batch);
      } else {
        _onRemoteEdit(batch);
      }
    } else if (msg.topic == _syncTopic) {
      final type = json['type'] as String?;
      if (type == 'sync-request' && json['playerId'] != _localPlayerId) {
        _handleSyncRequest(json['playerId'] as String);
      } else if (type == 'sync-response') {
        _handleSyncResponse(json);
      }
    }
  }

  void _onRemoteEdit(MapEditBatch batch) {
    _undoManager.advanceClock(batch.counter);

    for (final op in batch.ops) {
      if (_versionMap.shouldApply(op)) {
        _applyOpLocally(op);
        _versionMap.record(op);
      }
    }

    _editorState.notifyRemoteChange();
  }

  /// Apply a single op to the local editor state.
  void _applyOpLocally(MapEditOp op) {
    switch (op.layer) {
      case OpLayer.structure:
        final typeName = structureValueFromJson(op.newValue);
        _editorState.setStructureTile(op.x, op.y, _tileTypeFromName(typeName));
      case OpLayer.floor:
        final ref = tileRefFromOpValue(op.newValue);
        _editorState.floorLayerData.setTile(op.x, op.y, ref);
      case OpLayer.objects:
        final ref = tileRefFromOpValue(op.newValue);
        _editorState.objectLayerData.setTile(op.x, op.y, ref);
      case OpLayer.terrain:
        _editorState.terrainGrid.setTerrain(
          op.x,
          op.y,
          op.newValue as String?,
        );
    }
  }

  /// Apply all ops in a batch to local state (for undo/redo).
  void _applyBatchLocally(MapEditBatch batch) {
    for (final op in batch.ops) {
      _applyOpLocally(op);
    }
    _editorState.notifyRemoteChange();
  }

  void _pushAndPublish(MapEditBatch batch) {
    _undoManager.push(batch);
    _versionMap.recordBatch(batch);
    _publishBatch(batch);
    _notifyUndoRedo();
  }

  Future<void> _publishBatch(MapEditBatch batch) async {
    await _liveKitService.publishJson(
      batch.toJson(),
      topic: _editTopic,
      reliable: true,
    );
  }

  void _notifyUndoRedo() {
    undoRedoChanged.value++;
  }

  // -------------------------------------------------------------------------
  // Sync protocol
  // -------------------------------------------------------------------------

  void _handleSyncRequest(String requesterId) {
    // Build snapshot of current state.
    final snapshot = _buildSnapshot();
    _liveKitService.publishJson(
      snapshot,
      topic: _syncTopic,
      reliable: true,
      destinationIdentities: [requesterId],
    );
  }

  void _handleSyncResponse(Map<String, dynamic> json) {
    if (!_isSyncing) return;

    // Apply structure tiles.
    final structure = json['structure'] as List<dynamic>? ?? [];
    for (final entry in structure) {
      final map = entry as Map<String, dynamic>;
      final x = map['x'] as int;
      final y = map['y'] as int;
      final typeName = structureValueFromJson(map['v']);
      _editorState.setStructureTile(x, y, _tileTypeFromName(typeName));
    }

    // Apply floor tiles.
    final floor = json['floor'] as List<dynamic>? ?? [];
    for (final entry in floor) {
      final map = entry as Map<String, dynamic>;
      final x = map['x'] as int;
      final y = map['y'] as int;
      _editorState.floorLayerData.setTile(
        x,
        y,
        TileRef(
          tilesetId: map['tilesetId'] as String,
          tileIndex: map['tileIndex'] as int,
        ),
      );
    }

    // Apply object tiles.
    final objects = json['objects'] as List<dynamic>? ?? [];
    for (final entry in objects) {
      final map = entry as Map<String, dynamic>;
      final x = map['x'] as int;
      final y = map['y'] as int;
      _editorState.objectLayerData.setTile(
        x,
        y,
        TileRef(
          tilesetId: map['tilesetId'] as String,
          tileIndex: map['tileIndex'] as int,
        ),
      );
    }

    // Apply terrain.
    final terrain = json['terrain'] as List<dynamic>? ?? [];
    for (final entry in terrain) {
      final map = entry as Map<String, dynamic>;
      _editorState.terrainGrid.setTerrain(
        map['x'] as int,
        map['y'] as int,
        map['t'] as String,
      );
    }

    // Load version map.
    final versions = json['versions'] as Map<String, dynamic>? ?? {};
    _versionMap.loadFromJson(versions);

    // Advance clock.
    final remoteClock = json['clock'] as int? ?? 0;
    _undoManager.advanceClock(remoteClock);

    _editorState.notifyRemoteChange();
    _flushSyncBuffer();
  }

  void _flushSyncBuffer() {
    _isSyncing = false;
    for (final batch in _syncBuffer) {
      _onRemoteEdit(batch);
    }
    _syncBuffer.clear();
  }

  Map<String, dynamic> _buildSnapshot() {
    final structure = <Map<String, dynamic>>[];
    final floor = <Map<String, dynamic>>[];
    final objects = <Map<String, dynamic>>[];
    final terrain = <Map<String, dynamic>>[];

    for (var y = 0; y < gridSize; y++) {
      for (var x = 0; x < gridSize; x++) {
        final tile = _editorState.tileAt(x, y);
        if (tile != TileType.open) {
          structure.add({'x': x, 'y': y, 'v': tile.name});
        }

        final floorRef = _editorState.floorLayerData.tileAt(x, y);
        if (floorRef != null) {
          floor.add({
            'x': x,
            'y': y,
            'tilesetId': floorRef.tilesetId,
            'tileIndex': floorRef.tileIndex,
          });
        }

        final objRef = _editorState.objectLayerData.tileAt(x, y);
        if (objRef != null) {
          objects.add({
            'x': x,
            'y': y,
            'tilesetId': objRef.tilesetId,
            'tileIndex': objRef.tileIndex,
          });
        }

        final terrainId = _editorState.terrainGrid.terrainAt(x, y);
        if (terrainId != null) {
          terrain.add({'x': x, 'y': y, 't': terrainId});
        }
      }
    }

    return {
      'type': 'sync-response',
      'structure': structure,
      'floor': floor,
      'objects': objects,
      'terrain': terrain,
      'versions': _versionMap.toJson(),
      'clock': _undoManager.clock,
    };
  }

  // -------------------------------------------------------------------------
  // Helpers
  // -------------------------------------------------------------------------

  /// Cells affected by a terrain paint at (x, y): target + 8 neighbors.
  List<(int, int)> _terrainAffectedCells(int x, int y) {
    final cells = <(int, int)>[(x, y)];
    for (final (dx, dy) in const [
      (-1, -1), (0, -1), (1, -1),
      (-1, 0), (1, 0),
      (-1, 1), (0, 1), (1, 1),
    ]) {
      final nx = x + dx;
      final ny = y + dy;
      if (_inBounds(nx, ny)) cells.add((nx, ny));
    }
    return cells;
  }

  bool _inBounds(int x, int y) =>
      x >= 0 && x < gridSize && y >= 0 && y < gridSize;

  String? _structureToValue(TileType type) {
    return type == TileType.open ? null : type.name;
  }

  TileType _tileTypeFromName(String name) {
    return TileType.values.byName(name);
  }

  /// Dispose subscriptions and resources.
  void dispose() {
    _dataSubscription?.cancel();
    _dataSubscription = null;
    undoRedoChanged.dispose();
  }
}

bool _deepEquals(dynamic a, dynamic b) {
  if (a is Map && b is Map) {
    if (a.length != b.length) return false;
    for (final key in a.keys) {
      if (!b.containsKey(key) || a[key] != b[key]) return false;
    }
    return true;
  }
  return a == b;
}
