import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:tech_world/flame/maps/tmx_importer.dart';
import 'package:tech_world/flame/shared/constants.dart';
import 'package:tech_world/flame/tiles/tile_ref.dart';

// ---------------------------------------------------------------------------
// TMX XML helpers — build valid TMX strings for testing.
// ---------------------------------------------------------------------------

/// Build a minimal TMX XML string.
///
/// [width] and [height] are in tiles. [tileWidth] and [tileHeight] in pixels.
/// [tilesets] is a list of `(name, firstGid, imageSource, columns, tileCount)`.
/// [layers] is a list of `(name, csv)` where csv is comma-separated GIDs.
/// [objectGroups] is a list of `(name, objects)` where objects is XML string.
String buildTmx({
  int width = 3,
  int height = 3,
  int tileWidth = 32,
  int tileHeight = 32,
  String orientation = 'orthogonal',
  List<({String name, int firstGid, String image, int columns, int tileCount})>
      tilesets = const [],
  List<({String name, String csv})> layers = const [],
  List<({String name, String objectsXml})> objectGroups = const [],
}) {
  final sb = StringBuffer();
  sb.writeln('<?xml version="1.0" encoding="UTF-8"?>');
  sb.write('<map version="1.10" tiledversion="1.11.2" ');
  sb.write('orientation="$orientation" ');
  sb.write('renderorder="right-down" ');
  sb.write('width="$width" height="$height" ');
  sb.write('tilewidth="$tileWidth" tileheight="$tileHeight" ');
  sb.writeln('infinite="0">');

  for (final ts in tilesets) {
    sb.write(' <tileset firstgid="${ts.firstGid}" name="${ts.name}" ');
    sb.write('tilewidth="$tileWidth" tileheight="$tileHeight" ');
    sb.write('tilecount="${ts.tileCount}" columns="${ts.columns}">');
    sb.write('<image source="${ts.image}" ');
    sb.write('width="${ts.columns * tileWidth}" ');
    sb.writeln('height="${(ts.tileCount ~/ ts.columns) * tileHeight}"/>');
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

/// Build a TMX XML with an external TSX reference (tileset source attribute).
///
/// In Tiled, external tilesets look like:
///   `<tileset firstgid="1" source="desert.tsx"/>`
/// The actual tileset metadata lives in the TSX file.
String buildTmxWithExternalTsx({
  int width = 3,
  int height = 3,
  int tileWidth = 32,
  int tileHeight = 32,
  List<({String source, int firstGid})> externalTilesets = const [],
  List<({String name, int firstGid, String image, int columns, int tileCount})>
      inlineTilesets = const [],
  List<({String name, String csv})> layers = const [],
}) {
  final sb = StringBuffer();
  sb.writeln('<?xml version="1.0" encoding="UTF-8"?>');
  sb.write('<map version="1.10" tiledversion="1.11.2" ');
  sb.write('orientation="orthogonal" ');
  sb.write('renderorder="right-down" ');
  sb.write('width="$width" height="$height" ');
  sb.write('tilewidth="$tileWidth" tileheight="$tileHeight" ');
  sb.writeln('infinite="0">');

  // External TSX references.
  for (final ts in externalTilesets) {
    sb.writeln(' <tileset firstgid="${ts.firstGid}" source="${ts.source}"/>');
  }

  // Inline tilesets.
  for (final ts in inlineTilesets) {
    sb.write(' <tileset firstgid="${ts.firstGid}" name="${ts.name}" ');
    sb.write('tilewidth="$tileWidth" tileheight="$tileHeight" ');
    sb.write('tilecount="${ts.tileCount}" columns="${ts.columns}">');
    sb.write('<image source="${ts.image}" ');
    sb.write('width="${ts.columns * tileWidth}" ');
    sb.writeln('height="${(ts.tileCount ~/ ts.columns) * tileHeight}"/>');
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

  sb.writeln('</map>');
  return sb.toString();
}

/// Build a valid TSX XML string.
String buildTsx({
  required String name,
  required String imageSource,
  int tileWidth = 32,
  int tileHeight = 32,
  required int columns,
  required int tileCount,
}) {
  final imageWidth = columns * tileWidth;
  final imageHeight = (tileCount ~/ columns) * tileHeight;
  return '''<?xml version="1.0" encoding="UTF-8"?>
<tileset version="1.10" tiledversion="1.11.2" name="$name" tilewidth="$tileWidth" tileheight="$tileHeight" tilecount="$tileCount" columns="$columns">
 <image source="$imageSource" width="$imageWidth" height="$imageHeight"/>
</tileset>''';
}

/// Dummy PNG bytes for testing (not a real PNG, just placeholder bytes).
final _dummyPngBytes = Uint8List.fromList(List.filled(64, 0xFF));

void main() {
  group('TmxImporter', () {
    // -----------------------------------------------------------------------
    // Basic conversion
    // -----------------------------------------------------------------------

    group('basic conversion', () {
      test('converts a 3×3 map with a single floor layer', () {
        // 3×3 map using test_tileset.png (4 columns, 16 tiles).
        // GIDs: 1=tile0, 2=tile1, ... (firstGid=1)
        final tmx = buildTmx(
          width: 3,
          height: 3,
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
              name: 'Ground',
              csv: '1,2,3,\n4,5,6,\n7,8,9',
            ),
          ],
        );

        final result = TmxImporter.import(tmx, mapId: 'test', mapName: 'Test');
        final map = result.gameMap;

        expect(map.id, 'test');
        expect(map.name, 'Test');
        expect(map.floorLayer, isNotNull);

        // 3×3 map is padded to 50×50 — centered with offset (23, 23).
        final ox = (gridSize - 3) ~/ 2; // 23
        final oy = (gridSize - 3) ~/ 2; // 23

        // Top-left corner: GID 1 → tileIndex 0
        expect(
          map.floorLayer!.tileAt(ox, oy),
          const TileRef(tilesetId: 'test', tileIndex: 0),
        );
        // Center: GID 5 → tileIndex 4
        expect(
          map.floorLayer!.tileAt(ox + 1, oy + 1),
          const TileRef(tilesetId: 'test', tileIndex: 4),
        );
        // Bottom-right: GID 9 → tileIndex 8
        expect(
          map.floorLayer!.tileAt(ox + 2, oy + 2),
          const TileRef(tilesetId: 'test', tileIndex: 8),
        );
      });

      test('converts an exact 50×50 map without padding or cropping', () {
        // Build a 50×50 CSV where every cell is GID 1 (tileIndex 0).
        final row = List.filled(50, '1').join(',');
        final csv = List.filled(50, row).join(',\n');

        final tmx = buildTmx(
          width: 50,
          height: 50,
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
            (name: 'Floor', csv: csv),
          ],
        );

        final result = TmxImporter.import(tmx);

        // No padding/cropping warnings.
        expect(result.warnings.where((w) =>
            w.kind == TmxWarningKind.mapPadded ||
            w.kind == TmxWarningKind.mapCropped), isEmpty);

        // Tile at (0,0) should be set (no offset).
        expect(
          result.gameMap.floorLayer!.tileAt(0, 0),
          const TileRef(tilesetId: 'test', tileIndex: 0),
        );
        // Tile at (49,49) should also be set.
        expect(
          result.gameMap.floorLayer!.tileAt(49, 49),
          const TileRef(tilesetId: 'test', tileIndex: 0),
        );
      });

      test('handles empty cells (GID 0) correctly', () {
        final tmx = buildTmx(
          width: 3,
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
            (name: 'Floor', csv: '1,0,3'),
          ],
        );

        final result = TmxImporter.import(tmx);
        final ox = (gridSize - 3) ~/ 2;
        final oy = (gridSize - 1) ~/ 2;

        // GID 0 = empty cell.
        expect(result.gameMap.floorLayer!.tileAt(ox, oy), isNotNull);
        expect(result.gameMap.floorLayer!.tileAt(ox + 1, oy), isNull);
        expect(result.gameMap.floorLayer!.tileAt(ox + 2, oy), isNotNull);
      });
    });

    // -----------------------------------------------------------------------
    // Tileset matching
    // -----------------------------------------------------------------------

    group('tileset matching', () {
      test('matches TMX tileset to predefined tileset by image basename', () {
        final tmx = buildTmx(
          width: 1,
          height: 1,
          tilesets: [
            (
              name: 'AnyName',
              firstGid: 1,
              image: '../images/tilesets/ext_terrains.png',
              columns: 32,
              tileCount: 2368,
            ),
          ],
          layers: [
            (name: 'Ground', csv: '1'),
          ],
        );

        final result = TmxImporter.import(tmx);
        final ox = (gridSize - 1) ~/ 2;
        final oy = ox;

        // Should match 'ext_terrains' tileset by filename.
        expect(
          result.gameMap.floorLayer!.tileAt(ox, oy)!.tilesetId,
          'ext_terrains',
        );
      });

      test('falls back to matching TMX tileset name against predefined ID', () {
        // Image filename does NOT match any predefined tileset, but the
        // tileset name matches the predefined ID 'ext_terrains'.
        final tmx = buildTmx(
          width: 1,
          height: 1,
          tilesets: [
            (
              name: 'ext_terrains',
              firstGid: 1,
              image: 'some/other/path/renamed_terrain.png',
              columns: 32,
              tileCount: 2368,
            ),
          ],
          layers: [
            (name: 'Ground', csv: '1'),
          ],
        );

        final result = TmxImporter.import(tmx);
        final c = (gridSize - 1) ~/ 2;

        // Should match 'ext_terrains' by name fallback.
        expect(
          result.gameMap.floorLayer!.tileAt(c, c)!.tilesetId,
          'ext_terrains',
        );
      });

      test('name fallback is case-insensitive', () {
        // Tileset name uses different casing than predefined ID.
        final tmx = buildTmx(
          width: 1,
          height: 1,
          tilesets: [
            (
              name: 'Ext_Terrains',
              firstGid: 1,
              image: 'non_matching.png',
              columns: 32,
              tileCount: 2368,
            ),
          ],
          layers: [
            (name: 'Ground', csv: '1'),
          ],
        );

        final result = TmxImporter.import(tmx);
        final c = (gridSize - 1) ~/ 2;

        expect(
          result.gameMap.floorLayer!.tileAt(c, c)!.tilesetId,
          'ext_terrains',
        );
      });

      test('warns on unmatched tileset and drops those tiles', () {
        // Include one known tileset so the import succeeds (doesn't throw),
        // plus one unknown tileset whose tiles get dropped.
        final tmx = buildTmx(
          width: 2,
          height: 1,
          tilesets: [
            (
              name: 'Test',
              firstGid: 1,
              image: '../tilesets/test_tileset.png',
              columns: 4,
              tileCount: 16,
            ),
            (
              name: 'Unknown',
              firstGid: 17,
              image: 'unknown_tileset.png',
              columns: 4,
              tileCount: 16,
            ),
          ],
          layers: [
            // GID 1 → known tileset, GID 17 → unknown tileset.
            (name: 'Floor', csv: '1,17'),
          ],
        );

        final result = TmxImporter.import(tmx);

        expect(
          result.warnings
              .any((w) => w.kind == TmxWarningKind.unmatchedTileset),
          isTrue,
        );
        // Tile from unknown tileset should be dropped.
        expect(
          result.warnings.any((w) => w.kind == TmxWarningKind.tilesDropped),
          isTrue,
        );
      });

      test('resolves GIDs across multiple tilesets', () {
        // Two tilesets: test_tileset (firstGid=1, 16 tiles)
        //               room_builder_office (firstGid=17, 224 tiles).
        final tmx = buildTmx(
          width: 2,
          height: 1,
          tilesets: [
            (
              name: 'Test',
              firstGid: 1,
              image: '../tilesets/test_tileset.png',
              columns: 4,
              tileCount: 16,
            ),
            (
              name: 'RoomBuilder',
              firstGid: 17,
              image: '../tilesets/room_builder_office.png',
              columns: 16,
              tileCount: 224,
            ),
          ],
          layers: [
            // GID 5 → test_tileset tile 4; GID 17 → room_builder_office tile 0
            (name: 'Objects', csv: '5,17'),
          ],
        );

        final result = TmxImporter.import(tmx);
        final ox = (gridSize - 2) ~/ 2;
        final oy = (gridSize - 1) ~/ 2;

        expect(
          result.gameMap.objectLayer!.tileAt(ox, oy),
          const TileRef(tilesetId: 'test', tileIndex: 4),
        );
        expect(
          result.gameMap.objectLayer!.tileAt(ox + 1, oy),
          const TileRef(tilesetId: 'room_builder_office', tileIndex: 0),
        );
      });
    });

    // -----------------------------------------------------------------------
    // GID resolution
    // -----------------------------------------------------------------------

    group('GID resolution', () {
      test('correctly subtracts firstGid to get local tile index', () {
        // firstGid=1, GID=10 → tileIndex=9
        final tmx = buildTmx(
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
            (name: 'Floor', csv: '10'),
          ],
        );

        final result = TmxImporter.import(tmx);
        // 1×1 map centered: offset = (50-1)~/2 = 24
        final c = (gridSize - 1) ~/ 2;

        expect(result.gameMap.floorLayer!.tileAt(c, c)!.tileIndex, 9);
      });

      test('warns when tiles have flip bits set', () {
        // Horizontal flip flag: 0x80000000. GID 1 with h-flip = 0x80000001.
        const flippedGid = 0x80000000 | 1; // 2147483649
        final tmx = buildTmx(
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
            (name: 'Floor', csv: '$flippedGid'),
          ],
        );

        final result = TmxImporter.import(tmx);

        expect(
          result.warnings.any((w) => w.kind == TmxWarningKind.flipIgnored),
          isTrue,
        );
        // Should still place the tile (ignoring flip).
        final c = (gridSize - 1) ~/ 2;
        expect(
          result.gameMap.floorLayer!.tileAt(c, c),
          const TileRef(tilesetId: 'test', tileIndex: 0),
        );
      });
    });

    // -----------------------------------------------------------------------
    // Layer classification
    // -----------------------------------------------------------------------

    group('layer classification', () {
      test('classifies layers by name — floor keywords → floor layer', () {
        final tmx = buildTmx(
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
            (name: 'terrain_base', csv: '1'),
          ],
        );

        final result = TmxImporter.import(tmx);
        expect(result.gameMap.floorLayer, isNotNull);
        expect(result.gameMap.objectLayer, isNull);
      });

      test('classifies layers by name — object keywords → object layer', () {
        final tmx = buildTmx(
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
            (name: 'Furniture', csv: '1'),
          ],
        );

        final result = TmxImporter.import(tmx);
        expect(result.gameMap.floorLayer, isNull);
        expect(result.gameMap.objectLayer, isNotNull);
      });

      test('fallback: first tile layer → floor, rest → objects', () {
        final tmx = buildTmx(
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
            (name: 'Layer1', csv: '1'),
            (name: 'Layer2', csv: '2'),
          ],
        );

        final result = TmxImporter.import(tmx);
        // 1×1 map centered: offset = (50-1)~/2 = 24
        final c = (gridSize - 1) ~/ 2;

        expect(result.gameMap.floorLayer, isNotNull);
        expect(result.gameMap.objectLayer, isNotNull);

        // Layer1 → floor (tileIndex 0), Layer2 → objects (tileIndex 1).
        expect(result.gameMap.floorLayer!.tileAt(c, c)!.tileIndex, 0);
        expect(result.gameMap.objectLayer!.tileAt(c, c)!.tileIndex, 1);
      });

      test('composites multiple floor layers (later overwrites earlier)', () {
        final tmx = buildTmx(
          width: 2,
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
            (name: 'Ground', csv: '1,2'),
            (name: 'Base overlay', csv: '0,5'), // only second cell overwritten
          ],
        );

        final result = TmxImporter.import(tmx);
        final ox = (gridSize - 2) ~/ 2;
        final oy = (gridSize - 1) ~/ 2;

        // (ox, oy): Ground=1 → 0, overlay=0 (empty) → kept from Ground.
        expect(result.gameMap.floorLayer!.tileAt(ox, oy)!.tileIndex, 0);
        // (ox+1, oy): Ground=2 → 1, overlay=5 → 4. Overlay overwrites.
        expect(result.gameMap.floorLayer!.tileAt(ox + 1, oy)!.tileIndex, 4);
      });
    });

    // -----------------------------------------------------------------------
    // Grid size handling
    // -----------------------------------------------------------------------

    group('grid size handling', () {
      test('pads small maps to 50×50 centered and warns', () {
        final tmx = buildTmx(
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
            (name: 'Floor', csv: '1,1,1,1,\n1,1,1,1,\n1,1,1,1,\n1,1,1,1'),
          ],
        );

        final result = TmxImporter.import(tmx);
        expect(
          result.warnings.any((w) => w.kind == TmxWarningKind.mapPadded),
          isTrue,
        );

        final ox = (gridSize - 4) ~/ 2; // 23
        final oy = (gridSize - 4) ~/ 2;

        // Cell before offset should be empty.
        expect(result.gameMap.floorLayer!.tileAt(ox - 1, oy), isNull);
        // Cell at offset should have data.
        expect(result.gameMap.floorLayer!.tileAt(ox, oy), isNotNull);
        // Cell after content should be empty.
        expect(result.gameMap.floorLayer!.tileAt(ox + 4, oy), isNull);
      });

      test('crops maps larger than 50×50 and warns', () {
        final row = List.filled(60, '1').join(',');
        final csv = List.filled(60, row).join(',\n');

        final tmx = buildTmx(
          width: 60,
          height: 60,
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
            (name: 'Floor', csv: csv),
          ],
        );

        final result = TmxImporter.import(tmx);
        expect(
          result.warnings.any((w) => w.kind == TmxWarningKind.mapCropped),
          isTrue,
        );

        // Should still have valid data at edges.
        expect(result.gameMap.floorLayer!.tileAt(0, 0), isNotNull);
        expect(result.gameMap.floorLayer!.tileAt(49, 49), isNotNull);
      });
    });

    // -----------------------------------------------------------------------
    // Barrier extraction
    // -----------------------------------------------------------------------

    group('barrier extraction', () {
      test('auto-detects barriers from tileset barrier metadata', () {
        // room_builder_office: tile indices 0–79 are barriers.
        // firstGid=1, so GID 1 → tileIndex 0 (barrier), GID 81 → tileIndex 80
        // (not barrier).
        final tmx = buildTmx(
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
            // GID 1 = barrier tile, GID 81 = non-barrier tile
            (name: 'Objects', csv: '1,81'),
          ],
        );

        final result = TmxImporter.import(tmx);
        final ox = (gridSize - 2) ~/ 2;
        final oy = (gridSize - 1) ~/ 2;

        // First tile is a barrier (tileIndex 0, which is in barrierTileIndices).
        expect(result.gameMap.barriers, contains(Point(ox, oy)));
        // Second tile is not a barrier.
        expect(result.gameMap.barriers, isNot(contains(Point(ox + 1, oy))));
      });

      test('does not create barriers for floor-layer tiles unless tagged', () {
        // ext_terrains: barrier tiles are only at indices 2262+ (fences).
        // GID 1 → tileIndex 0 → not a barrier.
        final tmx = buildTmx(
          width: 1,
          height: 1,
          tilesets: [
            (
              name: 'Terrains',
              firstGid: 1,
              image: '../tilesets/ext_terrains.png',
              columns: 32,
              tileCount: 2368,
            ),
          ],
          layers: [
            (name: 'Ground', csv: '1'),
          ],
        );

        final result = TmxImporter.import(tmx);
        expect(result.gameMap.barriers, isEmpty);
      });
    });

    // -----------------------------------------------------------------------
    // Spawn and terminal extraction
    // -----------------------------------------------------------------------

    group('spawn/terminal extraction', () {
      test('extracts spawn from object group', () {
        final tmx = buildTmx(
          width: 10,
          height: 10,
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
              csv: List.filled(10, List.filled(10, '1').join(',')).join(',\n'),
            ),
          ],
          objectGroups: [
            (
              name: 'Objects',
              objectsXml:
                  '<object id="1" name="Spawn" type="spawn" x="160" y="160" width="32" height="32"/>',
            ),
          ],
        );

        final result = TmxImporter.import(tmx);
        final ox = (gridSize - 10) ~/ 2; // 20
        final oy = (gridSize - 10) ~/ 2;

        // x=160, y=160 → grid (160/32, 160/32) = (5, 5) + offset (20, 20)
        expect(result.gameMap.spawnPoint, Point(ox + 5, oy + 5));
      });

      test('extracts terminals from object group', () {
        final tmx = buildTmx(
          width: 10,
          height: 10,
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
              csv: List.filled(10, List.filled(10, '1').join(',')).join(',\n'),
            ),
          ],
          objectGroups: [
            (
              name: 'Objects',
              objectsXml: '''
<object id="1" name="Terminal1" type="terminal" x="64" y="96" width="32" height="32"/>
<object id="2" name="Terminal2" type="terminal" x="192" y="128" width="32" height="32"/>''',
            ),
          ],
        );

        final result = TmxImporter.import(tmx);
        final ox = (gridSize - 10) ~/ 2;
        final oy = (gridSize - 10) ~/ 2;

        expect(result.gameMap.terminals, hasLength(2));
        expect(result.gameMap.terminals, contains(Point(ox + 2, oy + 3)));
        expect(result.gameMap.terminals, contains(Point(ox + 6, oy + 4)));
      });

      test('defaults spawn to center when no spawn object found', () {
        final tmx = buildTmx(
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

        final result = TmxImporter.import(tmx);

        expect(
          result.warnings.any((w) => w.kind == TmxWarningKind.noSpawnFound),
          isTrue,
        );
        expect(result.gameMap.spawnPoint, const Point(25, 25));
      });
    });

    // -----------------------------------------------------------------------
    // Error cases
    // -----------------------------------------------------------------------

    group('error cases', () {
      test('throws on non-orthogonal orientation', () {
        final tmx = buildTmx(
          orientation: 'isometric',
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

        expect(
          () => TmxImporter.import(tmx),
          throwsA(isA<TmxImportException>()),
        );
      });

      test('throws when all tilesets are unrecognized', () {
        final tmx = buildTmx(
          width: 1,
          height: 1,
          tilesets: [
            (
              name: 'Unknown',
              firstGid: 1,
              image: 'unknown.png',
              columns: 4,
              tileCount: 16,
            ),
          ],
          layers: [
            (name: 'Floor', csv: '1'),
          ],
        );

        expect(
          () => TmxImporter.import(tmx),
          throwsA(isA<TmxImportException>()),
        );
      });

      test('throws on invalid XML', () {
        expect(
          () => TmxImporter.import('not valid xml at all'),
          throwsA(anything),
        );
      });

      test('throws when no tile layers exist', () {
        final tmx = buildTmx(
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
          // No tile layers, only object groups.
          objectGroups: [
            (
              name: 'Objects',
              objectsXml:
                  '<object id="1" name="Spawn" type="spawn" x="0" y="0"/>',
            ),
          ],
        );

        expect(
          () => TmxImporter.import(tmx),
          throwsA(isA<TmxImportException>()),
        );
      });
    });

    // -----------------------------------------------------------------------
    // Tile size warning
    // -----------------------------------------------------------------------

    group('tile size', () {
      test('warns when TMX tile size differs from game tile size', () {
        final tmx = buildTmx(
          width: 1,
          height: 1,
          tileWidth: 16, // Game expects 32
          tileHeight: 16,
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

        final result = TmxImporter.import(tmx);
        expect(
          result.warnings.any((w) => w.kind == TmxWarningKind.wrongTileSize),
          isTrue,
        );
      });
    });

    // -----------------------------------------------------------------------
    // Tileset IDs in output
    // -----------------------------------------------------------------------

    group('output metadata', () {
      test('populates tilesetIds with all matched tilesets', () {
        final tmx = buildTmx(
          width: 2,
          height: 1,
          tilesets: [
            (
              name: 'Test',
              firstGid: 1,
              image: '../tilesets/test_tileset.png',
              columns: 4,
              tileCount: 16,
            ),
            (
              name: 'RoomBuilder',
              firstGid: 17,
              image: '../tilesets/room_builder_office.png',
              columns: 16,
              tileCount: 224,
            ),
          ],
          layers: [
            (name: 'Floor', csv: '1,17'),
          ],
        );

        final result = TmxImporter.import(tmx);
        expect(result.gameMap.tilesetIds, containsAll(['test', 'room_builder_office']));
      });

      test('generates mapId from mapName when not provided', () {
        final tmx = buildTmx(
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

        final result =
            TmxImporter.import(tmx, mapName: 'My Cool Map');
        expect(result.gameMap.name, 'My Cool Map');
        expect(result.gameMap.id, 'my_cool_map');
      });

      test('uses default name when none provided', () {
        final tmx = buildTmx(
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

        final result = TmxImporter.import(tmx);
        expect(result.gameMap.name, 'Imported Map');
        expect(result.gameMap.id, 'imported_map');
      });
    });

    // -----------------------------------------------------------------
    // analyze()
    // -----------------------------------------------------------------

    group('analyze', () {
      test('identifies predefined tilesets as resolved', () {
        final tmx = buildTmx(
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

        final analysis = TmxImporter.analyze(tmx);

        expect(analysis.resolvedTilesets, hasLength(1));
        expect(analysis.resolvedTilesets.first, 'test');
        expect(analysis.unresolvedTilesets, isEmpty);
      });

      test('identifies unknown tilesets as unresolved', () {
        final tmx = buildTmx(
          width: 1,
          height: 1,
          tilesets: [
            (
              name: 'Desert',
              firstGid: 1,
              image: 'desert_tiles.png',
              columns: 8,
              tileCount: 64,
            ),
          ],
          layers: [
            (name: 'Floor', csv: '1'),
          ],
        );

        final analysis = TmxImporter.analyze(tmx);

        expect(analysis.resolvedTilesets, isEmpty);
        expect(analysis.unresolvedTilesets, hasLength(1));
        expect(analysis.unresolvedTilesets.first.imageSource,
            'desert_tiles.png');
      });

      test('separates mixed predefined and unknown tilesets', () {
        final tmx = buildTmx(
          width: 2,
          height: 1,
          tilesets: [
            (
              name: 'Test',
              firstGid: 1,
              image: '../tilesets/test_tileset.png',
              columns: 4,
              tileCount: 16,
            ),
            (
              name: 'Desert',
              firstGid: 17,
              image: 'desert_tiles.png',
              columns: 8,
              tileCount: 64,
            ),
          ],
          layers: [
            (name: 'Floor', csv: '1,17'),
          ],
        );

        final analysis = TmxImporter.analyze(tmx);

        expect(analysis.resolvedTilesets, ['test']);
        expect(analysis.unresolvedTilesets, hasLength(1));
        expect(analysis.unresolvedTilesets.first.name, 'Desert');
      });

      test('resolves external TSX tilesets via providers', () {
        final tmx = buildTmxWithExternalTsx(
          width: 1,
          height: 1,
          externalTilesets: [
            (source: 'desert.tsx', firstGid: 1),
          ],
          layers: [
            (name: 'Floor', csv: '1'),
          ],
        );

        final tsxXml = buildTsx(
          name: 'Desert',
          imageSource: 'desert_tiles.png',
          columns: 8,
          tileCount: 64,
        );

        final analysis = TmxImporter.analyze(
          tmx,
          tsxProviders: [InMemoryTsxProvider('desert.tsx', tsxXml)],
        );

        // TSX resolved, but image not predefined → unresolved.
        expect(analysis.unresolvedTilesets, hasLength(1));
        expect(analysis.unresolvedTilesets.first.imageSource,
            'desert_tiles.png');
      });
    });

    // -----------------------------------------------------------------
    // importWithCustomTilesets()
    // -----------------------------------------------------------------

    group('importWithCustomTilesets', () {
      test('imports unknown tileset when image bytes provided', () {
        final tmx = buildTmx(
          width: 1,
          height: 1,
          tilesets: [
            (
              name: 'Desert',
              firstGid: 1,
              image: 'desert_tiles.png',
              columns: 8,
              tileCount: 64,
            ),
          ],
          layers: [
            (name: 'Floor', csv: '1'),
          ],
        );

        final result = TmxImporter.importWithCustomTilesets(
          tmx,
          customImages: {'desert_tiles.png': _dummyPngBytes},
        );

        // Should not throw, should produce a valid map with tiles.
        final c = (gridSize - 1) ~/ 2;
        expect(result.gameMap.floorLayer, isNotNull);
        expect(result.gameMap.floorLayer!.tileAt(c, c), isNotNull);
        // The tile should reference a custom tileset.
        expect(
          result.gameMap.floorLayer!.tileAt(c, c)!.tilesetId,
          startsWith('custom_'),
        );
        // Custom tilesets should be in the result.
        expect(result.customTilesets, hasLength(1));
        expect(result.customTilesets.first.isCustom, isTrue);
        expect(result.customTilesets.first.columns, 8);
      });

      test('mixes predefined and custom tilesets', () {
        final tmx = buildTmx(
          width: 2,
          height: 1,
          tilesets: [
            (
              name: 'Test',
              firstGid: 1,
              image: '../tilesets/test_tileset.png',
              columns: 4,
              tileCount: 16,
            ),
            (
              name: 'Desert',
              firstGid: 17,
              image: 'desert_tiles.png',
              columns: 8,
              tileCount: 64,
            ),
          ],
          layers: [
            // GID 1 → predefined, GID 17 → custom.
            (name: 'Floor', csv: '1,17'),
          ],
        );

        final result = TmxImporter.importWithCustomTilesets(
          tmx,
          customImages: {'desert_tiles.png': _dummyPngBytes},
        );

        final ox = (gridSize - 2) ~/ 2;
        final oy = (gridSize - 1) ~/ 2;

        // Predefined tile.
        expect(
          result.gameMap.floorLayer!.tileAt(ox, oy)!.tilesetId,
          'test',
        );
        // Custom tile.
        expect(
          result.gameMap.floorLayer!.tileAt(ox + 1, oy)!.tilesetId,
          startsWith('custom_'),
        );
      });

      test('resolves external TSX and imports with custom images', () {
        final tmx = buildTmxWithExternalTsx(
          width: 1,
          height: 1,
          externalTilesets: [
            (source: 'desert.tsx', firstGid: 1),
          ],
          layers: [
            (name: 'Floor', csv: '1'),
          ],
        );

        final tsxXml = buildTsx(
          name: 'Desert',
          imageSource: 'desert_tiles.png',
          columns: 8,
          tileCount: 64,
        );

        final result = TmxImporter.importWithCustomTilesets(
          tmx,
          customImages: {'desert_tiles.png': _dummyPngBytes},
          tsxProviders: [InMemoryTsxProvider('desert.tsx', tsxXml)],
        );

        final c = (gridSize - 1) ~/ 2;
        expect(result.gameMap.floorLayer!.tileAt(c, c), isNotNull);
        expect(result.customTilesets, hasLength(1));
      });

      test('same image bytes produce same custom tileset ID (content hash)',
          () {
        final tmx = buildTmx(
          width: 1,
          height: 1,
          tilesets: [
            (
              name: 'Desert',
              firstGid: 1,
              image: 'desert_tiles.png',
              columns: 8,
              tileCount: 64,
            ),
          ],
          layers: [
            (name: 'Floor', csv: '1'),
          ],
        );

        final result1 = TmxImporter.importWithCustomTilesets(
          tmx,
          customImages: {'desert_tiles.png': _dummyPngBytes},
        );
        final result2 = TmxImporter.importWithCustomTilesets(
          tmx,
          customImages: {'desert_tiles.png': _dummyPngBytes},
        );

        // Same content → same ID.
        expect(
          result1.customTilesets.first.id,
          result2.customTilesets.first.id,
        );
      });

      test('backward compatible: existing import() still works unchanged', () {
        final tmx = buildTmx(
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

        // Original API should still work.
        final result = TmxImporter.import(tmx);
        final c = (gridSize - 1) ~/ 2;
        expect(result.gameMap.floorLayer!.tileAt(c, c)!.tilesetId, 'test');
      });
    });
  });
}
