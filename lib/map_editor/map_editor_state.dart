import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:tiled/tiled.dart' as tiled;
import 'package:tech_world/flame/maps/door_data.dart';
import 'package:tech_world/flame/maps/game_map.dart';
import 'package:tech_world/flame/maps/terminal_mode.dart';
import 'package:tech_world/flame/maps/map_parser.dart';
import 'package:tech_world/flame/maps/tmx_importer.dart';
import 'package:tech_world/flame/shared/constants.dart';
import 'package:tech_world/flame/tiles/predefined_tilesets.dart'
    show allTilesets;
import 'package:tech_world/flame/tiles/terrain_bitmask.dart';
import 'package:tech_world/flame/tiles/predefined_terrains.dart';
import 'package:tech_world/flame/tiles/terrain_def.dart';
import 'package:tech_world/flame/tiles/predefined_tilesets.dart'
    show isTileRefBarrier, isTileRefNonBarrier;
import 'package:tech_world/flame/tiles/tileset_registry.dart';
import 'package:tech_world/flame/tiles/tile_brush.dart';
import 'package:tech_world/flame/tiles/tile_layer_data.dart';
import 'package:tech_world/flame/tiles/tile_ref.dart';
import 'package:tech_world/flame/tiles/tileset.dart';
import 'package:tech_world/map_editor/automap_engine.dart';
import 'package:tech_world/map_editor/automap_rule.dart';
import 'package:tech_world/map_editor/terrain_grid.dart';

/// Tile types that can be painted on the map grid.
enum TileType { open, barrier, spawn, terminal }

/// Tools available in the map editor.
enum EditorTool { barrier, wall, spawn, terminal, door, eraser }

/// Which layer is active for editing.
enum ActiveLayer {
  /// Structural layer — barriers, spawn, terminals (classic grid).
  structure,

  /// Floor tile layer — rendered below everything.
  floor,

  /// Object tile layer — rendered with y-sorted priority.
  objects,
}

/// State model for the visual map editor.
///
/// Holds a [gridSize] x [gridSize] grid of [TileType] values and provides
/// methods for painting, importing from existing maps, and exporting to
/// ASCII art or [GameMap] objects.
///
/// Also manages tile layers for tileset-based maps. The [activeLayer]
/// determines whether painting affects the structure grid or a tile layer.
class MapEditorState extends ChangeNotifier {
  MapEditorState()
      : _grid = List.generate(
          gridSize,
          (_) => List.filled(gridSize, TileType.open),
        );

  final List<List<TileType>> _grid;

  /// Optional tileset registry for computed barrier analysis.
  ///
  /// When set, the auto-barrier logic uses pixel-based analysis from the
  /// registry as a fallback for tilesets without hand-curated barrier data
  /// (e.g. custom imported tilesets).
  TilesetRegistry? _tilesetRegistry;

  /// Set the tileset registry for computed barrier analysis.
  // ignore: use_setters_to_change_properties
  void setTilesetRegistry(TilesetRegistry? registry) {
    _tilesetRegistry = registry;
  }

  /// Whether the editor has unsaved changes since the last load/save.
  bool _isDirty = false;
  bool get isDirty => _isDirty;

  /// Mark the editor as having unsaved changes. Called by mutating methods.
  void _markDirty() {
    if (!_isDirty) {
      _isDirty = true;
      // Don't notifyListeners — the caller's mutating method will do that.
    }
  }

  /// Reset the dirty flag (after a successful save or load).
  void markClean() {
    _isDirty = false;
  }

  EditorTool _currentTool = EditorTool.barrier;
  EditorTool get currentTool => _currentTool;

  String _mapName = 'Untitled Map';
  String get mapName => _mapName;

  String _mapId = 'untitled_map';
  String get mapId => _mapId;

  TerminalMode _terminalMode = TerminalMode.code;

  /// Firestore room ID when editing an existing room. Null for new maps.
  String? _roomId;
  String? get roomId => _roomId;

