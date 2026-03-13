import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:tech_world/flame/maps/game_map.dart';
import 'package:tech_world/flame/maps/map_parser.dart';
import 'package:tech_world/flame/maps/predefined_maps.dart';
import 'package:tech_world/flame/shared/constants.dart';
import 'package:tech_world/flame/tiles/tile_brush.dart';
import 'package:tech_world/flame/tiles/tileset.dart';
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

      // lRoom has L-wall barriers for offline fallback.
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

  group('Multi-tile brush painting', () {
    test('setBrush sets the current brush', () {
      const brush = TileBrush(
        tilesetId: 'test',
        startCol: 0,
        startRow: 0,
        columns: 4,
        width: 2,
        height: 2,
      );
      state.setBrush(brush);
      expect(state.currentBrush, brush);
    });

    test('setBrush null selects eraser', () {
      state.setBrush(const TileBrush(
        tilesetId: 'test',
        startCol: 0,
        startRow: 0,
        columns: 4,
      ));
      state.setBrush(null);
      expect(state.currentBrush, isNull);
    });

    test('paintTileRef with multi-tile brush stamps full rectangle', () {
      state.setActiveLayer(ActiveLayer.floor);
      state.setBrush(const TileBrush(
        tilesetId: 'test',
        startCol: 1,
        startRow: 2,
        columns: 4,
        width: 2,
        height: 3,
      ));

      state.paintTileRef(5, 10);

      // Check all 6 cells (2×3) were painted.
      for (var dy = 0; dy < 3; dy++) {
        for (var dx = 0; dx < 2; dx++) {
          final ref = state.floorLayerData.tileAt(5 + dx, 10 + dy);
          expect(ref, isNotNull, reason: 'Cell (${5 + dx}, ${10 + dy})');
          expect(ref!.tilesetId, 'test');
          // Expected index: (2+dy) * 4 + (1+dx)
          expect(ref.tileIndex, (2 + dy) * 4 + (1 + dx));
        }
      }
    });

    test('paintTileRef clips brush at grid boundary', () {
      state.setActiveLayer(ActiveLayer.floor);
      state.setBrush(const TileBrush(
        tilesetId: 'test',
        startCol: 0,
        startRow: 0,
        columns: 4,
        width: 3,
        height: 3,
      ));

      // Paint at bottom-right corner — only (49,49) should be set.
      state.paintTileRef(48, 48);

      expect(state.floorLayerData.tileAt(48, 48), isNotNull);
      expect(state.floorLayerData.tileAt(49, 49), isNotNull);
      // (50, 50) is out of bounds — should not crash.
    });

    test('paintTileRef with null brush erases single cell', () {
      state.setActiveLayer(ActiveLayer.floor);

      // First paint a tile.
      state.setBrush(const TileBrush(
        tilesetId: 'test',
        startCol: 0,
        startRow: 0,
        columns: 4,
      ));
      state.paintTileRef(5, 5);
      expect(state.floorLayerData.tileAt(5, 5), isNotNull);

      // Erase it.
      state.setBrush(null);
      state.paintTileRef(5, 5);
      expect(state.floorLayerData.tileAt(5, 5), isNull);
    });
  });

  group('toGameMap defensive copies', () {
    test('toGameMap floor layer is a separate copy from editor state', () {
      state.setActiveLayer(ActiveLayer.floor);
      state.setBrush(const TileBrush(
        tilesetId: 'test',
        startCol: 0,
        startRow: 0,
        columns: 4,
      ));
      state.paintTileRef(3, 3);

      final map = state.toGameMap();

      // Mutating the editor state should not affect the exported map.
      state.clearAll();
      expect(map.floorLayer, isNotNull);
      expect(map.floorLayer!.tileAt(3, 3), isNotNull,
          reason: 'Exported GameMap should be independent of editor state');
    });

    test('loadFromGameMap on same instance preserves manual tiles', () {
      state.setActiveLayer(ActiveLayer.floor);
      state.setBrush(const TileBrush(
        tilesetId: 'test',
        startCol: 0,
        startRow: 0,
        columns: 4,
      ));
      state.paintTileRef(3, 3);
      state.paintTileRef(4, 4);

      final map = state.toGameMap();

      // Re-load into the SAME instance — simulates re-entering editor mode.
      state.loadFromGameMap(map);

      expect(state.floorLayerData.tileAt(3, 3), isNotNull,
          reason: 'Floor tile should survive same-instance roundtrip');
      expect(state.floorLayerData.tileAt(4, 4), isNotNull,
          reason: 'Floor tile should survive same-instance roundtrip');
    });
  });

  group('Custom tilesets', () {
    const customTileset = Tileset(
      id: 'custom_abc123',
      name: 'My Tileset',
      imagePath: 'custom/custom_abc123.png',
      tileSize: 16,
      columns: 8,
      rows: 4,
      isCustom: true,
    );

    test('loadFromTmxWithCustomTilesets stores customTilesets and bytes', () {
      // Build a minimal TMX with a custom tileset.
      // We use loadFromGameMap + manual state to simulate what
      // loadFromTmxWithCustomTilesets does internally.
      final imageBytes = Uint8List.fromList([0x89, 0x50, 0x4E, 0x47]);

      state.setCustomTilesetData(
        [customTileset],
        {'custom/custom_abc123.png': imageBytes},
      );

      expect(state.customTilesets, hasLength(1));
      expect(state.customTilesets.first.id, 'custom_abc123');
      expect(state.customTilesetBytes, hasLength(1));
      expect(
        state.customTilesetBytes['custom/custom_abc123.png'],
        imageBytes,
      );
    });

    test('toGameMap includes customTilesets', () {
      state.setCustomTilesetData([customTileset], {});

      // Paint a tile referencing the custom tileset.
      state.setActiveLayer(ActiveLayer.floor);
      state.setBrush(const TileBrush(
        tilesetId: 'custom_abc123',
        startCol: 0,
        startRow: 0,
        columns: 8,
      ));
      state.paintTileRef(5, 5);

      final map = state.toGameMap();
      expect(map.customTilesets, hasLength(1));
      expect(map.customTilesets.first.id, 'custom_abc123');
    });

    test('loadFromGameMap preserves customTilesets', () {
      final map = GameMap(
        id: 'custom_map',
        name: 'Custom Map',
        barriers: const [],
        customTilesets: const [customTileset],
      );

      state.loadFromGameMap(map);

      expect(state.customTilesets, hasLength(1));
      expect(state.customTilesets.first.id, 'custom_abc123');
    });

    test('clearAll clears custom tileset data', () {
      final imageBytes = Uint8List.fromList([1, 2, 3]);
      state.setCustomTilesetData(
        [customTileset],
        {'custom/custom_abc123.png': imageBytes},
      );

      state.clearAll();

      expect(state.customTilesets, isEmpty);
      expect(state.customTilesetBytes, isEmpty);
    });

    test('setActiveLayer preserves brush for custom tileset', () {
      state.setCustomTilesetData([customTileset], {});

      // Select a brush from the custom tileset.
      state.setActiveLayer(ActiveLayer.floor);
      state.setBrush(const TileBrush(
        tilesetId: 'custom_abc123',
        startCol: 0,
        startRow: 0,
        columns: 8,
      ));

      // Switch to objects and back — brush should survive since custom
      // tilesets are available on all layers.
      state.setActiveLayer(ActiveLayer.objects);

      expect(state.currentBrush, isNotNull);
      expect(state.currentBrush!.tilesetId, 'custom_abc123');
    });
  });
}
