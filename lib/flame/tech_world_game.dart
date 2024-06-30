import 'package:flame/components.dart';
import 'package:flame/game.dart';

/// We extend FlameGame where we set the world component, load texture images
/// and setup the camera.
class TechWorldGame extends FlameGame {
  TechWorldGame({required super.world});

  @override
  Future<void> onLoad() async {
    await images.loadAll([
      'NPC11.png',
      'NPC12.png',
      'NPC13.png',
    ]);

    camera.viewfinder.anchor = Anchor.topLeft;
  }
}
