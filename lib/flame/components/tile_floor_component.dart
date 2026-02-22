import 'dart:ui';

import 'package:flame/components.dart';
import 'package:tech_world/flame/shared/constants.dart';
import 'package:tech_world/flame/tiles/animation_ticker.dart';
import 'package:tech_world/flame/tiles/tile_animation.dart';
import 'package:tech_world/flame/tiles/tile_layer_data.dart';
import 'package:tech_world/flame/tiles/tileset_registry.dart';

/// Renders the floor tile layer using a cached [Picture] for static tiles and
/// per-frame sprite rendering for animated tiles.
///
/// Static tiles are recorded once into a [Picture] and replayed each frame as
/// a single draw call. Animated tiles are skipped in the [Picture] and instead
/// rendered via shared [AnimationTicker]s so all instances of the same
/// animation play in sync (standard for pixel-art water, lava, etc.).
///
/// Priority is -2, placing it below the background image layer (-1) and all
/// game objects.
class TileFloorComponent extends Component {
  TileFloorComponent({
    required this.layerData,
    required this.registry,
  }) : super(priority: -2) {
    _partitionTiles();
  }

  final TileLayerData layerData;
  final TilesetRegistry registry;

  Picture? _cachedPicture;

  /// Animated tile entries — positions where animated tiles need per-frame
  /// rendering.
  final List<_AnimatedTileEntry> _animatedTiles = [];

  /// Grid positions of animated tiles, used by [_rebuildCache] to skip them
  /// without re-calling [TilesetRegistry.getAnimationForTile].
  final Set<(int, int)> _animatedPositions = {};

  /// Shared tickers keyed by [TileAnimation.baseTileIndex]. All tiles sharing
  /// the same animation use the same ticker to animate in sync.
  final Map<int, AnimationTicker> _tickers = {};

  /// Number of animated tile cells (for testing / debugging).
  int get animatedTileCount => _animatedTiles.length;

  /// Number of unique animation tickers (for testing / debugging).
  int get tickerCount => _tickers.length;

  /// Scans the layer and partitions tiles into animated vs static.
  ///
  /// Called during construction so [animatedTileCount] and [tickerCount] are
  /// available immediately (before [onLoad]).
  void _partitionTiles() {
    _animatedTiles.clear();
    _animatedPositions.clear();
    _tickers.clear();

    for (var y = 0; y < gridSize; y++) {
      for (var x = 0; x < gridSize; x++) {
        final ref = layerData.tileAt(x, y);
        if (ref == null) continue;

        final anim = registry.getAnimationForTile(ref.tilesetId, ref.tileIndex);
        if (anim != null) {
          _animatedTiles.add(
            _AnimatedTileEntry(
              x: x,
              y: y,
              tilesetId: ref.tilesetId,
              animation: anim,
            ),
          );
          _animatedPositions.add((x, y));
          // Create a shared ticker per unique animation.
          _tickers.putIfAbsent(
            anim.baseTileIndex,
            () => AnimationTicker(anim),
          );
        }
      }
    }
  }

  @override
  Future<void> onLoad() async {
    _rebuildCache();
  }

  void _rebuildCache() {
    _cachedPicture?.dispose();

    final recorder = PictureRecorder();
    final canvas = Canvas(recorder);

    for (var y = 0; y < gridSize; y++) {
      for (var x = 0; x < gridSize; x++) {
        final ref = layerData.tileAt(x, y);
        if (ref == null) continue;

        // Skip animated tiles — they're rendered per-frame in render().
        if (_animatedPositions.contains((x, y))) continue;

        final sprite = registry.getSpriteForTile(ref.tilesetId, ref.tileIndex);
        if (sprite == null) continue;

        sprite.render(
          canvas,
          position: Vector2(
            x * gridSquareSizeDouble,
            y * gridSquareSizeDouble,
          ),
          size: Vector2.all(gridSquareSizeDouble),
        );
      }
    }

    _cachedPicture = recorder.endRecording();
  }

  @override
  void update(double dt) {
    for (final ticker in _tickers.values) {
      ticker.update(dt);
    }
  }

  @override
  void render(Canvas canvas) {
    // Draw all static tiles as a single picture.
    if (_cachedPicture != null) {
      canvas.drawPicture(_cachedPicture!);
    }

    // Draw animated tiles using their shared tickers.
    for (final entry in _animatedTiles) {
      final ticker = _tickers[entry.animation.baseTileIndex];
      if (ticker == null) continue;

      final frameIndex = ticker.currentFrameIndex;
      final sprite =
          registry.getSpriteForTile(entry.tilesetId, frameIndex);
      if (sprite == null) continue;

      sprite.render(
        canvas,
        position: Vector2(
          entry.x * gridSquareSizeDouble,
          entry.y * gridSquareSizeDouble,
        ),
        size: Vector2.all(gridSquareSizeDouble),
      );
    }
  }

  @override
  void onRemove() {
    _cachedPicture?.dispose();
    _cachedPicture = null;
    _animatedTiles.clear();
    _animatedPositions.clear();
    _tickers.clear();
    super.onRemove();
  }
}

/// Tracks the position and animation for a single animated tile cell.
class _AnimatedTileEntry {
  const _AnimatedTileEntry({
    required this.x,
    required this.y,
    required this.tilesetId,
    required this.animation,
  });

  final int x;
  final int y;
  final String tilesetId;
  final TileAnimation animation;
}