  /// Set the room ID (used when loading from an existing room).
  void setRoomId(String? id) {
    _roomId = id;
  }

  // -------------------------------------------------------------------------
  // Custom tileset state
  // -------------------------------------------------------------------------

  /// Custom tilesets imported from zip bundles (not predefined in assets).
  List<Tileset> _customTilesets = [];

  /// Unmodifiable view of custom tilesets for external consumers.
  List<Tileset> get customTilesets => List.unmodifiable(_customTilesets);

  /// Raw PNG bytes for custom tileset images, keyed by [Tileset.imagePath].
  ///
  /// Populated during import and used for Firebase upload and TilePalette
  /// rendering. Cleared on [clearAll].
  Map<String, Uint8List> _customTilesetBytes = {};

  /// Unmodifiable view of custom tileset image bytes.
  Map<String, Uint8List> get customTilesetBytes =>
      Map.unmodifiable(_customTilesetBytes);

  /// Set custom tileset data directly (used by import and tests).
  void setCustomTilesetData(
    List<Tileset> tilesets,
    Map<String, Uint8List> bytes,
  ) {
    _customTilesets = List.of(tilesets);
    _customTilesetBytes = Map.of(bytes);
    notifyListeners();
  }

  // -------------------------------------------------------------------------
  // Tile layer state
  // -------------------------------------------------------------------------

  ActiveLayer _activeLayer = ActiveLayer.structure;
  ActiveLayer get activeLayer => _activeLayer;

  /// Floor tile layer data.
  final TileLayerData floorLayerData = TileLayerData();

  /// Object tile layer data.
  final TileLayerData objectLayerData = TileLayerData();

  /// The currently selected tile brush for painting on tile layers.
  ///
  /// A [TileBrush] can represent a single tile (1×1) or a rectangular
  /// multi-tile selection. Use [setBrush] for arbitrary sizes, or
  /// [setTileBrush] as a convenience for single-tile selections.
  TileBrush? _currentBrush;
  TileBrush? get currentBrush => _currentBrush;

  // -------------------------------------------------------------------------
  // Wall state
  // -------------------------------------------------------------------------

  /// Wall positions mapped to style IDs. Every wall is also a barrier.
  final Map<(int, int), String> _walls = {};

  /// The style applied when painting walls.
  String _wallStyle = 'modern_gray_07';
  String get wallStyle => _wallStyle;
  set wallStyle(String style) {
    _wallStyle = style;
    notifyListeners();
  }

  /// Whether a wall exists at ([x], [y]).
  bool isWallAt(int x, int y) => _walls.containsKey((x, y));

  /// The wall style at ([x], [y]), or null if no wall.
  String? wallStyleAt(int x, int y) => _walls[(x, y)];

  /// Unmodifiable view of all wall positions and their style IDs.
  ///
  /// Used by [MapSyncService] to read wall state for sync and tile generation.
  Map<(int, int), String> get wallMap => Map.unmodifiable(_walls);

  /// Set or remove a wall at ([x], [y]) with the given [styleId].
  ///
  /// Called by [MapSyncService] when applying remote wall edits. Also updates
  /// the structure grid (walls imply barriers). Pass `null` to remove.
  void setWall(int x, int y, String? styleId) {
    if (!_inBounds(x, y)) return;
    if (styleId != null) {
      _walls[(x, y)] = styleId;
      _grid[y][x] = TileType.barrier;
    } else {
      _walls.remove((x, y));
      // Only clear barrier if this was a wall-barrier (not a plain barrier).
      // The structure op handles barrier state separately, so leave it.
    }
  }

  // -------------------------------------------------------------------------
  // Door state
  // -------------------------------------------------------------------------

  /// Door positions mapped to [DoorData]. Every door is also a barrier
  /// when locked.
  final Map<(int, int), DoorData> _doors = {};

