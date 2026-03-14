// ignore_for_file: avoid_print

/// Slices `assets/images/single_room.png` into deduplicated 32x32 tiles.
///
/// Outputs:
///   - `assets/images/tilesets/single_room.png` — compact sprite sheet
///   - `lib/flame/maps/l_room_tile_data.dart` — generated tile mapping code
///
/// Run: `dart run tool/slice_tileset.dart`
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// Grid and tile constants matching the game.
const gridSize = 50;
const tileSize = 32;
const cropPixels = gridSize * tileSize; // 1600

/// Maximum sprite sheet width in tiles (keep sheets reasonably wide).
const sheetColumns = 32;

/// Old L-Room barrier positions (from before PR #200).
const oldBarriers = <(int, int)>{
  // Vertical wall at x=4
  (4, 7), (4, 8), (4, 9), (4, 10), (4, 11), (4, 12), (4, 13), (4, 14),
  (4, 15), (4, 16), (4, 18), (4, 19), (4, 20), (4, 21), (4, 22), (4, 23),
  (4, 24), (4, 25), (4, 26), (4, 27), (4, 28), (4, 29),
  // Horizontal wall at y=7
  (5, 7), (6, 7), (7, 7), (8, 7), (9, 7), (10, 7), (11, 7), (12, 7),
  (13, 7), (14, 7), (15, 7), (16, 7), (17, 7),
};

void main() {
  final projectRoot = Directory.current.path;
  final inputPath = '$projectRoot/assets/images/single_room.png';
  final outputSheetPath =
      '$projectRoot/assets/images/tilesets/single_room.png';
  final outputDartPath = '$projectRoot/lib/flame/maps/l_room_tile_data.dart';

  // Load source image.
  final bytes = File(inputPath).readAsBytesSync();
  final source = img.decodePng(bytes);
  if (source == null) {
    stderr.writeln('Failed to decode $inputPath');
    exit(1);
  }
  print('Source: ${source.width}x${source.height} '
      '(${source.width ~/ tileSize}x${source.height ~/ tileSize} tiles)');

  // Crop to 50x50 tile region (top-left 1600x1600).
  final cropped = img.copyCrop(
    source,
    x: 0,
    y: 0,
    width: cropPixels,
    height: cropPixels,
  );

  // Extract all tiles and deduplicate.
  final uniqueTiles = <Uint8List>[]; // raw RGBA bytes per unique tile
  final tileKeyToIndex = <String, int>{}; // pixel-hash -> unique index
  final gridMapping =
      List.generate(gridSize, (_) => List.filled(gridSize, 0));

  for (var gy = 0; gy < gridSize; gy++) {
    for (var gx = 0; gx < gridSize; gx++) {
      final tile = img.copyCrop(
        cropped,
        x: gx * tileSize,
        y: gy * tileSize,
        width: tileSize,
        height: tileSize,
      );
      final key = _tileFingerprint(tile);

      if (!tileKeyToIndex.containsKey(key)) {
        tileKeyToIndex[key] = uniqueTiles.length;
        uniqueTiles.add(_tileToRgba(tile));
      }
      gridMapping[gy][gx] = tileKeyToIndex[key]!;
    }
  }

  print('Unique tiles: ${uniqueTiles.length} / ${gridSize * gridSize}');

  // Build sprite sheet.
  final sheetCols = sheetColumns.clamp(1, uniqueTiles.length);
  final sheetRows = (uniqueTiles.length + sheetCols - 1) ~/ sheetCols;
  final sheet = img.Image(
    width: sheetCols * tileSize,
    height: sheetRows * tileSize,
    numChannels: 4,
  );

  for (var i = 0; i < uniqueTiles.length; i++) {
    final col = i % sheetCols;
    final row = i ~/ sheetCols;
    final rgba = uniqueTiles[i];
    for (var py = 0; py < tileSize; py++) {
      for (var px = 0; px < tileSize; px++) {
        final offset = (py * tileSize + px) * 4;
        sheet.setPixelRgba(
          col * tileSize + px,
          row * tileSize + py,
          rgba[offset],
          rgba[offset + 1],
          rgba[offset + 2],
          rgba[offset + 3],
        );
      }
    }
  }

  // Write sprite sheet.
  File(outputSheetPath).writeAsBytesSync(img.encodePng(sheet));
  print('Sprite sheet: ${sheet.width}x${sheet.height} '
      '($sheetCols x $sheetRows tiles) -> $outputSheetPath');

  // Identify barrier tile indices from old barrier positions.
  final barrierTileIndices = <int>{};
  for (final (bx, by) in oldBarriers) {
    if (bx < gridSize && by < gridSize) {
      barrierTileIndices.add(gridMapping[by][bx]);
    }
  }
  print('Barrier tile indices: ${barrierTileIndices.length}');

  // Generate Dart source file.
  final dartCode = _generateDart(
    gridMapping: gridMapping,
    barrierTileIndices: barrierTileIndices,
    sheetCols: sheetCols,
    sheetRows: sheetRows,
    uniqueCount: uniqueTiles.length,
  );
  File(outputDartPath)
    ..createSync(recursive: true)
    ..writeAsStringSync(dartCode);
  print('Dart source -> $outputDartPath');
}

