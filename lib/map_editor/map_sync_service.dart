import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:tech_world/flame/maps/barrier_occlusion.dart'
    show buildWallTilesForRegion;
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
  Completer<void>? _syncCompleter;
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

  /// Paint a wall at (x, y) using the active wall style.
  ///
  /// Follows the terrain pattern: capture old state for affected cells,
  /// apply locally, diff to produce semantic (walls) + visual (objects) ops.
  /// Wall bitmask uses 4 cardinal neighbors, plus cap tiles one row above.
  void paintWall(int x, int y) {
    if (!_inBounds(x, y)) return;

    final counter = _undoManager.nextCounter();
    final ops = <MapEditOp>[];

    final affectedCells = _wallAffectedCells(x, y);

    // Capture old state: wall styles, structure, and object layer tiles.
    final oldWalls = <(int, int), String?>{};
    final oldStructure = <(int, int), String?>{};
    final oldObjects = <(int, int), TileRef?>{};
    for (final (cx, cy) in affectedCells) {
      oldWalls[(cx, cy)] = _editorState.wallStyleAt(cx, cy);
      oldStructure[(cx, cy)] = _structureToValue(_editorState.tileAt(cx, cy));
    }
    // Object layer: also capture cap positions (y-1 for each cell).
    final objectCells = _wallObjectCells(affectedCells);
    for (final (cx, cy) in objectCells) {
      oldObjects[(cx, cy)] = _editorState.objectLayerData.tileAt(cx, cy);
    }

    // Apply locally.
    _editorState.paintTile(x, y);

    // Recompute object layer tiles for affected wall cells.
    final wallTiles = buildWallTilesForRegion(
      _editorState.wallMap,
      affectedCells.toSet(),
    );
    for (final entry in wallTiles.entries) {
      _editorState.objectLayerData.setTile(
        entry.key.$1,
        entry.key.$2,
        entry.value,
      );
    }

    // Diff: wall layer ops.
    for (final (cx, cy) in affectedCells) {
      final newWall = _editorState.wallStyleAt(cx, cy);
      if (oldWalls[(cx, cy)] != newWall) {
        ops.add(MapEditOp(
          playerId: _localPlayerId,
          counter: counter,
          x: cx,
          y: cy,
          layer: OpLayer.walls,
          oldValue: oldWalls[(cx, cy)],
          newValue: newWall,
        ));
      }

      // Structure ops (wall implies barrier).
      final newStructure = _structureToValue(_editorState.tileAt(cx, cy));
      if (oldStructure[(cx, cy)] != newStructure) {
        ops.add(MapEditOp(
          playerId: _localPlayerId,
          counter: counter,
          x: cx,
          y: cy,
          layer: OpLayer.structure,
          oldValue: oldStructure[(cx, cy)],
          newValue: newStructure,
        ));
      }
    }

    // Diff: object layer ops (includes cap positions).
    for (final (cx, cy) in objectCells) {
      final newObj = wallTiles[(cx, cy)] ?? _editorState.objectLayerData.tileAt(cx, cy);
      final oldObjVal = tileRefToOpValue(oldObjects[(cx, cy)]);
      final newObjVal = tileRefToOpValue(newObj);
      if (!opValueEquals(oldObjVal, newObjVal)) {
        ops.add(MapEditOp(
          playerId: _localPlayerId,
          counter: counter,
          x: cx,
          y: cy,
          layer: OpLayer.objects,
          oldValue: oldObjVal,
          newValue: newObjVal,
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

  /// Erase a wall at (x, y).
  ///
  /// Removes the wall style and barrier, then recomputes neighbor tiles.
  void eraseWall(int x, int y) {
    if (!_inBounds(x, y)) return;

    final counter = _undoManager.nextCounter();
    final ops = <MapEditOp>[];

    final affectedCells = _wallAffectedCells(x, y);

    // Capture old state.
    final oldWalls = <(int, int), String?>{};
    final oldStructure = <(int, int), String?>{};
    final oldObjects = <(int, int), TileRef?>{};
    for (final (cx, cy) in affectedCells) {
      oldWalls[(cx, cy)] = _editorState.wallStyleAt(cx, cy);
      oldStructure[(cx, cy)] = _structureToValue(_editorState.tileAt(cx, cy));
    }
    final objectCells = _wallObjectCells(affectedCells);
    for (final (cx, cy) in objectCells) {
      oldObjects[(cx, cy)] = _editorState.objectLayerData.tileAt(cx, cy);
    }

    // Apply locally (eraser tool removes wall + barrier).
    _editorState.paintTile(x, y);

    // Recompute object layer tiles for affected cells.
    final wallTiles = buildWallTilesForRegion(
      _editorState.wallMap,
      affectedCells.toSet(),
    );
    for (final entry in wallTiles.entries) {
      _editorState.objectLayerData.setTile(
        entry.key.$1,
        entry.key.$2,
        entry.value,
      );
    }

    // Diff: wall layer ops.
    for (final (cx, cy) in affectedCells) {
      final newWall = _editorState.wallStyleAt(cx, cy);
      if (oldWalls[(cx, cy)] != newWall) {
        ops.add(MapEditOp(
          playerId: _localPlayerId,
          counter: counter,
          x: cx,
          y: cy,
          layer: OpLayer.walls,
          oldValue: oldWalls[(cx, cy)],
          newValue: newWall,
        ));
      }

      final newStructure = _structureToValue(_editorState.tileAt(cx, cy));
      if (oldStructure[(cx, cy)] != newStructure) {
        ops.add(MapEditOp(
          playerId: _localPlayerId,
          counter: counter,
          x: cx,
          y: cy,
          layer: OpLayer.structure,
          oldValue: oldStructure[(cx, cy)],
          newValue: newStructure,
        ));
      }
    }

    for (final (cx, cy) in objectCells) {
      final newObj = wallTiles[(cx, cy)] ?? _editorState.objectLayerData.tileAt(cx, cy);
      final oldObjVal = tileRefToOpValue(oldObjects[(cx, cy)]);
      final newObjVal = tileRefToOpValue(newObj);
      if (!opValueEquals(oldObjVal, newObjVal)) {
        ops.add(MapEditOp(
          playerId: _localPlayerId,
          counter: counter,
          x: cx,
          y: cy,
          layer: OpLayer.objects,
          oldValue: oldObjVal,
          newValue: newObjVal,
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
      final oldStructure = _structureToValue(_editorState.tileAt(x, y));
      _editorState.paintTileRef(x, y);
      final newRef = layerData.tileAt(x, y);
      if (!opValueEquals(tileRefToOpValue(oldRef), tileRefToOpValue(newRef))) {
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
      // Capture auto-barrier removal on the structure grid.
      final newStructure = _structureToValue(_editorState.tileAt(x, y));
      if (oldStructure != newStructure) {
        ops.add(MapEditOp(
          playerId: _localPlayerId,
          counter: counter,
          x: x,
          y: y,
          layer: OpLayer.structure,
          oldValue: oldStructure,
          newValue: newStructure,
        ));
      }
    } else {
      // Multi-tile brush — capture all cells in footprint.
      final oldRefs = <(int, int), TileRef?>{};
      final oldStructures = <(int, int), String?>{};
      for (var dy = 0; dy < brush.height; dy++) {
        for (var dx = 0; dx < brush.width; dx++) {
          final tx = x + dx;
          final ty = y + dy;
          if (_inBounds(tx, ty)) {
            oldRefs[(tx, ty)] = layerData.tileAt(tx, ty);
            oldStructures[(tx, ty)] =
                _structureToValue(_editorState.tileAt(tx, ty));
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
        if (!opValueEquals(oldVal, newVal)) {
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
        // Capture auto-barrier side-effects on the structure grid.
        final newStructure =
            _structureToValue(_editorState.tileAt(tx, ty));
        if (oldStructures[(tx, ty)] != newStructure) {
          ops.add(MapEditOp(
            playerId: _localPlayerId,
            counter: counter,
            x: tx,
            y: ty,
            layer: OpLayer.structure,
            oldValue: oldStructures[(tx, ty)],
            newValue: newStructure,
          ));
        }
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
      if (!opValueEquals(oldFloorVal, newFloorVal)) {
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
      if (!opValueEquals(oldFloorVal, newFloorVal)) {
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
  /// Buffers incoming edits during sync to avoid races. Completes when
  /// a sync response arrives or after a 5-second timeout (e.g., no other
  /// editors are present).
  Future<void> requestSync() async {
    _isSyncing = true;
    _syncBuffer.clear();
    _syncCompleter = Completer<void>();

    await _liveKitService.publishJson(
      {'type': 'sync-request', 'playerId': _localPlayerId},
      topic: _syncTopic,
      reliable: true,
    );

    // Complete on sync-response (via _handleSyncResponse) or timeout.
    await _syncCompleter!.future
        .timeout(const Duration(seconds: 5), onTimeout: () {})
        .whenComplete(() => _flushSyncBuffer());
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
      case OpLayer.walls:
        _editorState.setWall(op.x, op.y, op.newValue as String?);
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

    // Apply walls and regenerate their object layer tiles.
    final walls = json['walls'] as List<dynamic>? ?? [];
    for (final entry in walls) {
      final map = entry as Map<String, dynamic>;
      _editorState.setWall(
        map['x'] as int,
        map['y'] as int,
        map['s'] as String,
      );
    }
    if (walls.isNotEmpty) {
      // Regenerate all wall object tiles from the synced wall data.
      final allWallCells = _editorState.wallMap.keys.toSet();
      final wallTiles = buildWallTilesForRegion(
        _editorState.wallMap,
        allWallCells,
      );
      for (final entry in wallTiles.entries) {
        _editorState.objectLayerData.setTile(
          entry.key.$1,
          entry.key.$2,
          entry.value,
        );
      }
    }

    // Load version map.
    final versions = json['versions'] as Map<String, dynamic>? ?? {};
    _versionMap.loadFromJson(versions);

    // Advance clock.
    final remoteClock = json['clock'] as int? ?? 0;
    _undoManager.advanceClock(remoteClock);

    _editorState.notifyRemoteChange();

    // Complete the sync request future early (before timeout).
    if (_syncCompleter != null && !_syncCompleter!.isCompleted) {
      _syncCompleter!.complete();
    }
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

    // Walls: sparse list of (x, y, style ID).
    final wallMap = _editorState.wallMap;
    final walls = <Map<String, dynamic>>[];
    for (final entry in wallMap.entries) {
      final (x, y) = entry.key;
      walls.add({'x': x, 'y': y, 's': entry.value});
    }

    return {
      'type': 'sync-response',
      'structure': structure,
      'floor': floor,
      'objects': objects,
      'terrain': terrain,
      'walls': walls,
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

  /// Cells affected by a wall paint at (x, y): target + 4 cardinal neighbors.
  ///
  /// Wall bitmask is cardinal-only (N/E/S/W), so only those neighbors need
  /// recomputation when a wall changes.
  List<(int, int)> _wallAffectedCells(int x, int y) {
    final cells = <(int, int)>[(x, y)];
    for (final (dx, dy) in const [
      (0, -1), // N
      (1, 0), // E
      (0, 1), // S
      (-1, 0), // W
    ]) {
      final nx = x + dx;
      final ny = y + dy;
      if (_inBounds(nx, ny)) cells.add((nx, ny));
    }
    return cells;
  }

  /// All cells whose object layer tiles might change due to wall edits.
  ///
  /// Includes each affected cell plus the row above (for cap tiles placed
  /// above north-facing walls).
  Set<(int, int)> _wallObjectCells(List<(int, int)> wallCells) {
    final result = <(int, int)>{};
    for (final (cx, cy) in wallCells) {
      result.add((cx, cy));
      if (_inBounds(cx, cy - 1)) result.add((cx, cy - 1));
    }
    return result;
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