  /// Whether a door exists at ([x], [y]).
  bool isDoorAt(int x, int y) => _doors.containsKey((x, y));

  /// The door data at ([x], [y]), or null if no door.
  DoorData? doorAt(int x, int y) => _doors[(x, y)];

  /// Unmodifiable view of all door positions and their data.
  Map<(int, int), DoorData> get doorMap => Map.unmodifiable(_doors);

  // -------------------------------------------------------------------------
  // Terrain brush state
  // -------------------------------------------------------------------------

  /// Parallel grid tracking which terrain type each cell belongs to.
  ///
  /// Used during editing to determine bitmask values. At runtime, the
  /// [TileLayerData] is self-sufficient — this is only needed for editor
  /// round-trips.
  final TerrainGrid terrainGrid = TerrainGrid();

  // -------------------------------------------------------------------------
  // Automap state
  // -------------------------------------------------------------------------

  /// Tracks cells that were auto-generated by automap rules (ephemeral).
  final Set<(int, int)> _automappedCells = {};

  /// Tracks structure-grid barriers that were auto-created from visual tiles.
  ///
  /// Only cells in this set are eligible for automatic removal on erase.
  /// Manual barriers, spawn points, and terminals are never added here.
  final Set<(int, int)> _autoBarrierCells = {};

  /// The currently active auto-terrain brush, or `null` for manual tile mode.
  TerrainDef? _activeTerrainBrush;
  TerrainDef? get activeTerrainBrush => _activeTerrainBrush;

  /// Set the active terrain brush for auto-terrain painting.
  ///
  /// Pass `null` to return to manual tile palette mode.
  void setTerrainBrush(TerrainDef? terrain) {
    _activeTerrainBrush = terrain;
    notifyListeners();
  }


  /// Paint auto-terrain at ([x], [y]) using the active terrain brush.
  ///
  /// Sets the terrain in the [terrainGrid], then re-evaluates this cell and
  /// all 8 neighbors to update the floor tile layer with the correct bitmask
  /// tiles. Notifies listeners once.
  void paintTerrain(int x, int y) {
    if (!_inBounds(x, y)) return;
    final terrain = _activeTerrainBrush;
    if (terrain == null) return;

    terrainGrid.setTerrain(x, y, terrain.id);

    // Re-evaluate target cell + all 8 Moore neighbors.
    _reevaluateTerrainCell(x, y, terrain);
    for (final (dx, dy) in Bitmask.offsets) {
      final nx = x + dx;
      final ny = y + dy;
      if (_inBounds(nx, ny) && terrainGrid.isTerrainAt(nx, ny, terrain.id)) {
        _reevaluateTerrainCell(nx, ny, terrain);
      }
    }

    _markDirty();
    notifyListeners();
  }

  /// Erase terrain at ([x], [y]) and update neighbors.
  ///
  /// Clears the terrain from the grid and the tile from the floor layer,
  /// then re-evaluates all 8 neighbors.
  void eraseTerrainAt(int x, int y) {
    if (!_inBounds(x, y)) return;

    final terrainId = terrainGrid.terrainAt(x, y);
    if (terrainId == null) return;

    terrainGrid.setTerrain(x, y, null);
    floorLayerData.setTile(x, y, null);

    // Look up the terrain def by ID so erasure works regardless of the
    // currently selected brush (fixes stale tiles when brush is switched).
    final terrain = lookupTerrain(terrainId);

    // Re-evaluate neighbors that might have been affected.
    for (final (dx, dy) in Bitmask.offsets) {
      final nx = x + dx;
      final ny = y + dy;
      if (_inBounds(nx, ny) &&
          terrain != null &&
          terrainGrid.isTerrainAt(nx, ny, terrainId)) {
        _reevaluateTerrainCell(nx, ny, terrain);
      }
    }

    _markDirty();
    notifyListeners();
  }

