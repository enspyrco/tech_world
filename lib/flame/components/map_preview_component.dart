import 'dart:ui';

import 'package:flame/components.dart';
import 'package:tech_world/flame/shared/constants.dart';
import 'package:tech_world/map_editor/map_editor_state.dart';
import 'package:tech_world/map_editor/tile_colors.dart';

/// Flame component that renders the map editor's grid state as colored tiles
/// in the game canvas.
///
/// Caches the grid as a [Picture] and only re-records when [MapEditorState]
/// notifies of a change, avoiding 2500 drawRect calls every frame.
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

    for (var y = 0; y < gridSize; y++) {
      for (var x = 0; x < gridSize; x++) {
        final tile = editorState.tileAt(x, y);
        paint.color = _colorForTile(tile);
        canvas.drawRect(
          Rect.fromCenter(
            center: Offset(
              x * gridSquareSizeDouble,
              y * gridSquareSizeDouble,
            ),
            width: gridSquareSizeDouble,
            height: gridSquareSizeDouble,
          ),
          paint,
        );
      }
    }

    _cachedPicture = recorder.endRecording();
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
