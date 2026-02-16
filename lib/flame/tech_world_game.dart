import 'package:flame/components.dart';
import 'package:flame/game.dart';

class SnapshotComponent extends PositionComponent with Snapshot {}

/// We extend FlameGame where we set the world component, load texture images
/// and setup the camera.
class TechWorldGame extends FlameGame {
  TechWorldGame({required super.world});

  late final SnapshotComponent root;

  @override
  Future<void> onLoad() async {
    await images.loadAll([
      'NPC11.png',
      'NPC12.png',
      'NPC13.png',
      'single_room.png',
      'claude_bot.png',
    ]);

    // Add a snapshot component.
    root = SnapshotComponent();
    add(root);

    camera.viewfinder.anchor = Anchor.center;
  }
}