/// Generates a fingerprint string for a tile image (hex of RGBA bytes).
String _tileFingerprint(img.Image tile) {
  final buf = StringBuffer();
  for (var y = 0; y < tile.height; y++) {
    for (var x = 0; x < tile.width; x++) {
      final p = tile.getPixel(x, y);
      buf
        ..write(p.r.toInt().toRadixString(16).padLeft(2, '0'))
        ..write(p.g.toInt().toRadixString(16).padLeft(2, '0'))
        ..write(p.b.toInt().toRadixString(16).padLeft(2, '0'))
        ..write(p.a.toInt().toRadixString(16).padLeft(2, '0'));
    }
  }
  return buf.toString();
}

/// Extracts raw RGBA bytes from a tile image.
Uint8List _tileToRgba(img.Image tile) {
  final bytes = Uint8List(tileSize * tileSize * 4);
  var offset = 0;
  for (var y = 0; y < tileSize; y++) {
    for (var x = 0; x < tileSize; x++) {
      final p = tile.getPixel(x, y);
      bytes[offset++] = p.r.toInt();
      bytes[offset++] = p.g.toInt();
      bytes[offset++] = p.b.toInt();
      bytes[offset++] = p.a.toInt();
    }
  }
  return bytes;
}

/// Generates the Dart source code for l_room_tile_data.dart.
String _generateDart({
  required List<List<int>> gridMapping,
  required Set<int> barrierTileIndices,
  required int sheetCols,
  required int sheetRows,
  required int uniqueCount,
}) {
  final buf = StringBuffer();

  buf.writeln("/// Generated tile data for the L-Room map's offline fallback.");
  buf.writeln('///');
  buf.writeln(
      '/// Auto-generated by `dart run tool/slice_tileset.dart` — do not edit.');
  buf.writeln('library;');
  buf.writeln();
  buf.writeln("import 'package:tech_world/flame/tiles/tile_layer_data.dart';");
  buf.writeln("import 'package:tech_world/flame/tiles/tile_ref.dart';");
  buf.writeln();

  // Tileset constants.
  buf.writeln('/// Sprite sheet dimensions for the single_room tileset.');
  buf.writeln('const lRoomTilesetColumns = $sheetCols;');
  buf.writeln('const lRoomTilesetRows = $sheetRows;');
  buf.writeln('const lRoomUniqueTileCount = $uniqueCount;');
  buf.writeln();

  // Barrier tile indices.
  final sortedBarriers = barrierTileIndices.toList()..sort();
  buf.writeln('/// Tile indices that are barriers (walls) in the single_room '
      'tileset.');
  buf.writeln('const lRoomBarrierTileIndices = <int>{');
  buf.writeln('  ${sortedBarriers.join(', ')},');
  buf.writeln('};');
  buf.writeln();

  // Grid mapping as a compact list of tile indices per row.
  buf.writeln('/// Tile index for each grid cell, row-major (50x50).');
  buf.writeln('///');
  buf.writeln(
      '/// All tiles use tileset ID `single_room` and are placed on the floor '
      'layer.');
  buf.writeln('const _tileIndices = <List<int>>[');
  for (var y = 0; y < gridSize; y++) {
    buf.writeln('  [${gridMapping[y].join(', ')}],');
  }
  buf.writeln('];');
  buf.writeln();

  // Builder function for the floor layer.
  buf.writeln('/// Builds the floor [TileLayerData] for the L-Room.');
  buf.writeln('TileLayerData buildLRoomFloorLayer() {');
  buf.writeln('  final layer = TileLayerData();');
  buf.writeln('  for (var y = 0; y < _tileIndices.length; y++) {');
  buf.writeln('    final row = _tileIndices[y];');
  buf.writeln('    for (var x = 0; x < row.length; x++) {');
  buf.writeln(
      "      layer.setTile(x, y, TileRef(tilesetId: 'single_room', "
      'tileIndex: row[x]));');
  buf.writeln('    }');
  buf.writeln('  }');
  buf.writeln('  return layer;');
  buf.writeln('}');

  return buf.toString();
}
