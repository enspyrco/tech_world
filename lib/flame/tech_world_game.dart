import 'package:flame/components.dart';
import 'package:flame/game.dart';

class SnapshotComponent extends PositionComponent with Snapshot {}

/// We extend FlameGame where we set the world component, load texture images
/// and setup the camera.
class TechWorldGame extends FlameGame {
  TechWorldGame({required super.world});

  late final SnapshotComponent root;
  late final SpriteComponent background;
  @override
  Future<void> onLoad() async {
    await images.loadAll([
      'NPC11.png',
      'NPC12.png',
      'NPC13.png',
      'single_room.png',
    ]);

    // Add a snapshot component.
    root = SnapshotComponent();
    add(root);

    // Add some children.
    final backgroundSprite = Sprite(await images.load('single_room.png'));
    background = SpriteComponent(sprite: backgroundSprite);
    root.add(background);

    camera.viewfinder.anchor = Anchor.topLeft;
  }
}