  /// Re-evaluate a single cell's tile based on its terrain bitmask.
  void _reevaluateTerrainCell(int x, int y, TerrainDef terrain) {
    final bitmask = computeBitmask(
      x,
      y,
      (nx, ny) => terrainGrid.isTerrainAt(nx, ny, terrain.id),
    );
    final tileIndex = terrain.tileIndexForBitmask(bitmask);
    if (tileIndex != null) {
      floorLayerData.setTile(
        x,
        y,
        TileRef(tilesetId: terrain.tilesetId, tileIndex: tileIndex),
      );
    }
  }


  /// Switch the active editing layer.
  ///
  /// Clears the current brush if its tileset is not available on the new layer
  /// or if the brush's rows are not visible on the new layer, preventing an
  /// invisible brush from painting tiles.
  void setActiveLayer(ActiveLayer layer) {
    _activeLayer = layer;
    if (_currentBrush != null) {
      final tileset = allTilesets
              .where((ts) => ts.id == _currentBrush!.tilesetId)
              .firstOrNull ??
          _customTilesets
              .where((ts) => ts.id == _currentBrush!.tilesetId)
              .firstOrNull;
      if (tileset == null || !tileset.availableLayers.contains(layer)) {
        _currentBrush = null;
      } else {
        // Check that all brush rows are visible on the new layer.
        final brush = _currentBrush!;
        for (var r = brush.startRow; r < brush.startRow + brush.height; r++) {
          if (!tileset.isRowVisibleForLayer(r, layer)) {
            _currentBrush = null;
            break;
          }
        }
      }
    }
    notifyListeners();
  }

  /// Set the tile brush to a rectangular selection.
  void setBrush(TileBrush? brush) {
    _currentBrush = brush;
    notifyListeners();
  }

  /// Convenience: set a single-tile brush from a [TileRef].
  ///
  /// The [columns] parameter is required so that the tile index can be
  /// correctly decomposed into column/row coordinates.
  /// Pass `null` for [ref] to select the eraser.
  void setTileBrush(TileRef? ref, {required int columns}) {
    if (ref == null) {
      _currentBrush = null;
    } else {
      _currentBrush = TileBrush(
        tilesetId: ref.tilesetId,
        startCol: ref.tileIndex % columns,
        startRow: ref.tileIndex ~/ columns,
        columns: columns,
      );
    }
    notifyListeners();
  }

  /// Paint the current brush at (x, y) on the active tile layer.
  ///
  /// For a multi-tile brush, (x, y) is the top-left anchor and all tiles
  /// within the brush rectangle are stamped. Eraser (`null` brush) clears
  /// a single cell.
  ///
  /// When painting on a visual layer (floor or objects), tiles tagged as
  /// barriers in their tileset automatically create barriers on the structure
  /// grid. Erasing checks both layers before removing an auto-barrier.
  void paintTileRef(int x, int y) {
    if (x < 0 || x >= gridSize || y < 0 || y >= gridSize) return;

    final isObjectLayer = _activeLayer == ActiveLayer.objects;
    final layer = isObjectLayer ? objectLayerData : floorLayerData;

    final brush = _currentBrush;
    if (brush == null) {
      // Eraser — clear single cell, then check auto-barrier removal.
      layer.setTile(x, y, null);
      _automappedCells.remove((x, y));
      _maybeRemoveAutoBarrier(x, y);
    } else {
      for (var dy = 0; dy < brush.height; dy++) {
        for (var dx = 0; dx < brush.width; dx++) {
          final tx = x + dx;
          final ty = y + dy;
          if (tx >= 0 && tx < gridSize && ty >= 0 && ty < gridSize) {
            final ref = brush.tileRefAt(dx, dy);
            layer.setTile(tx, ty, ref);
            // If the user paints over an automap-generated cell, stop
            // tracking it so re-apply won't erase the manual edit.
            _automappedCells.remove((tx, ty));
            _maybeCreateAutoBarrier(tx, ty, ref,
                isObjectLayer: isObjectLayer);
          }
        }
      }
    }
    _markDirty();
    notifyListeners();
  }

