import 'dart:math';

import 'package:tiled/tiled.dart' as tiled;

import 'package:tech_world/flame/maps/game_map.dart';
import 'package:tech_world/flame/shared/constants.dart';
import 'package:tech_world/flame/tiles/predefined_tilesets.dart'
    show allTilesets, isTileRefBarrier;
import 'package:tech_world/flame/tiles/tile_layer_data.dart';
import 'package:tech_world/flame/tiles/tile_ref.dart';
import 'package:tech_world/flame/tiles/tileset.dart';

// ---------------------------------------------------------------------------
// Result types
// ---------------------------------------------------------------------------

/// Result of a TMX import: the converted [GameMap] plus any warnings.
class TmxImportResult {
  const TmxImportResult({required this.gameMap, required this.warnings});

  final GameMap gameMap;
  final List<TmxImportWarning> warnings;
}

/// A non-fatal issue encountered during TMX import.
class TmxImportWarning {
  const TmxImportWarning({required this.kind, required this.message});

  final TmxWarningKind kind;
  final String message;

  @override
  String toString() => '${kind.name}: $message';
}

/// Categories of TMX import warnings.
enum TmxWarningKind {
  unmatchedTileset,
  mapCropped,
  mapPadded,
  tilesDropped,
  flipIgnored,
  noSpawnFound,
  wrongTileSize,
}

/// Fatal error during TMX import.
class TmxImportException implements Exception {
  const TmxImportException(this.message);

  final String message;

  @override
  String toString() => 'TmxImportException: $message';
}

// ---------------------------------------------------------------------------
// Layer name keywords for classification
// ---------------------------------------------------------------------------

const _floorKeywords = ['floor', 'ground', 'terrain', 'base'];
const _objectKeywords = ['object', 'furniture', 'wall', 'decor', 'prop'];

// ---------------------------------------------------------------------------
// Importer
// ---------------------------------------------------------------------------

/// Converts Tiled `.tmx` XML into a [GameMap] using the project's native
/// tile system.
///
/// Uses the `tiled` package for XML parsing and maps TMX tilesets to the
/// predefined tilesets registered in [allTilesets] by matching image
/// filenames.
class TmxImporter {
  TmxImporter._();

