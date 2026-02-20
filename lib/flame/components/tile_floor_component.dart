import 'dart:ui';

import 'package:flame/components.dart';
import 'package:tech_world/flame/shared/constants.dart';
import 'package:tech_world/flame/tiles/tile_layer_data.dart';
import 'package:tech_world/flame/tiles/tileset_registry.dart';

/// Renders the floor tile layer as a cached [Picture] for efficient drawing.
///
/// All floor tiles are recorded once into a [Picture] and replayed each frame,
/// avoiding per-tile draw calls. This follows the same caching pattern as
/// [MapPreviewComponent].
///
/// Priority is -2, placing it below the background image layer (-1) and all
/// game objects.
class TileFloorComponent extends Component {
  TileFloorComponent({
    required this.layerData,
    required this.registry,
  }) : super(priority: -2);

  final TileLayerData layerData;
  final TilesetRegistry registry;

  Picture? _cachedPicture;

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
  void render(Canvas canvas) {
    if (_cachedPicture != null) {
      canvas.drawPicture(_cachedPicture!);
    }
  }

  @override
  void onRemove() {
    _cachedPicture?.dispose();
    _cachedPicture = null;
    super.onRemove();
  }
}
