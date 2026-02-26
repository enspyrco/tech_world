import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tech_world/flame/maps/tmx_importer.dart';
import 'package:tech_world/flame/shared/constants.dart';

/// Smoke-test: import the hand-crafted sample_courtyard.tmx and verify the
/// result looks correct.
void main() {
  test('imports sample_courtyard.tmx and produces a valid GameMap', () {
    final tmxFile = File('test/flame/maps/sample_courtyard.tmx');
    expect(tmxFile.existsSync(), isTrue, reason: 'TMX file should exist');

    final tmxXml = tmxFile.readAsStringSync();
    final result = TmxImporter.import(
      tmxXml,
      mapId: 'sample_courtyard',
      mapName: 'Sample Courtyard',
    );

    final map = result.gameMap;

    // Print warnings for visibility.
    if (result.warnings.isNotEmpty) {
      // ignore: avoid_print
      print('TMX import warnings:');
      for (final w in result.warnings) {
        // ignore: avoid_print
        print('  - $w');
      }
    }

    // Basic metadata.
    expect(map.id, 'sample_courtyard');
    expect(map.name, 'Sample Courtyard');

    // 10×10 map padded to 50×50 — centered with offset (20, 20).
    final ox = (gridSize - 10) ~/ 2; // 20
    final oy = (gridSize - 10) ~/ 2; // 20

    // Floor layer should exist with ext_terrains tiles.
    expect(map.floorLayer, isNotNull, reason: 'Should have a floor layer');

    // Top-left corner: GID 1 → ext_terrains tileIndex 0 (grass).
    final grassTile = map.floorLayer!.tileAt(ox, oy);
    expect(grassTile, isNotNull, reason: 'Top-left should have a grass tile');
    expect(grassTile!.tilesetId, 'ext_terrains');
    expect(grassTile.tileIndex, 0);

    // Dirt path center: GID 65 → ext_terrains tileIndex 64.
    final dirtTile = map.floorLayer!.tileAt(ox + 4, oy + 1);
    expect(dirtTile, isNotNull, reason: 'Path should have a dirt tile');
    expect(dirtTile!.tilesetId, 'ext_terrains');
    expect(dirtTile.tileIndex, 64);

    // Object layer should exist with room_builder_office tiles.
    expect(map.objectLayer, isNotNull, reason: 'Should have an object layer');

    // Top-left wall: GID 2369 → room_builder_office tileIndex 0.
    final wallTile = map.objectLayer!.tileAt(ox, oy);
    expect(wallTile, isNotNull, reason: 'Top-left should have a wall tile');
    expect(wallTile!.tilesetId, 'room_builder_office');
    expect(wallTile.tileIndex, 0);

    // Spawn point: pixel (160,160) → grid (5,5) + offset → (25, 25).
    expect(map.spawnPoint.x, ox + 5);
    expect(map.spawnPoint.y, oy + 5);

    // Terminals: 2 coding stations.
    expect(map.terminals.length, 2);

    // Barriers: wall tiles from room_builder_office should be auto-detected.
    // (rows 0–4 are barriers in room_builder_office)
    expect(map.barriers, isNotEmpty, reason: 'Wall tiles should create barriers');

    // Tileset IDs should include both.
    expect(map.tilesetIds, containsAll(['ext_terrains', 'room_builder_office']));

    // ignore: avoid_print
    print('\nImport summary:');
    // ignore: avoid_print
    print('  Floor tiles: ext_terrains');
    // ignore: avoid_print
    print('  Object tiles: room_builder_office');
    // ignore: avoid_print
    print('  Spawn: (${map.spawnPoint.x}, ${map.spawnPoint.y})');
    // ignore: avoid_print
    print('  Terminals: ${map.terminals.length}');
    // ignore: avoid_print
    print('  Barriers: ${map.barriers.length}');
    // ignore: avoid_print
    print('  Warnings: ${result.warnings.length}');
  });
}
