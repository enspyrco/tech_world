import 'dart:math';

import 'game_map.dart';

/// Open Arena - no barriers, free movement everywhere.
const openArena = GameMap(
  id: 'open_arena',
  name: 'Open Arena',
  barriers: [],
  spawnPoint: Point(25, 25),
);

/// The L-Room - original map with L-shaped walls.
const lRoom = GameMap(
  id: 'l_room',
  name: 'The L-Room',
  barriers: [
    // Vertical wall at x=4
    Point(4, 7),
    Point(4, 8),
    Point(4, 9),
    Point(4, 10),
    Point(4, 11),
    Point(4, 12),
    Point(4, 13),
    Point(4, 14),
    Point(4, 15),
    Point(4, 16),
    Point(4, 18),
    Point(4, 19),
    Point(4, 20),
    Point(4, 21),
    Point(4, 22),
    Point(4, 23),
    Point(4, 24),
    Point(4, 25),
    Point(4, 26),
    Point(4, 27),
    Point(4, 28),
    Point(4, 29),
    // Horizontal wall at y=7
    Point(5, 7),
    Point(6, 7),
    Point(7, 7),
    Point(8, 7),
    Point(9, 7),
    Point(10, 7),
    Point(11, 7),
    Point(12, 7),
    Point(13, 7),
    Point(14, 7),
    Point(15, 7),
    Point(16, 7),
    Point(17, 7),
  ],
  spawnPoint: Point(10, 15),
  terminals: [Point(8, 12), Point(14, 12)],
);

/// Four Corners - barriers in each corner, open center.
final fourCorners = GameMap(
  id: 'four_corners',
  name: 'Four Corners',
  barriers: [
    // Top-left corner (5x5 block)
    ..._generateBlock(2, 2, 5, 5),
    // Top-right corner
    ..._generateBlock(43, 2, 5, 5),
    // Bottom-left corner
    ..._generateBlock(2, 43, 5, 5),
    // Bottom-right corner
    ..._generateBlock(43, 43, 5, 5),
  ],
  spawnPoint: const Point(25, 25),
);

/// Simple Maze - a basic maze pattern.
final simpleMaze = GameMap(
  id: 'simple_maze',
  name: 'Simple Maze',
  barriers: _deduplicateBarriers([
    // Outer walls (with gaps for entry/exit)
    ..._generateHorizontalWall(5, 5, 40, gap: 20),
    ..._generateHorizontalWall(5, 44, 40, gap: 25),
    ..._generateVerticalWall(5, 6, 38, gap: 22), // Start at y=6 to avoid corner overlap
    ..._generateVerticalWall(44, 6, 38, gap: 22), // Start at y=6 to avoid corner overlap
    // Internal maze walls
    ..._generateHorizontalWall(10, 15, 25),
    ..._generateVerticalWall(20, 10, 20, gap: 15),
    ..._generateHorizontalWall(25, 30, 15),
    ..._generateVerticalWall(30, 20, 15, gap: 27),
  ]),
  spawnPoint: const Point(8, 8),
);