  // -------------------------------------------------------------------------
  // Automapping
  // -------------------------------------------------------------------------

  /// Apply automap [rules] to the grid.
  ///
  /// Clears previous auto-generated tiles, evaluates rules against the
  /// current structure grid, and places resulting tiles on the object layer.
  /// Skips cells with existing manual tiles.
  void applyAutomapRules(List<AutomapRule> rules) {
    // Clear previous auto-generated tiles.
    for (final (x, y) in _automappedCells) {
      objectLayerData.setTile(x, y, null);
    }
    _automappedCells.clear();

    final result = evaluateRules(
      rules: rules,
      structureAt: tileAt,
      objectTileAt: objectLayerData.tileAt,
    );

    for (final entry in result.placements.entries) {
      final (x, y) = entry.key;
      // Skip cells with existing manual tiles.
      if (objectLayerData.tileAt(x, y) != null) continue;
      objectLayerData.setTile(x, y, entry.value);
      _automappedCells.add((x, y));
    }

    _markDirty();
    notifyListeners();
  }

  /// Remove only auto-generated tiles, preserving manual placements.
  void clearAutomapTiles() {
    for (final (x, y) in _automappedCells) {
      objectLayerData.setTile(x, y, null);
    }
    _automappedCells.clear();
    _markDirty();
    notifyListeners();
  }

  // -------------------------------------------------------------------------
  // Structure grid (original functionality)
  // -------------------------------------------------------------------------

  /// Read-only access to the grid.
  TileType tileAt(int x, int y) {
    if (x < 0 || x >= gridSize || y < 0 || y >= gridSize) {
      return TileType.open;
    }
    return _grid[y][x];
  }

  /// Set the current painting tool.
  void setTool(EditorTool tool) {
    _currentTool = tool;
    notifyListeners();
  }

  /// Set the map name.
  void setMapName(String name) {
    _mapName = name;
    _markDirty();
    notifyListeners();
  }

  /// Set the map ID.
  void setMapId(String id) {
    _mapId = id;
    _markDirty();
    notifyListeners();
  }

  /// Paint a tile at (x, y) using the current tool.
  ///
  /// Enforces single-spawn constraint: painting a new spawn removes the old one.
  /// Out-of-bounds coordinates are silently ignored.
  void paintTile(int x, int y) {
    if (x < 0 || x >= gridSize || y < 0 || y >= gridSize) return;

    switch (_currentTool) {
      case EditorTool.barrier:
        _walls.remove((x, y)); // plain barrier overrides any wall
        _grid[y][x] = TileType.barrier;
      case EditorTool.wall:
        _walls[(x, y)] = _wallStyle;
        _grid[y][x] = TileType.barrier; // wall implies barrier
      case EditorTool.spawn:
        _clearTilesOfType(TileType.spawn);
        _grid[y][x] = TileType.spawn;
      case EditorTool.terminal:
        _grid[y][x] = TileType.terminal;
      case EditorTool.door:
        _doors[(x, y)] = DoorData(position: Point(x, y));
        _grid[y][x] = TileType.barrier; // doors block movement when locked
      case EditorTool.eraser:
        _walls.remove((x, y));
        _doors.remove((x, y));
        _grid[y][x] = TileType.open;
    }
    _markDirty();
    notifyListeners();
  }

  /// Reset all tiles to open (structure grid only).
  void clearGrid() {
    for (var y = 0; y < gridSize; y++) {
      for (var x = 0; x < gridSize; x++) {
        _grid[y][x] = TileType.open;
      }
    }
    _walls.clear();
    _doors.clear();
    _autoBarrierCells.clear();
    _markDirty();
    notifyListeners();
  }

