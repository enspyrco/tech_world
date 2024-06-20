import 'package:flame/components.dart';
import 'package:flutter/services.dart';
import 'package:tech_world/flame/tech_world_game.dart';

enum Direction { up, down, left, right }

class PlayerComponent extends PositionComponent
    with KeyboardHandler, HasGameReference<TechWorldGame> {
  PlayerComponent({required super.position})
      : animation = {
          Direction.up: _PlayerUpAnimation(position: position),
          Direction.down: _PlayerDownAnimation(position: position),
          Direction.left: _PlayerLeftAnimation(position: position),
          Direction.right: _PlayerRightAnimation(position: position),
        };

  SpriteAnimationComponent? currentAnimation;
  final Map<Direction, SpriteAnimationComponent> animation;

  void startMoving(Direction direction) {
    if (currentAnimation != null) game.remove(currentAnimation!);
    currentAnimation = animation[direction];
    game.add(currentAnimation!);
  }

  @override
  bool onKeyEvent(KeyEvent event, Set<LogicalKeyboardKey> keysPressed) {
    if (keysPressed.contains(LogicalKeyboardKey.arrowLeft)) {
      startMoving(Direction.left);
    } else if (keysPressed.contains(LogicalKeyboardKey.arrowRight)) {
      startMoving(Direction.right);
    } else if (keysPressed.contains(LogicalKeyboardKey.arrowUp)) {
      startMoving(Direction.up);
    } else if (keysPressed.contains(LogicalKeyboardKey.arrowDown)) {
      startMoving(Direction.down);
    }
    return true;
  }
}

class _PlayerDownAnimation extends SpriteAnimationComponent
    with HasGameReference<TechWorldGame> {
  _PlayerDownAnimation({
    required super.position,
  }) : super(size: Vector2(32, 64), anchor: Anchor.center);

  @override
  void onLoad() {
    animation = SpriteAnimation.fromFrameData(
      game.images.fromCache('NPC11.png'),
      SpriteAnimationData.sequenced(
        amount: 3,
        textureSize: Vector2(32, 64),
        stepTime: 0.12,
      ),
    );
  }
}

class _PlayerLeftAnimation extends SpriteAnimationComponent
    with HasGameReference<TechWorldGame> {
  _PlayerLeftAnimation({
    required super.position,
  }) : super(size: Vector2(32, 64), anchor: Anchor.center);

  @override
  void onLoad() {
    animation = SpriteAnimation.fromFrameData(
      game.images.fromCache('NPC11.png'),
      SpriteAnimationData.sequenced(
        amount: 3,
        textureSize: Vector2(32, 64),
        stepTime: 0.12,
        texturePosition: Vector2(96, 0),
      ),
    );
  }
}

class _PlayerUpAnimation extends SpriteAnimationComponent
    with HasGameReference<TechWorldGame> {
  _PlayerUpAnimation({
    required super.position,
  }) : super(size: Vector2(32, 64), anchor: Anchor.center);

  @override
  void onLoad() {
    animation = SpriteAnimation.fromFrameData(
      game.images.fromCache('NPC11.png'),
      SpriteAnimationData.sequenced(
        amount: 3,
        textureSize: Vector2(32, 64),
        stepTime: 0.12,
        texturePosition: Vector2(192, 0),
      ),
    );
  }
}

class _PlayerRightAnimation extends SpriteAnimationComponent
    with HasGameReference<TechWorldGame> {
  _PlayerRightAnimation({
    required super.position,
  }) : super(size: Vector2(32, 64), anchor: Anchor.center);

  @override
  void onLoad() {
    animation = SpriteAnimation.fromFrameData(
      game.images.fromCache('NPC11.png'),
      SpriteAnimationData.sequenced(
        amount: 3,
        textureSize: Vector2(32, 64),
        stepTime: 0.12,
        texturePosition: Vector2(288, 0),
      ),
    );
  }
}
