import 'dart:ui';

import 'package:flame/components.dart';
import 'package:tech_world/flame/shared/constants.dart';
import 'package:tech_world/map_editor/map_editor_state.dart';
import 'package:tech_world/map_editor/tile_colors.dart';

/// Flame component that renders the map editor's grid state as colored tiles
/// in the game canvas.
///
/// Iterates the [MapEditorState] grid each frame and draws colored rectangles
/// using the same coordinate system as [BarriersComponent].
class MapPreviewComponent extends Component {
  MapPreviewComponent({required this.editorState});

  final MapEditorState editorState;

  final Paint _paint = Paint();

  @override
  void render(Canvas canvas) {
    for (var y = 0; y < gridSize; y++) {
      for (var x = 0; x < gridSize; x++) {
        final tile = editorState.tileAt(x, y);
        _paint.color = _colorForTile(tile);
        canvas.drawRect(
          Rect.fromCenter(
            center: Offset(
              x * gridSquareSizeDouble,
              y * gridSquareSizeDouble,
            ),
            width: gridSquareSizeDouble,
            height: gridSquareSizeDouble,
          ),
          _paint,
        );
      }
    }
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