  /// Parse [tmxXml] and convert it to a [TmxImportResult].
  ///
  /// Optionally override the map's [mapId] and [mapName]. If [mapName] is
  /// provided without [mapId], the ID is derived from the name by
  /// lowercasing and replacing spaces with underscores.
  static TmxImportResult import(
    String tmxXml, {
    String? mapId,
    String? mapName,
  }) {
    final warnings = <TmxImportWarning>[];

    // 1. Parse XML.
    final tiled.TiledMap tiledMap;
    try {
      tiledMap = tiled.TileMapParser.parseTmx(tmxXml);
    } catch (e) {
      throw TmxImportException('Failed to parse TMX XML: $e');
    }

    // 2. Validate orientation.
    if (tiledMap.orientation != null &&
        tiledMap.orientation != tiled.MapOrientation.orthogonal) {
      throw TmxImportException(
        'Only orthogonal maps are supported, '
        'got ${tiledMap.orientation}.',
      );
    }

    // 3. Check tile size.
    if (tiledMap.tileWidth != gridSquareSize ||
        tiledMap.tileHeight != gridSquareSize) {
      warnings.add(TmxImportWarning(
        kind: TmxWarningKind.wrongTileSize,
        message:
            'TMX tile size is ${tiledMap.tileWidth}x${tiledMap.tileHeight}, '
            'expected ${gridSquareSize}x$gridSquareSize. '
            'Tiles will be mapped by index regardless.',
      ));
    }

    // 4. Build tileset mapping: TMX tileset → predefined Tileset.
    final tilesetMapping = _buildTilesetMapping(tiledMap.tilesets, warnings);
    if (tilesetMapping.isEmpty) {
      throw TmxImportException(
        'No TMX tilesets matched any predefined tileset. '
        'Ensure TMX tileset image filenames match those in assets/images/tilesets/.',
      );
    }

    // 5. Find tile layers.
    final tileLayers = tiledMap.layers
        .whereType<tiled.TileLayer>()
        .toList();
    if (tileLayers.isEmpty) {
      throw TmxImportException(
        'TMX file has no tile layers. At least one tile layer is required.',
      );
    }

    // 6. Classify tile layers into floor vs. object.
    final classified = _classifyLayers(tileLayers);

    // 7. Compute grid offset for centering / cropping.
    final mapW = tiledMap.width;
    final mapH = tiledMap.height;
    final (ox, oy, cropW, cropH) = _computeGridTransform(mapW, mapH, warnings);

    // 8. Convert tile layers.
    var hasFlippedTiles = false;
    var droppedTileCount = 0;

    TileLayerData? convertLayers(List<tiled.TileLayer> layers) {
      if (layers.isEmpty) return null;
      final layerData = TileLayerData();
      for (final layer in layers) {
        final tileData = layer.tileData;
        if (tileData == null) continue;
        for (var row = 0; row < cropH && row < tileData.length; row++) {
          final rowData = tileData[row];
          for (var col = 0; col < cropW && col < rowData.length; col++) {
            final gid = rowData[col];
            if (gid.tile == 0) continue; // Empty cell.

            // Check flips.
            if (gid.flips.horizontally ||
                gid.flips.vertically ||
                gid.flips.diagonally ||
                gid.flips.antiDiagonally) {
              hasFlippedTiles = true;
            }

            // Resolve tileset.
            final resolved = _resolveGid(gid.tile, tilesetMapping);
            if (resolved == null) {
              droppedTileCount++;
              continue;
            }

            final destX = ox + col;
            final destY = oy + row;
            if (destX >= 0 &&
                destX < gridSize &&
                destY >= 0 &&
                destY < gridSize) {
              layerData.setTile(destX, destY, resolved);
            }
          }
        }
      }
      return layerData.isEmpty ? null : layerData;
    }

    final floorLayer = convertLayers(classified.floor);
    final objectLayer = convertLayers(classified.objects);

    if (hasFlippedTiles) {
      warnings.add(const TmxImportWarning(
        kind: TmxWarningKind.flipIgnored,
        message: 'Some tiles have flip/rotation flags set. '
            'Flips are not supported and were ignored.',
      ));
    }
    if (droppedTileCount > 0) {
      warnings.add(TmxImportWarning(
        kind: TmxWarningKind.tilesDropped,
        message: '$droppedTileCount tile(s) from unmatched tilesets '
            'were dropped.',
      ));
    }

    // 9. Extract spawn/terminals from object groups.
    final objectGroups = tiledMap.layers
        .whereType<tiled.ObjectGroup>()
        .toList();

    Point<int>? spawnPoint;
    final terminals = <Point<int>>[];

    for (final group in objectGroups) {
      for (final obj in group.objects) {
        final type = obj.type.toLowerCase();
        final gridX = ox + (obj.x ~/ tiledMap.tileWidth);
        final gridY = oy + (obj.y ~/ tiledMap.tileHeight);

        if (type == 'spawn') {
          if (gridX >= 0 &&
              gridX < gridSize &&
              gridY >= 0 &&
              gridY < gridSize) {
            spawnPoint = Point(gridX, gridY);
          }
        } else if (type == 'terminal') {
          if (gridX >= 0 &&
              gridX < gridSize &&
              gridY >= 0 &&
              gridY < gridSize) {
            terminals.add(Point(gridX, gridY));
          }
        }
      }
    }

    if (spawnPoint == null) {
      warnings.add(const TmxImportWarning(
        kind: TmxWarningKind.noSpawnFound,
        message: 'No object with type "spawn" found. '
            'Using default spawn point (25, 25).',
      ));
    }

    // 10. Auto-detect barriers from tile metadata.
    final barriers = <Point<int>>[];
    _collectBarriers(floorLayer, barriers);
    _collectBarriers(objectLayer, barriers);

    // 11. Collect tileset IDs.
    final tilesetIds = <String>{
      if (floorLayer != null) ...floorLayer.referencedTilesetIds,
      if (objectLayer != null) ...objectLayer.referencedTilesetIds,
    }.toList();

    // 12. Resolve map name and ID.
    final name = mapName ?? 'Imported Map';
    final id = mapId ?? _nameToId(name);

    return TmxImportResult(
      gameMap: GameMap(
        id: id,
        name: name,
        barriers: barriers,
        spawnPoint: spawnPoint ?? const Point(25, 25),
        terminals: terminals,
        floorLayer: floorLayer,
        objectLayer: objectLayer,
        tilesetIds: tilesetIds,
      ),
      warnings: warnings,
    );
  }
}

// ---------------------------------------------------------------------------
// Tileset mapping
// ---------------------------------------------------------------------------

/// Maps TMX tileset firstGid ranges to our predefined [Tileset] objects.
///
/// Each entry records the TMX firstGid and the matched predefined tileset.
class _TilesetEntry {
  const _TilesetEntry({
    required this.firstGid,
    required this.tileCount,
    required this.tileset,
  });

  final int firstGid;
  final int tileCount;
  final Tileset tileset;
}