/// The Library - bookshelves form reading nooks and corridors.
///
/// Layout (50x50 grid):
///   Entrance at bottom-center, bookshelves run mostly east-west
///   with gaps for corridors. Four cozy reading nooks house terminals.
///
///   Key features:
///   - Central corridor running north-south
///   - East-west bookshelf rows with gaps for passage
///   - Four reading nooks tucked between shelves for terminals
///   - Open entrance foyer at the bottom
final theLibrary = GameMap(
  id: 'the_library',
  name: 'The Library',
  barriers: _deduplicateBarriers([
    // === Outer walls (library perimeter) ===
    // North wall
    ..._generateHorizontalWall(3, 3, 44),
    // South wall with entrance gap at center (x=23-26)
    ..._generateHorizontalWall(3, 46, 20), // left portion: x=3..22
    ..._generateHorizontalWall(27, 46, 20), // right portion: x=27..46
    // West wall
    ..._generateVerticalWall(3, 4, 42),
    // East wall
    ..._generateVerticalWall(46, 4, 42),

    // === Entrance foyer desk (small reception block) ===
    ..._generateBlock(21, 42, 8, 2), // reception desk

    // === Row 1: Top bookshelves (y=8) ===
    // West shelf
    ..._generateHorizontalWall(6, 8, 15), // x=6..20
    // East shelf (gap at x=24 for north-south corridor)
    ..._generateHorizontalWall(27, 8, 16), // x=27..42

    // === Nook 1 (northwest): shelves forming a reading nook ===
    // South wall of nook
    ..._generateHorizontalWall(6, 14, 10), // x=6..15
    // East wall of nook (gap at y=11 for entry)
    ..._generateVerticalWall(15, 9, 2), // y=9..10
    ..._generateVerticalWall(15, 12, 2), // y=12..13
    // Terminal 1 at (10, 11) - center of northwest nook

    // === Nook 2 (northeast): shelves forming a reading nook ===
    // South wall of nook
    ..._generateHorizontalWall(34, 14, 10), // x=34..43
    // West wall of nook (gap at y=11 for entry)
    ..._generateVerticalWall(34, 9, 2), // y=9..10
    ..._generateVerticalWall(34, 12, 2), // y=12..13
    // Terminal 2 at (39, 11) - center of northeast nook

    // === Row 2: Middle bookshelves (y=19) ===
    // West shelf
    ..._generateHorizontalWall(6, 19, 12), // x=6..17
    // Center-west shelf
    ..._generateHorizontalWall(20, 19, 4), // x=20..23
    // Center-east shelf (gap at x=24 for corridor)
    ..._generateHorizontalWall(27, 19, 4), // x=27..30
    // East shelf
    ..._generateHorizontalWall(33, 19, 10), // x=33..42

    // === Row 3: Bookshelves (y=24) ===
    // West shelf
    ..._generateHorizontalWall(6, 24, 8), // x=6..13
    // East shelf
    ..._generateHorizontalWall(35, 24, 8), // x=35..42

    // === Nook 3 (west-center): study alcove ===
    // North wall of nook
    ..._generateHorizontalWall(6, 28, 10), // x=6..15
    // South wall of nook
    ..._generateHorizontalWall(6, 34, 10), // x=6..15
    // East wall of nook (gap at y=31 for entry)
    ..._generateVerticalWall(15, 29, 2), // y=29..30
    ..._generateVerticalWall(15, 32, 2), // y=32..33
    // Terminal 3 at (10, 31) - center of west alcove

    // === Nook 4 (east-center): study alcove ===
    // North wall of nook
    ..._generateHorizontalWall(34, 28, 10), // x=34..43
    // South wall of nook
    ..._generateHorizontalWall(34, 34, 10), // x=34..43
    // West wall of nook (gap at y=31 for entry)
    ..._generateVerticalWall(34, 29, 2), // y=29..30
    ..._generateVerticalWall(34, 32, 2), // y=32..33
    // Terminal 4 at (39, 31) - center of east alcove

    // === Row 4: Lower bookshelves (y=38) ===
    // West shelf
    ..._generateHorizontalWall(6, 38, 15), // x=6..20
    // East shelf (gap at x=24 for corridor)
    ..._generateHorizontalWall(27, 38, 16), // x=27..42
  ]),
  spawnPoint: const Point(24, 44),
  terminals: [
    Point(10, 11), // Northwest reading nook
    Point(39, 11), // Northeast reading nook
    Point(10, 31), // West study alcove
    Point(39, 31), // East study alcove
  ],
);