  /// Reset all layers including tile data.
  void clearAll() {
    clearGrid(); // Already calls _markDirty().
    _roomId = null;
    _activeTerrainBrush = null;
    _automappedCells.clear();
    _autoBarrierCells.clear();
    terrainGrid.clear();
    _clearTileLayer(floorLayerData);
    _clearTileLayer(objectLayerData);
    _customTilesets = [];
    _customTilesetBytes = {};
    notifyListeners();
  }

  /// Load grid state from an existing [GameMap].
  ///
  /// Resets the dirty flag since this is a "fresh start" from a saved state.
  void loadFromGameMap(GameMap map) {
    clearGrid();
    _autoBarrierCells.clear();
    _automappedCells.clear();
    _mapName = map.name;
    _mapId = map.id;
    _terminalMode = map.terminalMode;

    for (final barrier in map.barriers) {
      if (_inBounds(barrier.x, barrier.y)) {
        _grid[barrier.y][barrier.x] = TileType.barrier;
      }
    }

    if (_inBounds(map.spawnPoint.x, map.spawnPoint.y)) {
      _grid[map.spawnPoint.y][map.spawnPoint.x] = TileType.spawn;
    }

    for (final terminal in map.terminals) {
      if (_inBounds(terminal.x, terminal.y)) {
        _grid[terminal.y][terminal.x] = TileType.terminal;
      }
    }

    // Load walls if present.
    _walls.clear();
    for (final entry in map.walls.entries) {
      final p = entry.key;
      if (_inBounds(p.x, p.y)) {
        _walls[(p.x, p.y)] = entry.value;
      }
    }

    // Load doors if present.
    _doors.clear();
    for (final door in map.doors) {
      final p = door.position;
      if (_inBounds(p.x, p.y)) {
        _doors[(p.x, p.y)] = door;
      }
    }

    // Load tile layers if present.
    _clearTileLayer(floorLayerData);
    _clearTileLayer(objectLayerData);

    if (map.floorLayer != null) {
      _copyTileLayer(map.floorLayer!, floorLayerData);
    }
    if (map.objectLayer != null) {
      _copyTileLayer(map.objectLayer!, objectLayerData);
    }

    // Load terrain grid if present.
    terrainGrid.clear();
    if (map.terrainGrid != null) {
      _copyTerrainGrid(map.terrainGrid!, terrainGrid);
    }

    // Restore custom tilesets from the map (bytes may already be loaded
    // from a prior import). Always assign to clear stale data when loading
    // a map without custom tilesets.
    _customTilesets = List.of(map.customTilesets);

    _isDirty = false; // Fresh load — no unsaved changes.
    notifyListeners();
  }

  /// Import a Tiled `.tmx` XML string into the editor.
  ///
  /// Parses the TMX via [TmxImporter], loads the resulting [GameMap], and
  /// returns any non-fatal warnings for the caller to display.
  List<TmxImportWarning> loadFromTmx(
    String tmxXml, {
    String? mapId,
    String? mapName,
  }) {
    final result = TmxImporter.import(
      tmxXml,
      mapId: mapId,
      mapName: mapName,
    );
    loadFromGameMap(result.gameMap);
    return result.warnings;
  }

  /// Import a Tiled `.tmx` XML string with custom tileset images.
  ///
  /// Like [loadFromTmx] but accepts [customImages] (image source → PNG bytes)
  /// and optional [tsxProviders] for external TSX resolution.
  ///
  /// Returns the import result including custom [Tileset] objects that need
  /// to be registered with [TilesetRegistry.loadFromImage] by the caller.
  TmxImportResultWithCustomTilesets loadFromTmxWithCustomTilesets(
    String tmxXml, {
    Map<String, Uint8List> customImages = const {},
    List<tiled.TsxProvider>? tsxProviders,
    String? mapId,
    String? mapName,
  }) {
    final result = TmxImporter.importWithCustomTilesets(
      tmxXml,
      customImages: customImages,
      tsxProviders: tsxProviders,
      mapId: mapId,
      mapName: mapName,
    );
    loadFromGameMap(result.gameMap);

    // Store custom tileset metadata and image bytes for persistence and
    // tile palette rendering.
    _customTilesets = List.of(result.customTilesets);
    _customTilesetBytes = Map.of(result.customImageBytes);

    return result;
  }

