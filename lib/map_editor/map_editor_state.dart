import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:tech_world/flame/maps/game_map.dart';
import 'package:tech_world/flame/maps/map_parser.dart';
import 'package:tech_world/flame/shared/constants.dart';

/// Tile types that can be painted on the map grid.
enum TileType { open, barrier, spawn, terminal }

/// Tools available in the map editor.
enum EditorTool { barrier, spawn, terminal, eraser }

/// State model for the visual map editor.
///
/// Holds a [gridSize] x [gridSize] grid of [TileType] values and provides
/// methods for painting, importing from existing maps, and exporting to
/// ASCII art or [GameMap] objects.
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

  /// Reset all tiles to open.
  void clearGrid() {
    for (var y = 0; y < gridSize; y++) {
      for (var x = 0; x < gridSize; x++) {
        _grid[y][x] = TileType.open;
      }
    }
    notifyListeners();
  }

  /// Load grid state from an existing [GameMap].
  void loadFromGameMap(GameMap map) {
    clearGrid();
    _mapName = map.name;
    _mapId = map.id;

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

    return GameMap(
      id: _mapId,
      name: _mapName,
      barriers: barriers,
      spawnPoint: spawnPoint ?? const Point(25, 25),
      terminals: terminals,
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
}
