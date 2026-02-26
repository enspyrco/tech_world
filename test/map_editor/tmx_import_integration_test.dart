import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:tech_world/flame/maps/tmx_importer.dart';
import 'package:tech_world/flame/shared/constants.dart';
import 'package:tech_world/flame/tiles/tile_ref.dart';
import 'package:tech_world/map_editor/map_editor_state.dart';

/// Build a minimal TMX XML string for integration testing.
String _buildTmx({
  int width = 3,
  int height = 3,
  List<({String name, int firstGid, String image, int columns, int tileCount})>
      tilesets = const [],
  List<({String name, String csv})> layers = const [],
  List<({String name, String objectsXml})> objectGroups = const [],
}) {
  final sb = StringBuffer();
  sb.writeln('<?xml version="1.0" encoding="UTF-8"?>');
  sb.write('<map version="1.10" tiledversion="1.11.2" ');
  sb.write('orientation="orthogonal" renderorder="right-down" ');
  sb.write('width="$width" height="$height" ');
  sb.writeln('tilewidth="32" tileheight="32" infinite="0">');

  for (final ts in tilesets) {
    sb.write(' <tileset firstgid="${ts.firstGid}" name="${ts.name}" ');
    sb.write('tilewidth="32" tileheight="32" ');
    sb.write('tilecount="${ts.tileCount}" columns="${ts.columns}">');
    sb.write('<image source="${ts.image}" ');
    sb.write('width="${ts.columns * 32}" ');
    sb.writeln('height="${(ts.tileCount ~/ ts.columns) * 32}"/>');
    sb.writeln(' </tileset>');
  }

  for (final layer in layers) {
    sb.writeln(
        ' <layer name="${layer.name}" width="$width" height="$height">');
    sb.writeln('  <data encoding="csv">');
    sb.writeln(layer.csv);
    sb.writeln('  </data>');
    sb.writeln(' </layer>');
  }

  for (final og in objectGroups) {
    sb.writeln(' <objectgroup name="${og.name}">');
    sb.writeln(og.objectsXml);
    sb.writeln(' </objectgroup>');
  }

  sb.writeln('</map>');
  return sb.toString();
}

void main() {
  group('MapEditorState.loadFromTmx', () {
    late MapEditorState state;

    setUp(() {
      state = MapEditorState();
    });

    test('loads TMX data into editor state and returns warnings', () {
      final tmx = _buildTmx(
        width: 4,
        height: 4,
        tilesets: [
          (
            name: 'Test',
            firstGid: 1,
            image: '../tilesets/test_tileset.png',
            columns: 4,
            tileCount: 16,
          ),
        ],
        layers: [
          (name: 'Ground', csv: '1,2,3,4,\n5,6,7,8,\n9,10,11,12,\n13,14,15,16'),
        ],
        objectGroups: [
          (
            name: 'Objects',
            objectsXml:
                '<object id="1" name="Spawn" type="spawn" x="32" y="32" width="32" height="32"/>',
          ),
        ],
      );

      final warnings = state.loadFromTmx(
        tmx,
        mapName: 'Test Map',
        mapId: 'test_map',
      );

      // Should have a padding warning (4×4 < 50×50).
      expect(
        warnings.any((w) => w.kind == TmxWarningKind.mapPadded),
        isTrue,
      );

      // Map name and ID should be set.
      expect(state.mapName, 'Test Map');
      expect(state.mapId, 'test_map');

      // Floor layer should have data at the centered offset.
      final ox = (gridSize - 4) ~/ 2;
      final oy = (gridSize - 4) ~/ 2;

      expect(
        state.floorLayerData.tileAt(ox, oy),
        const TileRef(tilesetId: 'test', tileIndex: 0),
      );
      expect(
        state.floorLayerData.tileAt(ox + 3, oy + 3),
        const TileRef(tilesetId: 'test', tileIndex: 15),
      );

      // Spawn should be set in structure grid.
      expect(state.tileAt(ox + 1, oy + 1), TileType.spawn);
    });

    test('loads barriers from tileset metadata', () {
      // room_builder_office: tile indices 0–79 are barriers.
      final tmx = _buildTmx(
        width: 2,
        height: 1,
        tilesets: [
          (
            name: 'RoomBuilder',
            firstGid: 1,
            image: '../tilesets/room_builder_office.png',
            columns: 16,
            tileCount: 224,
          ),
        ],
        layers: [
          // GID 1 = barrier (tileIndex 0), GID 81 = non-barrier (tileIndex 80)
          (name: 'Wall Layer', csv: '1,81'),
        ],
      );

      state.loadFromTmx(tmx);
      final ox = (gridSize - 2) ~/ 2;
      final oy = (gridSize - 1) ~/ 2;

      // First cell should be a barrier in structure grid.
      expect(state.tileAt(ox, oy), TileType.barrier);
      // Second cell should be open (tileIndex 80 is not in barrierTileIndices).
      expect(state.tileAt(ox + 1, oy), TileType.open);
    });

    test('throws TmxImportException on invalid TMX', () {
      expect(
        () => state.loadFromTmx('not valid xml'),
        throwsA(isA<TmxImportException>()),
      );
    });

    test('round-trips through toGameMap()', () {
      final tmx = _buildTmx(
        width: 5,
        height: 5,
        tilesets: [
          (
            name: 'Test',
            firstGid: 1,
            image: '../tilesets/test_tileset.png',
            columns: 4,
            tileCount: 16,
          ),
        ],
        layers: [
          (
            name: 'Floor',
            csv: '1,2,3,4,5,\n6,7,8,9,10,\n11,12,13,14,15,\n16,1,2,3,4,\n5,6,7,8,9',
          ),
        ],
        objectGroups: [
          (
            name: 'Objects',
            objectsXml: '''
<object id="1" name="Spawn" type="spawn" x="64" y="64" width="32" height="32"/>
<object id="2" name="T1" type="terminal" x="128" y="128" width="32" height="32"/>''',
          ),
        ],
      );

      state.loadFromTmx(tmx, mapName: 'Round Trip', mapId: 'round_trip');
      final exported = state.toGameMap();

      expect(exported.id, 'round_trip');
      expect(exported.name, 'Round Trip');
      expect(exported.floorLayer, isNotNull);
      expect(exported.tilesetIds, contains('test'));

      // Spawn point should be set.
      final ox = (gridSize - 5) ~/ 2;
      final oy = (gridSize - 5) ~/ 2;
      expect(exported.spawnPoint, Point(ox + 2, oy + 2));

      // Terminal should be set.
      expect(exported.terminals, contains(Point(ox + 4, oy + 4)));
    });

    test('clears previous state before loading TMX', () {
      // Load ASCII first to populate structure grid.
      state.loadFromAscii('####\n#S.#\n#..#\n####');
      expect(state.tileAt(0, 0), TileType.barrier);

      // Now load TMX — previous state should be cleared.
      final tmx = _buildTmx(
        width: 1,
        height: 1,
        tilesets: [
          (
            name: 'Test',
            firstGid: 1,
            image: '../tilesets/test_tileset.png',
            columns: 4,
            tileCount: 16,
          ),
        ],
        layers: [
          (name: 'Floor', csv: '1'),
        ],
      );

      state.loadFromTmx(tmx, mapName: 'Fresh');

      // Old barrier at (0,0) should be cleared.
      expect(state.tileAt(0, 0), TileType.open);
      expect(state.mapName, 'Fresh');
    });
  });
}