  /// Load grid state from an ASCII art string (same format as [parseAsciiMap]).
  ///
  /// Characters: `.` = open, `#` = barrier, `S` = spawn, `T` = terminal.
  void loadFromAscii(String ascii) {
    clearGrid();

    var lines = ascii.split('\n');
    // Trim leading/trailing blank lines.
    while (lines.isNotEmpty && lines.first.trim().isEmpty) {
      lines = lines.sublist(1);
    }
    while (lines.isNotEmpty && lines.last.trim().isEmpty) {
      lines = lines.sublist(0, lines.length - 1);
    }

    for (var y = 0; y < lines.length && y < gridSize; y++) {
      final line = lines[y];
      for (var x = 0; x < line.length && x < gridSize; x++) {
        switch (line[x]) {
          case '#':
            _grid[y][x] = TileType.barrier;
          case 'S':
            _clearTilesOfType(TileType.spawn);
            _grid[y][x] = TileType.spawn;
          case 'T':
            _grid[y][x] = TileType.terminal;
          default:
            _grid[y][x] = TileType.open;
        }
      }
    }
    _isDirty = false; // Fresh load — no unsaved changes.
    notifyListeners();
  }

  /// Export the grid as an ASCII art string compatible with [parseAsciiMap].
  String toAsciiString() {
    final buffer = StringBuffer();
    for (var y = 0; y < gridSize; y++) {
      for (var x = 0; x < gridSize; x++) {
        buffer.write(_tileToChar(_grid[y][x]));
      }
      if (y < gridSize - 1) buffer.write('\n');
    }
    return buffer.toString();
  }

  /// Export the grid as a [GameMap] for live preview.
  GameMap toGameMap() {
    final barriers = <Point<int>>[];
    final terminals = <Point<int>>[];
    Point<int>? spawnPoint;

    for (var y = 0; y < gridSize; y++) {
      for (var x = 0; x < gridSize; x++) {
        switch (_grid[y][x]) {
          case TileType.barrier:
            barriers.add(Point(x, y));
          case TileType.spawn:
            spawnPoint = Point(x, y);
          case TileType.terminal:
            terminals.add(Point(x, y));
          case TileType.open:
            break;
        }
      }
    }

    // Collect tileset IDs from both layers.
    final tilesetIds = <String>{
      ...floorLayerData.referencedTilesetIds,
      ...objectLayerData.referencedTilesetIds,
    }.toList();

    return GameMap(
      id: _mapId,
      name: _mapName,
      barriers: barriers,
      spawnPoint: spawnPoint ?? const Point(25, 25),
      terminals: terminals,
      floorLayer: floorLayerData.isEmpty ? null : floorLayerData.copy(),
      objectLayer: objectLayerData.isEmpty ? null : objectLayerData.copy(),
      tilesetIds: tilesetIds,
      terrainGrid: terrainGrid.isEmpty ? null : terrainGrid.copy(),
      customTilesets: List.unmodifiable(_customTilesets),
      walls: {
        for (final entry in _walls.entries)
          Point(entry.key.$1, entry.key.$2): entry.value,
      },
      doors: [
        for (final door in _doors.values) door,
      ],
      terminalMode: _terminalMode,
    );
  }

  // -------------------------------------------------------------------------
  // Auto-barrier helpers
  // -------------------------------------------------------------------------

