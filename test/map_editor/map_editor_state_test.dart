import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:tech_world/flame/maps/map_parser.dart';
import 'package:tech_world/flame/maps/predefined_maps.dart';
import 'package:tech_world/flame/shared/constants.dart';
import 'package:tech_world/map_editor/map_editor_state.dart';

void main() {
  late MapEditorState state;

  setUp(() {
    state = MapEditorState();
  });

  group('Grid operations', () {
    test('starts with all open tiles', () {
      for (var y = 0; y < gridSize; y++) {
        for (var x = 0; x < gridSize; x++) {
          expect(state.tileAt(x, y), TileType.open);
        }
      }
    });

    test('paintTile sets barrier', () {
      state.setTool(EditorTool.barrier);
      state.paintTile(5, 10);
      expect(state.tileAt(5, 10), TileType.barrier);
    });

    test('paintTile sets terminal', () {
      state.setTool(EditorTool.terminal);
      state.paintTile(3, 7);
      expect(state.tileAt(3, 7), TileType.terminal);
    });

    test('eraser clears a tile', () {
      state.setTool(EditorTool.barrier);
      state.paintTile(5, 10);
      expect(state.tileAt(5, 10), TileType.barrier);

      state.setTool(EditorTool.eraser);
      state.paintTile(5, 10);
      expect(state.tileAt(5, 10), TileType.open);
    });

    test('clearGrid resets everything', () {
      state.setTool(EditorTool.barrier);
      state.paintTile(0, 0);
      state.paintTile(49, 49);
      state.setTool(EditorTool.spawn);
      state.paintTile(25, 25);

      state.clearGrid();

      expect(state.tileAt(0, 0), TileType.open);
      expect(state.tileAt(49, 49), TileType.open);
      expect(state.tileAt(25, 25), TileType.open);
    });

    test('out-of-bounds paintTile is a no-op', () {
      state.setTool(EditorTool.barrier);
      state.paintTile(-1, 0);
      state.paintTile(0, -1);
      state.paintTile(50, 0);
      state.paintTile(0, 50);
      // No exception, grid unchanged
      for (var y = 0; y < gridSize; y++) {
        for (var x = 0; x < gridSize; x++) {
          expect(state.tileAt(x, y), TileType.open);
        }
      }
    });

    test('out-of-bounds tileAt returns open', () {
      expect(state.tileAt(-1, 0), TileType.open);
      expect(state.tileAt(0, -1), TileType.open);
      expect(state.tileAt(50, 0), TileType.open);
      expect(state.tileAt(0, 50), TileType.open);
    });
  });

  group('Single-spawn enforcement', () {
    test('only one spawn point exists at a time', () {
      state.setTool(EditorTool.spawn);
      state.paintTile(10, 10);
      expect(state.tileAt(10, 10), TileType.spawn);

      state.paintTile(20, 20);
      expect(state.tileAt(10, 10), TileType.open);
      expect(state.tileAt(20, 20), TileType.spawn);
    });

    test('painting spawn over existing spawn works', () {
      state.setTool(EditorTool.spawn);
      state.paintTile(5, 5);
      state.paintTile(5, 5);
      expect(state.tileAt(5, 5), TileType.spawn);
    });
  });

  group('Export', () {
    test('toAsciiString produces valid 50x50 output', () {
      final ascii = state.toAsciiString();
      final lines = ascii.split('\n');
      expect(lines.length, gridSize);
      for (final line in lines) {
        expect(line.length, gridSize);
      }
    });

    test('toAsciiString encodes tile types correctly', () {
      state.setTool(EditorTool.barrier);
      state.paintTile(0, 0);
      state.setTool(EditorTool.spawn);
      state.paintTile(1, 0);
      state.setTool(EditorTool.terminal);
      state.paintTile(2, 0);

      final ascii = state.toAsciiString();
      final firstLine = ascii.split('\n').first;
      expect(firstLine[0], '#');
      expect(firstLine[1], 'S');
      expect(firstLine[2], 'T');
      expect(firstLine[3], '.');
    });

    test('toGameMap includes barriers, spawn, and terminals', () {
      state.setTool(EditorTool.barrier);
      state.paintTile(0, 0);
      state.paintTile(1, 0);
      state.setTool(EditorTool.spawn);
      state.paintTile(10, 10);
      state.setTool(EditorTool.terminal);
      state.paintTile(5, 5);

      final map = state.toGameMap();
      expect(map.barriers.length, 2);
      expect(map.barriers, contains(const Point(0, 0)));
      expect(map.barriers, contains(const Point(1, 0)));
      expect(map.spawnPoint, const Point(10, 10));
      expect(map.terminals.length, 1);
      expect(map.terminals.first, const Point(5, 5));
    });

    test('toGameMap uses default spawn when none set', () {
      final map = state.toGameMap();
      expect(map.spawnPoint, const Point(25, 25));
    });
  });

  group('Import', () {
    test('loadFromAscii correctly populates grid', () {
      // Build a small pattern in the top-left corner
      final lines = List.generate(gridSize, (_) => '.' * gridSize);
      lines[0] = '#ST${'.' * (gridSize - 3)}';

      state.loadFromAscii(lines.join('\n'));

      expect(state.tileAt(0, 0), TileType.barrier);
      expect(state.tileAt(1, 0), TileType.spawn);
      expect(state.tileAt(2, 0), TileType.terminal);
      expect(state.tileAt(3, 0), TileType.open);
    });

    test('loadFromGameMap populates grid from existing map', () {
      state.loadFromGameMap(lRoom);

      expect(state.mapName, 'The L-Room');
      expect(state.mapId, 'l_room');

      // Check a known barrier
      expect(state.tileAt(4, 7), TileType.barrier);
      // Check spawn
      expect(state.tileAt(10, 15), TileType.spawn);
      // Check terminals
      expect(state.tileAt(8, 12), TileType.terminal);
      expect(state.tileAt(14, 12), TileType.terminal);
      // Check an open tile
      expect(state.tileAt(0, 0), TileType.open);
    });
  });

  group('Roundtrip', () {
    test('loadFromGameMap → toAsciiString → parseAsciiMap preserves map', () {
      state.loadFromGameMap(theLibrary);

      final ascii = state.toAsciiString();
      final parsed = parseAsciiMap(
        id: 'the_library',
        name: 'The Library',
        ascii: ascii,
      );

      // Compare barriers
      final originalBarriers = theLibrary.barriers.toSet();
      final parsedBarriers = parsed.barriers.toSet();
      expect(parsedBarriers, originalBarriers);

      // Compare spawn
      expect(parsed.spawnPoint, theLibrary.spawnPoint);

      // Compare terminals
      expect(parsed.terminals.toSet(), theLibrary.terminals.toSet());
    });

    test('toAsciiString → loadFromAscii preserves grid', () {
      // Paint some tiles
      state.setTool(EditorTool.barrier);
      for (var i = 0; i < 10; i++) {
        state.paintTile(i, 0);
      }
      state.setTool(EditorTool.spawn);
      state.paintTile(25, 25);
      state.setTool(EditorTool.terminal);
      state.paintTile(30, 30);

      final ascii = state.toAsciiString();

      final state2 = MapEditorState();
      state2.loadFromAscii(ascii);

      for (var y = 0; y < gridSize; y++) {
        for (var x = 0; x < gridSize; x++) {
          expect(state2.tileAt(x, y), state.tileAt(x, y),
              reason: 'Mismatch at ($x, $y)');
        }
      }
    });
  });

  group('ChangeNotifier', () {
    test('paintTile notifies listeners', () {
      var notified = false;
      state.addListener(() => notified = true);

      state.setTool(EditorTool.barrier);
      notified = false;
      state.paintTile(5, 5);
      expect(notified, isTrue);
    });

    test('clearGrid notifies listeners', () {
      var notified = false;
      state.addListener(() => notified = true);
      state.clearGrid();
      expect(notified, isTrue);
    });

    test('setTool notifies listeners', () {
      var notified = false;
      state.addListener(() => notified = true);
      state.setTool(EditorTool.terminal);
      expect(notified, isTrue);
    });
  });

  group('Background image', () {
    test('starts null', () {
      expect(state.backgroundImage, isNull);
    });

    test('setBackgroundImage updates value and notifies', () {
      var notified = false;
      state.addListener(() => notified = true);

      state.setBackgroundImage('single_room.png');

      expect(state.backgroundImage, 'single_room.png');
      expect(notified, isTrue);
    });

    test('loadFromGameMap restores backgroundImage from l_room', () {
      state.loadFromGameMap(lRoom);
      expect(state.backgroundImage, 'single_room.png');
    });

    test('loadFromGameMap sets null for maps without background', () {
      // First set a background so we can verify it gets cleared.
      state.setBackgroundImage('single_room.png');
      state.loadFromGameMap(openArena);
      expect(state.backgroundImage, isNull);
    });

    test('toGameMap includes backgroundImage', () {
      state.setBackgroundImage('single_room.png');
      final map = state.toGameMap();
      expect(map.backgroundImage, 'single_room.png');
    });

    test('toGameMap has null backgroundImage when not set', () {
      final map = state.toGameMap();
      expect(map.backgroundImage, isNull);
    });

    test('clearAll resets backgroundImage to null', () {
      state.setBackgroundImage('single_room.png');
      state.clearAll();
      expect(state.backgroundImage, isNull);
    });
  });
}