/// The Workshop - industrial maker space with workbenches and equipment.
///
/// Layout (50x50 grid):
///   Entrance at bottom-left. Workbenches, tool racks, and heavy equipment
///   create a winding maze-like layout. Terminals sit at workbench stations.
///
///   Key features:
///   - More challenging navigation than The Library
///   - Winding paths between heavy equipment blocks
///   - Workbench stations with terminals
///   - Multiple dead-ends and switchbacks
final theWorkshop = GameMap(
  id: 'the_workshop',
  name: 'The Workshop',
  barriers: _deduplicateBarriers([
    // === Outer walls (workshop perimeter) ===
    // North wall
    ..._generateHorizontalWall(2, 2, 46),
    // South wall with entrance gap at left (x=4-6)
    ..._generateHorizontalWall(2, 47, 2), // x=2..3
    ..._generateHorizontalWall(7, 47, 41), // x=7..47
    // West wall (gap at y=44-46 for door)
    ..._generateVerticalWall(2, 3, 41), // y=3..43
    // East wall
    ..._generateVerticalWall(47, 3, 44),

    // === Entry corridor: tool racks along entrance path ===
    // Tool rack forcing you right from entrance
    ..._generateVerticalWall(9, 40, 7), // y=40..46 right of entrance
    // Tool rack creating corridor
    ..._generateHorizontalWall(9, 40, 8), // x=9..16

    // === Zone 1 (southwest): Heavy equipment / welding area ===
    // Large equipment block
    ..._generateBlock(5, 33, 4, 4), // 4x4 block
    // Welding screen wall
    ..._generateVerticalWall(13, 30, 8), // y=30..37
    // Equipment shelf
    ..._generateHorizontalWall(5, 30, 5), // x=5..9

    // === Zone 2 (northwest): Storage and lumber area ===
    // Lumber racks (horizontal)
    ..._generateBlock(5, 5, 8, 2), // wide rack, y=5..6
    ..._generateBlock(5, 10, 8, 2), // second rack, y=10..11
    // Divider wall between storage and work area
    ..._generateVerticalWall(16, 4, 12, gap: 9), // y=4..15, gap at y=9
    // More storage shelving
    ..._generateBlock(5, 15, 6, 2), // y=15..16

    // === Zone 3 (north-center): Assembly area with workbenches ===
    // Workbench 1 (north)
    ..._generateBlock(20, 5, 6, 2), // y=5..6
    // Equipment between benches
    ..._generateBlock(20, 10, 3, 3), // small equipment
    ..._generateBlock(28, 5, 3, 3), // tool cabinet
    // Workbench 2 (center)
    ..._generateBlock(28, 10, 6, 2), // y=10..11
    // Terminal 1 at (24, 8) - between workbenches in assembly area

    // === Divider wall: north/south sections ===
    // Long horizontal wall with two gaps for passage
    ..._generateHorizontalWall(16, 17, 12), // x=16..27
    ..._generateHorizontalWall(30, 17, 15), // x=30..44
    // gap at x=28-29 for passage

    // === Zone 4 (center): Main workshop floor ===
    // Central equipment pillar
    ..._generateBlock(22, 22, 4, 4), // 4x4 block y=22..25
    // Workbench along south side of pillar
    ..._generateHorizontalWall(20, 27, 8), // x=20..27
    // Terminal 2 at (24, 29) - south of central workbench

    // === Zone 5 (east): Electronics / precision work area ===
    // North shelving
    ..._generateBlock(36, 5, 8, 2), // y=5..6
    // Precision equipment blocks
    ..._generateBlock(38, 10, 3, 3), // y=10..12
    ..._generateBlock(43, 10, 3, 3), // y=10..12
    // East workbench with divider
    ..._generateVerticalWall(36, 20, 10), // y=20..29
    ..._generateHorizontalWall(37, 24, 8), // x=37..44
    // Terminal 3 at (41, 21) - electronics workbench (north of east bench)

    // === Zone 6 (southeast): Paint / finishing area ===
    // Paint booth walls
    ..._generateVerticalWall(36, 33, 8), // y=33..40
    ..._generateHorizontalWall(37, 33, 8), // x=37..44
    // Drying racks
    ..._generateBlock(40, 37, 2, 4), // y=37..40
    // Terminal 4 at (38, 36) - paint booth workstation

    // === Zone 7 (south-center): CNC / machining area ===
    // CNC machine block
    ..._generateBlock(18, 33, 5, 4), // y=33..36
    // Material rack
    ..._generateBlock(25, 35, 3, 3), // y=35..37
    // Divider from welding area
    ..._generateHorizontalWall(18, 40, 12), // x=18..29

    // === Scattered obstacles: pipes, pillars, crates ===
    // Support pillars
    ..._generateBlock(14, 22, 2, 2), // pillar
    ..._generateBlock(32, 28, 2, 2), // pillar
    // Crate stack
    ..._generateBlock(30, 42, 3, 2), // crates near south wall
  ]),
  spawnPoint: const Point(5, 45),
  terminals: [
    Point(24, 8), // Assembly area workbench
    Point(24, 29), // Central workshop workbench
    Point(41, 21), // Electronics workbench
    Point(38, 36), // Paint booth workstation
  ],
);

/// All available maps.
final allMaps = [openArena, lRoom, fourCorners, simpleMaze, theLibrary, theWorkshop];

/// Default map to use when none is specified.
const defaultMap = lRoom;

// Helper functions for generating barrier patterns

/// Remove duplicate barriers from a list.
List<Point<int>> _deduplicateBarriers(List<Point<int>> barriers) {
  return barriers.toSet().toList();
}

/// Generate a rectangular block of barriers.
List<Point<int>> _generateBlock(int startX, int startY, int width, int height) {
  final points = <Point<int>>[];
  for (var y = startY; y < startY + height; y++) {
    for (var x = startX; x < startX + width; x++) {
      points.add(Point(x, y));
    }
  }
  return points;
}

/// Generate a horizontal wall with optional gap.
List<Point<int>> _generateHorizontalWall(int startX, int y, int length,
    {int? gap}) {
  final points = <Point<int>>[];
  for (var x = startX; x < startX + length; x++) {
    if (gap == null || x != gap) {
      points.add(Point(x, y));
    }
  }
  return points;
}

/// Generate a vertical wall with optional gap.
List<Point<int>> _generateVerticalWall(int x, int startY, int length,
    {int? gap}) {
  final points = <Point<int>>[];
  for (var y = startY; y < startY + length; y++) {
    if (gap == null || y != gap) {
      points.add(Point(x, y));
    }
  }
  return points;
}
