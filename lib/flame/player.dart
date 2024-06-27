import 'dart:async';

import 'package:flame/components.dart';
import 'package:flame/effects.dart';
import 'package:flutter/services.dart';
import 'package:tech_world/flame/tech_world_game.dart';

enum Direction { up, down, left, right }

class PlayerComponent extends SpriteAnimationGroupComponent<Direction>
    with KeyboardHandler, HasGameReference<TechWorldGame> {
  @override
  FutureOr<void> onLoad() {
    animations = {
      Direction.up: SpriteAnimation.fromFrameData(
        game.images.fromCache('NPC11.png'),
        SpriteAnimationData.sequenced(
          amount: 3,
          textureSize: Vector2(32, 64),
          stepTime: 0.12,
          texturePosition: Vector2(192, 0),
        ),
      ),
      Direction.down: SpriteAnimation.fromFrameData(
        game.images.fromCache('NPC11.png'),
        SpriteAnimationData.sequenced(
          amount: 3,
          textureSize: Vector2(32, 64),
          stepTime: 0.12,
        ),
      ),
      Direction.left: SpriteAnimation.fromFrameData(
        game.images.fromCache('NPC11.png'),
        SpriteAnimationData.sequenced(
          amount: 3,
          textureSize: Vector2(32, 64),
          stepTime: 0.12,
          texturePosition: Vector2(96, 0),
        ),
      ),
      Direction.right: SpriteAnimation.fromFrameData(
        game.images.fromCache('NPC11.png'),
        SpriteAnimationData.sequenced(
          amount: 3,
          textureSize: Vector2(32, 64),
          stepTime: 0.12,
          texturePosition: Vector2(288, 0),
        ),
      ),
    };
    return super.onLoad();
  }

  PlayerComponent({required super.position}) {
    current = Direction.up;
  }

  @override
  bool onKeyEvent(KeyEvent event, Set<LogicalKeyboardKey> keysPressed) {
    if (keysPressed.contains(LogicalKeyboardKey.arrowLeft)) {
      current = Direction.left;
      add(MoveByEffect(Vector2(-64, 0), EffectController(duration: 0.5)));
    } else if (keysPressed.contains(LogicalKeyboardKey.arrowRight)) {
      current = Direction.right;
      add(MoveByEffect(Vector2(64, 0), EffectController(duration: 0.5)));
    } else if (keysPressed.contains(LogicalKeyboardKey.arrowUp)) {
      current = Direction.up;
      add(MoveByEffect(Vector2(0, -64), EffectController(duration: 0.5)));
    } else if (keysPressed.contains(LogicalKeyboardKey.arrowDown)) {
      current = Direction.down;
      add(MoveByEffect(Vector2(0, 64), EffectController(duration: 0.5)));
    }
    return true;
  }
}

// class _PlayerDownAnimation extends SpriteAnimationComponent
//     with HasGameReference<TechWorldGame> {
//   _PlayerDownAnimation({
//     required super.position,
//   }) : super(size: Vector2(32, 64), anchor: Anchor.center);

//   @override
//   void onLoad() {
//     animation = SpriteAnimation.fromFrameData(
//       game.images.fromCache('NPC11.png'),
//       SpriteAnimationData.sequenced(
//         amount: 3,
//         textureSize: Vector2(32, 64),
//         stepTime: 0.12,
//       ),
//     );
//   }
// }

// class _PlayerLeftAnimation extends SpriteAnimationComponent
//     with HasGameReference<TechWorldGame> {
//   _PlayerLeftAnimation({
//     required super.position,
//   }) : super(size: Vector2(32, 64), anchor: Anchor.center);

//   @override
//   void onLoad() {
//     animation = SpriteAnimation.fromFrameData(
//       game.images.fromCache('NPC11.png'),
//       SpriteAnimationData.sequenced(
//         amount: 3,
//         textureSize: Vector2(32, 64),
//         stepTime: 0.12,
//         texturePosition: Vector2(96, 0),
//       ),
//     );
//   }
// }

// class _PlayerUpAnimation extends SpriteAnimationComponent
//     with HasGameReference<TechWorldGame> {
//   _PlayerUpAnimation({
//     required super.position,
//   }) : super(size: Vector2(32, 64), anchor: Anchor.center);

//   @override
//   void onLoad() {
//     animation = SpriteAnimation.fromFrameData(
//       game.images.fromCache('NPC11.png'),
//       SpriteAnimationData.sequenced(
//         amount: 3,
//         textureSize: Vector2(32, 64),
//         stepTime: 0.12,
//         texturePosition: Vector2(192, 0),
//       ),
//     );
//   }
// }

// class _PlayerRightAnimation extends SpriteAnimationComponent
//     with HasGameReference<TechWorldGame> {
//   _PlayerRightAnimation({
//     required super.position,
//   }) : super(size: Vector2(32, 64), anchor: Anchor.center);

//   @override
//   void onLoad() {
//     animation = SpriteAnimation.fromFrameData(
//       game.images.fromCache('NPC11.png'),
//       SpriteAnimationData.sequenced(
//         amount: 3,
//         textureSize: Vector2(32, 64),
//         stepTime: 0.12,
//         texturePosition: Vector2(288, 0),
//       ),
//     );
//   }
// }
