import 'package:flame/components.dart';
import 'package:flame/game.dart';
import 'package:tech_world/flame/tiles/predefined_tilesets.dart';
import 'package:tech_world/flame/tiles/tileset_registry.dart';

class SnapshotComponent extends PositionComponent with Snapshot {}

/// We extend FlameGame where we set the world component, load texture images
/// and setup the camera.
class TechWorldGame extends FlameGame {
  TechWorldGame({required super.world});

  late final SnapshotComponent root;

  /// Registry for loading and accessing tileset sprite sheets.
  late final TilesetRegistry tilesetRegistry;

  @override
  Future<void> onLoad() async {
    await images.loadAll([
      'NPC11.png',
      'NPC12.png',
      'NPC13.png',
      'single_room.png',
      'claude_bot.png',
    ]);

    // Initialize tileset registry and load all predefined tilesets.
    tilesetRegistry = TilesetRegistry(images: images);
    await tilesetRegistry.loadAll(allTilesets);

    // Add a snapshot component.
    root = SnapshotComponent();
    add(root);

    camera.viewfinder.anchor = Anchor.center;
  }
}
