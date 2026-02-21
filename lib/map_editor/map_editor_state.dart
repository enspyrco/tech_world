import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:tech_world/flame/maps/game_map.dart';
import 'package:tech_world/flame/maps/map_parser.dart';
import 'package:tech_world/flame/shared/constants.dart';
import 'package:tech_world/flame/tiles/tile_brush.dart';
import 'package:tech_world/flame/tiles/tile_layer_data.dart';
import 'package:tech_world/flame/tiles/tile_ref.dart';

/// Tile types that can be painted on the map grid.
enum TileType { open, barrier, spawn, terminal }

/// Tools available in the map editor.
enum EditorTool { barrier, spawn, terminal, eraser }

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

  EditorTool _currentTool = EditorTool.barrier;
  EditorTool get currentTool => _currentTool;

  String _mapName = 'Untitled Map';
  String get mapName => _mapName;

  String _mapId = 'untitled_map';
  String get mapId => _mapId;

  /// Firestore room ID when editing an existing room. Null for new maps.
  String? _roomId;
  String? get roomId => _roomId;

  /// Set the room ID (used when loading from an existing room).
  void setRoomId(String? id) {
    _roomId = id;
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
  // Background image
  // -------------------------------------------------------------------------

  /// Optional background image filename (relative to `assets/images/`).
  String? _backgroundImage;
  String? get backgroundImage => _backgroundImage;

  /// Set the background image filename, or `null` for no background.
  void setBackgroundImage(String? filename) {
    _backgroundImage = filename;
    notifyListeners();
  }

  /// Switch the active editing layer.
  void setActiveLayer(ActiveLayer layer) {
    _activeLayer = layer;
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
  void paintTileRef(int x, int y) {
    if (x < 0 || x >= gridSize || y < 0 || y >= gridSize) return;

    final layer = _activeLayer == ActiveLayer.floor
        ? floorLayerData
        : objectLayerData;

    final brush = _currentBrush;
    if (brush == null) {
      // Eraser — clear single cell.
      layer.setTile(x, y, null);
    } else {
      for (var dy = 0; dy < brush.height; dy++) {
        for (var dx = 0; dx < brush.width; dx++) {
          final tx = x + dx;
          final ty = y + dy;
          if (tx >= 0 && tx < gridSize && ty >= 0 && ty < gridSize) {
            layer.setTile(tx, ty, brush.tileRefAt(dx, dy));
          }
        }
      }
    }
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
    notifyListeners();
  }

  /// Set the map ID.
  void setMapId(String id) {
    _mapId = id;
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
        _grid[y][x] = TileType.barrier;
      case EditorTool.spawn:
        // Remove existing spawn point first (only one allowed).
        _clearTilesOfType(TileType.spawn);
        _grid[y][x] = TileType.spawn;
      case EditorTool.terminal:
        _grid[y][x] = TileType.terminal;
      case EditorTool.eraser:
        _grid[y][x] = TileType.open;
    }
    notifyListeners();
  }

  /// Reset all tiles to open (structure grid only).
  void clearGrid() {
    for (var y = 0; y < gridSize; y++) {
      for (var x = 0; x < gridSize; x++) {
        _grid[y][x] = TileType.open;
      }
    }
    notifyListeners();
  }

  /// Reset all layers including tile data.
  void clearAll() {
    clearGrid();
    _backgroundImage = null;
    _roomId = null;
    _clearTileLayer(floorLayerData);
    _clearTileLayer(objectLayerData);
    notifyListeners();
  }

  /// Load grid state from an existing [GameMap].
  void loadFromGameMap(GameMap map) {
    clearGrid();
    _mapName = map.name;
    _mapId = map.id;
    _backgroundImage = map.backgroundImage;

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

    // Load tile layers if present.
    _clearTileLayer(floorLayerData);
    _clearTileLayer(objectLayerData);

    if (map.floorLayer != null) {
      _copyTileLayer(map.floorLayer!, floorLayerData);
    }
    if (map.objectLayer != null) {
      _copyTileLayer(map.objectLayer!, objectLayerData);
    }

    notifyListeners();
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
      backgroundImage: _backgroundImage,
      floorLayer: floorLayerData.isEmpty ? null : floorLayerData,
      objectLayer: objectLayerData.isEmpty ? null : objectLayerData,
      tilesetIds: tilesetIds,
    );
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
}
