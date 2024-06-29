import 'dart:async';
import 'dart:math';

import 'package:flame/components.dart';
import 'package:flame/effects.dart';
import 'package:tech_world/flame/shared/constants.dart';
import 'package:tech_world/flame/shared/direction.dart';
import 'package:tech_world/flame/tech_world_game.dart';

class PlayerComponent extends SpriteAnimationGroupComponent<Direction>
    with KeyboardHandler, HasGameReference<TechWorldGame> {
  PlayerComponent({required super.position});

  List<MoveEffect> _moveEffects = [];
  List<Direction> _directions = [];
  int _pathSegmentNum = 0;

  @override
  FutureOr<void> onLoad() {
    current = Direction.down;
    anchor = Anchor.centerLeft;

    final upAnimation = SpriteAnimation.fromFrameData(
      game.images.fromCache('NPC11.png'),
      SpriteAnimationData.sequenced(
        amount: 3,
        textureSize: Vector2(32, 64),
        stepTime: 0.12,
        texturePosition: Vector2(192, 0),
      ),
    );

    final downAnimation = SpriteAnimation.fromFrameData(
      game.images.fromCache('NPC11.png'),
      SpriteAnimationData.sequenced(
        amount: 3,
        textureSize: Vector2(32, 64),
        stepTime: 0.12,
      ),
    );

    final leftAnimation = SpriteAnimation.fromFrameData(
      game.images.fromCache('NPC11.png'),
      SpriteAnimationData.sequenced(
        amount: 3,
        textureSize: Vector2(32, 64),
        stepTime: 0.12,
        texturePosition: Vector2(96, 0),
      ),
    );

    final rightAnimation = SpriteAnimation.fromFrameData(
      game.images.fromCache('NPC11.png'),
      SpriteAnimationData.sequenced(
        amount: 3,
        textureSize: Vector2(32, 64),
        stepTime: 0.12,
        texturePosition: Vector2(288, 0),
      ),
    );

    animations = {
      Direction.up: upAnimation,
      Direction.upLeft: leftAnimation,
      Direction.upRight: rightAnimation,
      Direction.down: downAnimation,
      Direction.downLeft: leftAnimation,
      Direction.downRight: rightAnimation,
      Direction.left: leftAnimation,
      Direction.right: rightAnimation,
    };
    return super.onLoad();
  }

  // We add 1 because position is
  Point<int> get miniGridPosition => Point(
        position.x.round() ~/ gridSquareSize,
        position.y.round() ~/ gridSquareSize,
      );

  void move(List<Direction> directions) {
    _pathSegmentNum = 0;
    _moveEffects = [];
    _directions = directions;
    for (final direction in directions) {
      _moveEffects.add(
        MoveByEffect(
          Vector2(direction.offsetX, direction.offsetY),
          EffectController(duration: 0.2),
          onComplete: () {
            print('position at end = ${position}');
            playing = false;
            _addNextMoveEffect();
          },
        ),
      );
    }
    _addNextMoveEffect();
  }

  void _addNextMoveEffect() {
    if (_directions.isEmpty || _pathSegmentNum == _directions.length) {
      return;
    }
    current = _directions[_pathSegmentNum];
    playing = true;
    add(_moveEffects[_pathSegmentNum]);
    _pathSegmentNum++;
  }
}