/// Build a sorted list of tileset mappings from TMX tilesets to predefined
/// tilesets, matched by image filename with a name-based fallback.
List<_TilesetEntry> _buildTilesetMapping(
  List<tiled.Tileset> tmxTilesets,
  List<TmxImportWarning> warnings,
) {
  // Build lookups: image basename → tileset, tileset ID → tileset.
  final imageLookup = <String, Tileset>{};
  final idLookup = <String, Tileset>{};
  for (final ts in allTilesets) {
    // imagePath is like 'tilesets/ext_terrains.png' — extract filename.
    final basename = ts.imagePath.split('/').last;
    imageLookup[basename] = ts;
    idLookup[ts.id] = ts;
  }

  final entries = <_TilesetEntry>[];
  for (final tmxTs in tmxTilesets) {
    final firstGid = tmxTs.firstGid;
    if (firstGid == null) continue;

    final imageSource = tmxTs.image?.source;

    // Try 1: Match by image filename.
    Tileset? matched;
    if (imageSource != null) {
      final basename = imageSource.split('/').last;
      matched = imageLookup[basename];
    }

    // Try 2: Match by tileset name → predefined tileset ID.
    if (matched == null) {
      final name = tmxTs.name;
      if (name != null) {
        matched = idLookup[name];
      }
    }

    if (matched == null) {
      final label = imageSource?.split('/').last ?? tmxTs.name ?? '(unnamed)';
      warnings.add(TmxImportWarning(
        kind: TmxWarningKind.unmatchedTileset,
        message: 'TMX tileset "$label" does not match any predefined '
            'tileset. Its tiles will be dropped.',
      ));
      continue;
    }

    entries.add(_TilesetEntry(
      firstGid: firstGid,
      tileCount: tmxTs.tileCount ?? matched.tileCount,
      tileset: matched,
    ));
  }

  // Sort by firstGid ascending for binary-search-style lookup.
  entries.sort((a, b) => a.firstGid.compareTo(b.firstGid));
  return entries;
}

/// Resolve a global tile ID to a [TileRef] using the tileset mapping.
///
/// Returns null if the GID doesn't belong to any matched tileset.
TileRef? _resolveGid(int globalId, List<_TilesetEntry> mapping) {
  // Find the tileset whose range contains this GID.
  // Tilesets are sorted by firstGid; we want the last one where
  // firstGid <= globalId.
  _TilesetEntry? matched;
  for (final entry in mapping) {
    if (entry.firstGid <= globalId) {
      matched = entry;
    } else {
      break;
    }
  }

  if (matched == null) return null;

  final localIndex = globalId - matched.firstGid;
  if (localIndex < 0 || localIndex >= matched.tileCount) return null;

  return TileRef(tilesetId: matched.tileset.id, tileIndex: localIndex);
}

// ---------------------------------------------------------------------------
// Layer classification
// ---------------------------------------------------------------------------

class _ClassifiedLayers {
  const _ClassifiedLayers({required this.floor, required this.objects});

  final List<tiled.TileLayer> floor;
  final List<tiled.TileLayer> objects;
}

/// Classify tile layers as floor or object by name heuristics.
_ClassifiedLayers _classifyLayers(List<tiled.TileLayer> layers) {
  final floor = <tiled.TileLayer>[];
  final objects = <tiled.TileLayer>[];
  final unclassified = <tiled.TileLayer>[];

  for (final layer in layers) {
    final nameLower = layer.name.toLowerCase();
    if (_floorKeywords.any((kw) => nameLower.contains(kw))) {
      floor.add(layer);
    } else if (_objectKeywords.any((kw) => nameLower.contains(kw))) {
      objects.add(layer);
    } else {
      unclassified.add(layer);
    }
  }

  // Fallback: first unclassified → floor, rest → objects.
  if (unclassified.isNotEmpty) {
    if (floor.isEmpty) {
      floor.add(unclassified.removeAt(0));
    }
    objects.addAll(unclassified);
  }

  return _ClassifiedLayers(floor: floor, objects: objects);
}

// ---------------------------------------------------------------------------
// Grid transform (centering / cropping)
// ---------------------------------------------------------------------------

/// Returns `(offsetX, offsetY, cropWidth, cropHeight)`.
(int, int, int, int) _computeGridTransform(
  int mapW,
  int mapH,
  List<TmxImportWarning> warnings,
) {
  int ox = 0;
  int oy = 0;
  int cropW = mapW;
  int cropH = mapH;

  if (mapW < gridSize || mapH < gridSize) {
    ox = (gridSize - mapW) ~/ 2;
    oy = (gridSize - mapH) ~/ 2;
    warnings.add(TmxImportWarning(
      kind: TmxWarningKind.mapPadded,
      message: 'Map is $mapW×$mapH, padded to '
          '$gridSize×$gridSize (offset $ox,$oy).',
    ));
  }

  if (mapW > gridSize || mapH > gridSize) {
    cropW = min(mapW, gridSize);
    cropH = min(mapH, gridSize);
    warnings.add(TmxImportWarning(
      kind: TmxWarningKind.mapCropped,
      message: 'Map is $mapW×$mapH, cropped to '
          '$gridSize×$gridSize.',
    ));
  }

  return (ox, oy, cropW, cropH);
}

// ---------------------------------------------------------------------------
// Barrier collection
// ---------------------------------------------------------------------------

/// Scan a tile layer and add barrier points for tiles tagged as barriers
/// in their predefined tileset.
void _collectBarriers(TileLayerData? layer, List<Point<int>> barriers) {
  if (layer == null) return;
  for (var y = 0; y < gridSize; y++) {
    for (var x = 0; x < gridSize; x++) {
      final ref = layer.tileAt(x, y);
      if (ref != null && isTileRefBarrier(ref)) {
        barriers.add(Point(x, y));
      }
    }
  }
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// Convert a display name to a snake_case ID.
String _nameToId(String name) {
  return name
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
      .replaceAll(RegExp(r'^_|_$'), '');
}
