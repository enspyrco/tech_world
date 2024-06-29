import 'package:flame/components.dart';
import 'package:flame/game.dart';

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
