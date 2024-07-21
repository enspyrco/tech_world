import 'dart:async';
import 'dart:math';

import 'package:flame/components.dart';
import 'package:flame/effects.dart';
import 'package:tech_world/flame/shared/constants.dart';
import 'package:tech_world/flame/shared/direction.dart';
import 'package:tech_world/flame/tech_world_game.dart';
import 'package:tech_world_networking_types/tech_world_networking_types.dart';

/// The [PlayerComponent] uses the path points to calculate a list of
/// [Direction]s that are used to create a list of [MoveEffect]s
///
/// The [PlayerComponent] contains the position of the player and draws
/// the sprite animation. A list of [Direction]s for each path segment is used
/// provide the appropriate movement by adding the corresponding [MoveEffect]s
/// at the same time as changing the animation to the relevant walking direction.
///
/// The anchor point draws the 32x64 sprite in the appropriate place that
/// corresponds to the grid point that matches the position of the component.
class PlayerComponent extends SpriteAnimationGroupComponent<Direction>
    with KeyboardHandler, HasGameReference<TechWorldGame>
    implements User {
  PlayerComponent({
    required super.position,
    required this.id,
    required this.displayName,
  });

  PlayerComponent.from(User user)
      : id = user.id,
        displayName = user.displayName {
    super.position = Vector2.zero();
  }

  @override
  String id;
  @override
  String displayName;
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

  // We round the player position before calculating the miniGrid position,
  // as position values are doubles and do not necessarily hold exact values.
  Point<int> get miniGridPosition => Point(
        position.x.round() ~/ gridSquareSize,
        position.y.round() ~/ gridSquareSize,
      );

  /// Create a list of [MoveEffect]s that each add the next [MoveEffect]
  /// when the previous has finished.
  void move(List<Direction> directions, List<Vector2> largeGridPoints) {
    _pathSegmentNum = 0;
    _moveEffects = [];
    _directions = directions;
    for (final largeGridPoint in largeGridPoints) {
      _moveEffects.add(
        MoveToEffect(
          largeGridPoint,
          EffectController(duration: 0.2),
          onComplete: () {
            playing = false;
            _addNextMoveEffect();
          },
        ),
      );
    }
    _addNextMoveEffect();
  }

  /// Set the [Direction] and add the [MoveEffect] for each path segment.
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