  /// Create an auto-barrier for a painted tile.
  ///
  /// On the object layer, tiles create barriers unless explicitly marked as
  /// non-blocking (e.g. decorative tops of tall objects). On the floor layer,
  /// only tiles tagged as barriers in their tileset create barriers.
  ///
  /// When a [TilesetRegistry] is set, computed pixel analysis is used as a
  /// fallback for tilesets without hand-curated barrier metadata.
  void _maybeCreateAutoBarrier(int x, int y, TileRef ref,
      {required bool isObjectLayer}) {
    if (isObjectLayer &&
        isTileRefNonBarrier(ref, registry: _tilesetRegistry)) {
      return;
    }
    if (!isObjectLayer &&
        !isTileRefBarrier(ref, registry: _tilesetRegistry)) {
      return;
    }
    if (_grid[y][x] != TileType.open) return;
    _grid[y][x] = TileType.barrier;
    _autoBarrierCells.add((x, y));
  }

  /// If the cell at ([x], [y]) was auto-barriered and no visual layer
  /// still justifies the barrier, revert it to open.
  ///
  /// Justification: object-layer tiles keep the barrier unless explicitly
  /// non-blocking; for the floor layer, only barrier-tagged tiles keep it.
  void _maybeRemoveAutoBarrier(int x, int y) {
    if (!_autoBarrierCells.contains((x, y))) return;

    // Object layer: any tile justifies the barrier, unless non-blocking.
    final objectTile = objectLayerData.tileAt(x, y);
    if (objectTile != null &&
        !isTileRefNonBarrier(objectTile, registry: _tilesetRegistry)) {
      return;
    }

    // Floor layer: only barrier-tagged tiles justify the barrier.
    final floorTile = floorLayerData.tileAt(x, y);
    if (floorTile != null &&
        isTileRefBarrier(floorTile, registry: _tilesetRegistry)) {
      return;
    }

    _grid[y][x] = TileType.open;
    _autoBarrierCells.remove((x, y));
  }

  void _clearTilesOfType(TileType type) {
    for (var y = 0; y < gridSize; y++) {
      for (var x = 0; x < gridSize; x++) {
        if (_grid[y][x] == type) {
          _grid[y][x] = TileType.open;
        }
      }
    }
  }

  // -------------------------------------------------------------------------
  // Remote edit support (called by MapSyncService)
  // -------------------------------------------------------------------------

  /// Directly set a structure grid tile without side effects.
  ///
  /// Used by [MapSyncService] to apply remote edits. Does not call
  /// [notifyListeners], [_markDirty], or enforce the single-spawn constraint.
  void setStructureTile(int x, int y, TileType type) {
    if (!_inBounds(x, y)) return;
    _grid[y][x] = type;
  }

  /// Notify listeners that remote changes have been applied.
  ///
  /// Called by [MapSyncService] after applying a batch of remote edits.
  void notifyRemoteChange() {
    _markDirty();
    notifyListeners();
  }

  bool _inBounds(int x, int y) =>
      x >= 0 && x < gridSize && y >= 0 && y < gridSize;

  static String _tileToChar(TileType tile) {
    switch (tile) {
      case TileType.open:
        return '.';
      case TileType.barrier:
        return '#';
      case TileType.spawn:
        return 'S';
      case TileType.terminal:
        return 'T';
    }
  }

  /// Clear all cells in a tile layer.
  void _clearTileLayer(TileLayerData layer) {
    for (var y = 0; y < gridSize; y++) {
      for (var x = 0; x < gridSize; x++) {
        layer.setTile(x, y, null);
      }
    }
  }

  /// Copy tile data from [source] into [dest].
  void _copyTileLayer(TileLayerData source, TileLayerData dest) {
    for (var y = 0; y < gridSize; y++) {
      for (var x = 0; x < gridSize; x++) {
        dest.setTile(x, y, source.tileAt(x, y));
      }
    }
  }

  /// Copy terrain data from [source] into [dest].
  void _copyTerrainGrid(TerrainGrid source, TerrainGrid dest) {
    for (var y = 0; y < gridSize; y++) {
      for (var x = 0; x < gridSize; x++) {
        dest.setTerrain(x, y, source.terrainAt(x, y));
      }
    }
  }

}
