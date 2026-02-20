import 'dart:ui';

import 'package:flame/components.dart';
import 'package:flutter/painting.dart' show HSLColor;
import 'package:tech_world/flame/shared/constants.dart';
import 'package:tech_world/flame/tech_world_game.dart';
import 'package:tech_world/flame/tiles/tile_layer_data.dart';
import 'package:tech_world/map_editor/map_editor_state.dart';
import 'package:tech_world/map_editor/tile_colors.dart';

/// Flame component that renders the map editor's grid state as colored tiles
/// in the game canvas.
///
/// Caches the grid as a [Picture] and only re-records when [MapEditorState]
/// notifies of a change, avoiding 2500 drawRect calls every frame.
///
/// When tile layer data is present, renders tile sprites from the tileset
/// registry alongside the structure grid.
class MapPreviewComponent extends Component {
  MapPreviewComponent({required this.editorState}) {
    editorState.addListener(_invalidateCache);
    _rebuildCache();
  }

  final MapEditorState editorState;

  Picture? _cachedPicture;

  void _invalidateCache() {
    _cachedPicture?.dispose();
    _cachedPicture = null;
  }

  void _rebuildCache() {
    final recorder = PictureRecorder();
    final canvas = Canvas(recorder);
    final paint = Paint();

    // Try to get tileset registry for rendering tile sprites.
    final game = findGame() as TechWorldGame?;
    final registry = game?.tilesetRegistry;

    // Render floor tile layer first (below structure).
    if (registry != null) {
      _renderTileLayer(canvas, editorState.floorLayerData, registry, paint);
    }

    // Render structure grid.
    for (var y = 0; y < gridSize; y++) {
      for (var x = 0; x < gridSize; x++) {
        final tile = editorState.tileAt(x, y);
        // Skip open tiles so the background shows through.
        if (tile == TileType.open) continue;
        paint.color = _colorForTile(tile).withValues(alpha: 0.6);
        canvas.drawRect(
          Rect.fromLTWH(
            x * gridSquareSizeDouble,
            y * gridSquareSizeDouble,
            gridSquareSizeDouble,
            gridSquareSizeDouble,
          ),
          paint,
        );
      }
    }

    // Render object tile layer on top (above structure).
    if (registry != null) {
      _renderTileLayer(canvas, editorState.objectLayerData, registry, paint);
    }

    _cachedPicture = recorder.endRecording();
  }

  void _renderTileLayer(
    Canvas canvas,
    TileLayerData layerData,
    dynamic registry,
    Paint paint,
  ) {
    for (var y = 0; y < gridSize; y++) {
      for (var x = 0; x < gridSize; x++) {
        final ref = layerData.tileAt(x, y);
        if (ref == null) continue;

        final sprite =
            registry.getSpriteForTile(ref.tilesetId, ref.tileIndex);
        if (sprite != null) {
          sprite.render(
            canvas,
            position: Vector2(
              x * gridSquareSizeDouble,
              y * gridSquareSizeDouble,
            ),
            size: Vector2.all(gridSquareSizeDouble),
          );
        } else {
          // Fallback: render a colored rectangle for unknown tile sprites.
          final hue = (ref.tileIndex * 22.5) % 360;
          paint.color = HSLColor.fromAHSL(0.5, hue, 0.6, 0.5).toColor();
          canvas.drawRect(
            Rect.fromLTWH(
              x * gridSquareSizeDouble,
              y * gridSquareSizeDouble,
              gridSquareSizeDouble,
              gridSquareSizeDouble,
            ),
            paint,
          );
        }
      }
    }
  }

  @override
  void render(Canvas canvas) {
    if (_cachedPicture == null) _rebuildCache();
    canvas.drawPicture(_cachedPicture!);
  }

  @override
  void onRemove() {
    editorState.removeListener(_invalidateCache);
    _cachedPicture?.dispose();
    _cachedPicture = null;
    super.onRemove();
  }

  Color _colorForTile(TileType tile) {
    switch (tile) {
      case TileType.open:
        return TileColors.open;
      case TileType.barrier:
        return TileColors.barrier;
      case TileType.spawn:
        return TileColors.spawn;
      case TileType.terminal:
        return TileColors.terminal;
    }
  }
}
