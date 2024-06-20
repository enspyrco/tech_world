import 'package:flame/components.dart';
import 'package:flame/game.dart';
import 'package:flame/input.dart';
import 'package:tech_world/flame/player.dart';

class TechWorldGame extends FlameGame with HasKeyboardHandlerComponents {
  TechWorldGame();

  late PlayerComponent _player;

  @override
  Future<void> onLoad() async {
    await images.loadAll([
      'NPC11.png',
      'NPC12.png',
      'NPC13.png',
    ]);

    camera.viewfinder.anchor = Anchor.topLeft;

    _player = PlayerComponent(position: Vector2(100, size.y - 50));

    world.add(_player);
  }
}
