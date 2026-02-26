import 'package:flame/cache.dart';
import 'package:flame/components.dart';
import 'package:flame/sprite.dart';
import 'package:tech_world/flame/tiles/tile_animation.dart';
import 'package:tech_world/flame/tiles/tile_animations.dart';
import 'package:tech_world/flame/tiles/tileset.dart';

/// Loads and caches tileset sprite sheets for tile rendering.
///
/// Tilesets are loaded from Flame's [Images] cache and converted to
/// [SpriteSheet] instances for efficient sprite lookup by tile index.
class TilesetRegistry {
  TilesetRegistry({required this.images});

  /// Creates a registry without an [Images] cache, for testing animation
  /// lookups that don't require sprite loading.
  TilesetRegistry.forTesting() : images = Images();

  /// Flame's shared image cache — typically `game.images`.
  final Images images;

  final Map<String, LoadedTileset> _loaded = {};

  /// Load a [Tileset] definition, creating a [SpriteSheet] from its image.
  ///
  /// Does nothing if the tileset is already loaded.
  Future<void> load(Tileset tileset) async {
    if (_loaded.containsKey(tileset.id)) return;

    final image = await images.load(tileset.imagePath);
    final sheet = SpriteSheet(
      image: image,
      srcSize: Vector2.all(tileset.tileSize.toDouble()),
    );

    _loaded[tileset.id] = LoadedTileset(
      tileset: tileset,
      spriteSheet: sheet,
    );
  }

  /// Load multiple tilesets at once.
  Future<void> loadAll(List<Tileset> tilesets) async {
    for (final tileset in tilesets) {
      await load(tileset);
    }
  }

  /// Look up a loaded tileset by ID. Returns null if not loaded.
  LoadedTileset? get(String tilesetId) => _loaded[tilesetId];

  /// Get a [Sprite] for a specific tileset tile by index.
  ///
  /// Returns null if the tileset isn't loaded or the index is out of range.
  Sprite? getSpriteForTile(String tilesetId, int tileIndex) {
    final loaded = _loaded[tilesetId];
    if (loaded == null) return null;

    final columns = loaded.tileset.columns;
    final row = tileIndex ~/ columns;
    final col = tileIndex % columns;

    if (row >= loaded.tileset.rows || col >= columns) return null;

    return loaded.spriteSheet.getSprite(row, col);
  }

  /// Whether a tileset with the given ID has been loaded.
  bool isLoaded(String tilesetId) => _loaded.containsKey(tilesetId);

  /// All currently loaded tileset IDs.
  Iterable<String> get loadedIds => _loaded.keys;

  /// Look up the [TileAnimation] for a tile in a given tileset.
  ///
  /// Returns the animation if [tileIndex] is any frame of an animation
  /// defined for [tilesetId], or `null` if the tile is static. Checks all
  /// frame indices (not just base), so any frame painted in the editor still
  /// triggers the animation.
  TileAnimation? getAnimationForTile(String tilesetId, int tileIndex) {
    return lookupAnimationForTile(tilesetId, tileIndex);
  }
}
