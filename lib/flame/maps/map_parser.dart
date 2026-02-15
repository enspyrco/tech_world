import 'dart:math';

import '../shared/constants.dart';
import 'game_map.dart';

/// Parses an ASCII art string into a [GameMap].
///
/// The ASCII art format uses the following characters:
/// - `.` = open space
/// - `#` = barrier
/// - `S` = spawn point (open space)
/// - `T` = terminal station (open space)
///
/// The grid must be exactly [gridSize] x [gridSize] (50x50).
/// Characters map to (x, y) where x is the column index and y is the row index.
///
/// Throws [FormatException] if the ASCII art is invalid.
GameMap parseAsciiMap({
  required String id,
  required String name,
  required String ascii,
}) {
  final lines = _parseLines(ascii);
  _validateDimensions(lines, name);

  final barriers = <Point<int>>[];
  final terminals = <Point<int>>[];
  Point<int>? spawnPoint;

  for (var y = 0; y < lines.length; y++) {
    final line = lines[y];
    for (var x = 0; x < line.length; x++) {
      final char = line[x];
      switch (char) {
        case '.':
          // Open space, nothing to do.
          break;
        case '#':
          barriers.add(Point(x, y));
        case 'S':
          if (spawnPoint != null) {
            throw FormatException(
              'Map "$name" has multiple spawn points: '
              'first at (${spawnPoint.x}, ${spawnPoint.y}), '
              'second at ($x, $y).',
            );
          }
          spawnPoint = Point(x, y);
        case 'T':
          terminals.add(Point(x, y));
        default:
          throw FormatException(
            'Map "$name" has invalid character "$char" at ($x, $y). '
            'Valid characters are: . # S T',
          );
      }
    }
  }

  if (spawnPoint == null) {
    throw FormatException(
      'Map "$name" has no spawn point. Use "S" to mark the spawn location.',
    );
  }

  return GameMap(
    id: id,
    name: name,
    barriers: barriers,
    spawnPoint: spawnPoint,
    terminals: terminals,
  );
}

/// Splits the ASCII string into lines, trimming leading/trailing blank lines
/// and ensuring each line is exactly [gridSize] characters.
List<String> _parseLines(String ascii) {
  // Split into lines and remove leading/trailing empty lines.
  var lines = ascii.split('\n');

  // Remove leading empty lines.
  while (lines.isNotEmpty && lines.first.trim().isEmpty) {
    lines = lines.sublist(1);
  }
  // Remove trailing empty lines.
  while (lines.isNotEmpty && lines.last.trim().isEmpty) {
    lines = lines.sublist(0, lines.length - 1);
  }

  return lines;
}

/// Validates that the parsed lines form a [gridSize] x [gridSize] grid.
void _validateDimensions(List<String> lines, String name) {
  if (lines.length != gridSize) {
    throw FormatException(
      'Map "$name" has ${lines.length} rows, expected $gridSize.',
    );
  }

  for (var y = 0; y < lines.length; y++) {
    if (lines[y].length != gridSize) {
      throw FormatException(
        'Map "$name" row $y has ${lines[y].length} columns, '
        'expected $gridSize.',
      );
    }
  }
}
