import 'dart:math';

import 'package:tech_world/flame/maps/game_map.dart';
import 'package:tech_world/flame/maps/generators/grid_utils.dart';
import 'package:tech_world/flame/maps/generators/map_generator.dart';
import 'package:tech_world/flame/shared/constants.dart';

/// Generates a dungeon-style map with random rooms connected by corridors.
///
/// Algorithm:
/// 1. Start with a filled (all walls) grid.
/// 2. Place up to [GeneratorConfig.dungeonMaxRooms] non-overlapping rooms.
/// 3. Connect rooms with L-shaped corridors (sorted by center position).
/// 4. Remove any disconnected regions as a safety net.
/// 5. Spawn in the center of the first room.
GameMap generateDungeon({required int seed, required GeneratorConfig config}) {
  final rng = Random(seed);
  final grid = createFilledGrid();
  final rooms = <Rectangle<int>>[];

  // Playable area inset by 1 cell on each side for a solid border.
  const minXY = 1;
  final maxXY = gridSize - 1;

  for (var i = 0; i < config.dungeonMaxRooms; i++) {
    final w =
        config.dungeonMinRoomSize + rng.nextInt(config.dungeonMaxRoomSize - config.dungeonMinRoomSize + 1);
    final h =
        config.dungeonMinRoomSize + rng.nextInt(config.dungeonMaxRoomSize - config.dungeonMinRoomSize + 1);
    final x = minXY + rng.nextInt(maxXY - w - minXY);
    final y = minXY + rng.nextInt(maxXY - h - minXY);

    final room = Rectangle(x, y, w, h);

    if (!rooms.any((r) => _roomsOverlap(r, room))) {
      rooms.add(room);
      _carveRoom(grid, room);
    }
  }

  // Sort rooms by center position for consistent corridor connection.
  rooms.sort((a, b) {
    final cmp = _centerY(a).compareTo(_centerY(b));
    return cmp != 0 ? cmp : _centerX(a).compareTo(_centerX(b));
  });

  // Connect each room to the next with L-shaped corridors.
  for (var i = 0; i < rooms.length - 1; i++) {
    _connectRooms(grid, rooms[i], rooms[i + 1], rng);
  }

  // Ensure connectivity.
  final region = largestOpenRegion(grid);
  removeDisconnectedRegions(grid, region);

  final spawn = rooms.isNotEmpty
      ? Point(_centerX(rooms.first), _centerY(rooms.first))
      : findSpawnPoint(grid, region);

  final layers = buildTileLayers(grid, floorTileIndex: 120);

  return GameMap(
    id: 'generated_dungeon_$seed',
    name: 'Dungeon #$seed',
    barriers: gridToBarriers(grid),
    spawnPoint: spawn,
    floorLayer: layers.floor,
    objectLayer: layers.objects,
    tilesetIds: const ['room_builder_office'],
  );
}

// ---------------------------------------------------------------------------
// Room helpers
// ---------------------------------------------------------------------------

int _centerX(Rectangle<int> r) => r.left + r.width ~/ 2;
int _centerY(Rectangle<int> r) => r.top + r.height ~/ 2;

/// Checks if two rooms overlap (with 1-cell padding so they don't touch).
bool _roomsOverlap(Rectangle<int> a, Rectangle<int> b) {
  return a.left - 1 < b.left + b.width &&
      a.left + a.width + 1 > b.left &&
      a.top - 1 < b.top + b.height &&
      a.top + a.height + 1 > b.top;
}

/// Carves out a room (sets cells to open).
void _carveRoom(Grid grid, Rectangle<int> room) {
  for (var y = room.top; y < room.top + room.height; y++) {
    for (var x = room.left; x < room.left + room.width; x++) {
      if (x >= 0 && x < gridSize && y >= 0 && y < gridSize) {
        grid[y][x] = false;
      }
    }
  }
}

// ---------------------------------------------------------------------------
// Corridor helpers
// ---------------------------------------------------------------------------

/// Connects two rooms with an L-shaped corridor.
///
/// Randomly chooses horizontal-first or vertical-first.
void _connectRooms(Grid grid, Rectangle<int> a, Rectangle<int> b, Random rng) {
  final ax = _centerX(a);
  final ay = _centerY(a);
  final bx = _centerX(b);
  final by = _centerY(b);

  if (rng.nextBool()) {
    _carveHorizontal(grid, ax, bx, ay);
    _carveVertical(grid, bx, ay, by);
  } else {
    _carveVertical(grid, ax, ay, by);
    _carveHorizontal(grid, ax, bx, by);
  }
}

void _carveHorizontal(Grid grid, int x1, int x2, int y) {
  final start = min(x1, x2);
  final end = max(x1, x2);
  for (var x = start; x <= end; x++) {
    if (x >= 0 && x < gridSize && y >= 0 && y < gridSize) {
      grid[y][x] = false;
    }
  }
}

void _carveVertical(Grid grid, int x, int y1, int y2) {
  final start = min(y1, y2);
  final end = max(y1, y2);
  for (var y = start; y <= end; y++) {
    if (x >= 0 && x < gridSize && y >= 0 && y < gridSize) {
      grid[y][x] = false;
    }
  }
}
