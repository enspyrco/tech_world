import 'dart:async';
import 'dart:math';

import 'package:flame/components.dart';
import 'package:flame/effects.dart';
import 'package:tech_world/auth/auth_user.dart';
import 'package:tech_world/flame/components/path_component.dart';
import 'package:tech_world/flame/shared/constants.dart';
import 'package:tech_world/flame/shared/direction.dart';
import 'package:tech_world/flame/shared/dreamfinder_state.dart';
import 'package:tech_world/flame/tech_world_game.dart';

/// Dreamfinder's in-world character component.
///
/// Unlike regular [PlayerComponent]s, Dreamfinder has a richer state machine
/// with idle behavior ("working"), surprise reactions, and autonomous movement.
///
/// The sprite sheet (`dreamfinder_bot_sheet.png`, 512×192) has three rows:
///   Row 0 (y=0):   Walk cycle — 4 directions × 4 frames
///   Row 1 (y=64):  Working idle — 4 frames, looping
///   Row 2 (y=128): Surprise — 4 frames, one-shot
class DreamfinderComponent
    extends SpriteAnimationGroupComponent<DreamfinderState>
    with HasGameReference<TechWorldGame>
    implements User {
  DreamfinderComponent({
    required super.position,
    required this.id,
    required this.displayName,
    required PathComponent pathComponent,
  }) : _pathComponent = pathComponent;

  @override
  String id;

  @override
  String displayName;

  final PathComponent _pathComponent;

  bool _hasNoticedPlayer = false;
  List<MoveEffect> _moveEffects = [];
  List<Direction> _directions = [];
  int _pathSegmentNum = 0;

  static const _walkFrameCount = 4;
  static const _spriteAsset = 'dreamfinder_bot_sheet.png';

  @override
  FutureOr<void> onLoad() {
    anchor = Anchor.centerLeft;
    _buildAnimations();
    // Start in working state — Dreamfinder was here before you arrived.
    current = DreamfinderState.working;
    playing = true;
    return super.onLoad();
  }

  @override
  void update(double dt) {
    super.update(dt);
    priority = position.y.round() ~/ gridSquareSize;
  }

  /// Grid position as a tuple for pathfinding.
  (int, int) get miniGridTuple => (
        position.x.round() ~/ gridSquareSize,
        position.y.round() ~/ gridSquareSize,
      );

  Point<int> get miniGridPosition => Point(
        position.x.round() ~/ gridSquareSize,
        position.y.round() ~/ gridSquareSize,
      );

  // ---------------------------------------------------------------------------
  // Animation setup
  // ---------------------------------------------------------------------------

  void _buildAnimations() {
    final image = game.images.fromCache(_spriteAsset);
    const sectionWidth = _walkFrameCount * 32.0;

    // Row 0: Walk directions (y=0).
    SpriteAnimation walkAnim(double xOffset) =>
        SpriteAnimation.fromFrameData(
          image,
          SpriteAnimationData.sequenced(
            amount: _walkFrameCount,
            textureSize: Vector2(32, 64),
            stepTime: 0.12,
            texturePosition: Vector2(xOffset, 0),
          ),
        );

    final walkDown = walkAnim(0);
    final walkLeft = walkAnim(sectionWidth);
    final walkUp = walkAnim(sectionWidth * 2);
    final walkRight = walkAnim(sectionWidth * 3);

    // Row 1: Working idle (y=64), looping.
    final workingAnim = SpriteAnimation.fromFrameData(
      image,
      SpriteAnimationData.sequenced(
        amount: 4,
        textureSize: Vector2(32, 64),
        stepTime: 0.3,
        texturePosition: Vector2(0, 64),
      ),
    );

    // Row 2: Surprise (y=128), one-shot.
    final surpriseAnim = SpriteAnimation.fromFrameData(
      image,
      SpriteAnimationData.sequenced(
        amount: 4,
        textureSize: Vector2(32, 64),
        stepTime: 0.25,
        texturePosition: Vector2(0, 128),
        loop: false,
      ),
    );

    // Idle = single frame from walk down (frame 0).
    final idleAnim = SpriteAnimation.fromFrameData(
      image,
      SpriteAnimationData.sequenced(
        amount: 1,
        textureSize: Vector2(32, 64),
        stepTime: 1,
      ),
    );

    animations = {
      DreamfinderState.working: workingAnim,
      DreamfinderState.surprised: surpriseAnim,
      DreamfinderState.idle: idleAnim,
      DreamfinderState.walkDown: walkDown,
      DreamfinderState.walkLeft: walkLeft,
      DreamfinderState.walkUp: walkUp,
      DreamfinderState.walkRight: walkRight,
      DreamfinderState.walkUpLeft: walkLeft,
      DreamfinderState.walkUpRight: walkRight,
      DreamfinderState.walkDownLeft: walkLeft,
      DreamfinderState.walkDownRight: walkRight,
    };
  }

  // ---------------------------------------------------------------------------
  // Host behavior: "was busy, notices you"
  // ---------------------------------------------------------------------------

  /// Called when a human player joins the room.
  ///
  /// Triggers the surprise → walk-to-player sequence.
  void noticePlayer(Vector2 playerPosition) {
    if (_hasNoticedPlayer) return;
    _hasNoticedPlayer = true;

    // Interrupt any current movement.
    _removeAllEffects();

    // Play the surprise animation.
    current = DreamfinderState.surprised;
    playing = true;

    // When surprise finishes, walk toward the player.
    animationTicker?.onComplete = () {
      animationTicker?.onComplete = null;
      _walkToPlayer(playerPosition);
    };
  }

  void _walkToPlayer(Vector2 targetPosition) {
    final targetGrid = (
      (targetPosition.x / gridSquareSizeDouble).round().clamp(0, gridSize - 1),
      (targetPosition.y / gridSquareSizeDouble).round().clamp(0, gridSize - 1),
    );

    // Stop 2 cells away from the player so we don't overlap.
    final myGrid = miniGridTuple;
    final dx = targetGrid.$1 - myGrid.$1;
    final dy = targetGrid.$2 - myGrid.$2;
    final approachTarget = (
      (targetGrid.$1 - dx.sign * 2).clamp(0, gridSize - 1),
      (targetGrid.$2 - dy.sign * 2).clamp(0, gridSize - 1),
    );

    _pathComponent.calculatePath(start: myGrid, end: approachTarget);
    final directions = _pathComponent.directions;
    final points = _pathComponent.largeGridPoints;

    if (directions.isEmpty || points.isEmpty) {
      // No path found — just stand idle facing down.
      current = DreamfinderState.idle;
      playing = false;
      return;
    }

    _move(directions, points);
  }

  // ---------------------------------------------------------------------------
  // Movement (adapted from PlayerComponent)
  // ---------------------------------------------------------------------------

  /// Move along a path with directional animations.
  void _move(List<Direction> directions, List<Vector2> largeGridPoints) {
    _removeAllEffects();
    _pathSegmentNum = 0;
    _moveEffects = [];
    _directions = directions;

    if (directions.isEmpty && largeGridPoints.isNotEmpty) {
      position = largeGridPoints.first;
      return;
    }

    for (int i = 1; i < largeGridPoints.length; i++) {
      _moveEffects.add(
        MoveToEffect(
          largeGridPoints[i],
          EffectController(duration: 0.2),
          onComplete: () {
            playing = false;
            animationTicker?.reset();
            _addNextMoveEffect();
          },
        ),
      );
    }
    _addNextMoveEffect();
  }

  void _addNextMoveEffect() {
    if (_directions.isEmpty || _pathSegmentNum == _directions.length) {
      // Path complete — stand idle.
      current = DreamfinderState.idle;
      playing = false;
      return;
    }
    final direction = _directions[_pathSegmentNum];
    if (direction == Direction.none) {
      _pathSegmentNum++;
      _addNextMoveEffect();
      return;
    }
    if (animations == null) return;
    current = walkStateFromDirection(direction);
    playing = true;
    add(_moveEffects[_pathSegmentNum]);
    _pathSegmentNum++;
  }

  /// Handle position data sent by the bot server via LiveKit.
  ///
  /// This overrides any autonomous client-side movement.
  void moveFromServer(List<Direction> directions, List<Vector2> largeGridPoints) {
    // Cancel autonomous behavior.
    _hasNoticedPlayer = true;
    animationTicker?.onComplete = null;
    _move(directions, largeGridPoints);
  }

  void _removeAllEffects() {
    final effects = children.whereType<Effect>().toList();
    for (final effect in effects) {
      effect.removeFromParent();
    }
  }
}
