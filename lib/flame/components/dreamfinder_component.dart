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
///
/// See [kDreamfinderWanderRadius] for how far Dreamfinder roams.

/// How far (grid cells, Chebyshev) Dreamfinder wanders from his home cell.
///
/// He drifts around a small area rather than roaming the whole map — a roaming
/// host is distracting during a live demo. `0` pins him in place (a standing
/// host); larger values give a wider patrol. Home is his spawn cell, which is
/// snapped to the nearest walkable tile (see the spawn logic in tech_world.dart)
/// so the patrol never centres on a wall.
const int kDreamfinderWanderRadius = 3;

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
  final Random _random = Random();

  bool _hasNoticedPlayer = false;
  bool _isWandering = false;
  bool _isGreeting = false;
  bool _serverControlled = false;

  /// See [kDreamfinderWanderRadius]. How far DF wanders from [_homeCell] (grid
  /// cells, Chebyshev). 0 = stays put. Mutable so tests can set it.
  int wanderRadius = kDreamfinderWanderRadius;

  /// The cell DF wanders around — captured from his spawn in [onLoad] so the
  /// small patrol orbits wherever he was placed (a walkable cell).
  (int, int)? _homeCell;

  double _wanderCooldown = 0;
  List<MoveEffect> _moveEffects = [];
  List<Direction> _directions = [];
  int _pathSegmentNum = 0;

  static const _initialWanderDelay = 3.0;
  static const _minWorkDuration = 5.0;
  static const _maxWorkDuration = 12.0;
  static const _postGreetingDelay = 4.0;

  static const _walkFrameCount = 4;
  static const _spriteAsset = 'dreamfinder_bot_sheet.png';

  @override
  FutureOr<void> onLoad() {
    anchor = Anchor.centerLeft;
    _buildAnimations();
    // Start in working state — Dreamfinder was here before you arrived.
    current = DreamfinderState.working;
    playing = true;
    // Home is wherever DF spawned (a walkable cell); the small wander orbits it.
    _homeCell = miniGridTuple;
    _wanderCooldown = _initialWanderDelay;
    return super.onLoad();
  }

  @override
  void update(double dt) {
    super.update(dt);
    priority = (position.y.round() ~/ gridSquareSize) * kPriorityStride +
        (position.x.round().abs() % kPriorityStride);

    // Tick the wander cooldown when idle/working and not otherwise occupied.
    if (!_isWandering && !_isGreeting && !_serverControlled &&
        _wanderCooldown > 0) {
      _wanderCooldown -= dt;
      if (_wanderCooldown <= 0) {
        _startWander();
      }
    }
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
  /// Triggers a surprise glance in place, then settles back to the working idle.
  /// DF does not walk over to the player — that would pull him out of his small
  /// wander area — the [playerPosition] argument is kept for API compatibility.
  void noticePlayer(Vector2 playerPosition) {
    if (_hasNoticedPlayer) return;
    _hasNoticedPlayer = true;
    _isWandering = false;
    _isGreeting = true;

    // Interrupt any current movement.
    _removeAllEffects();

    // Play the surprise animation.
    current = DreamfinderState.surprised;
    playing = true;

    // When the surprise glance finishes, settle back in place.
    animationTicker?.onComplete = () {
      animationTicker?.onComplete = null;
      _settleAfterGreeting();
    };
  }

  /// After the surprise glance, return to the working idle in place, then resume
  /// the bounded wander after [_postGreetingDelay]. DF greets without leaving his
  /// small patrol area.
  void _settleAfterGreeting() {
    _isGreeting = false;
    current = DreamfinderState.working;
    playing = true;
    _wanderCooldown = _postGreetingDelay;
  }

  // ---------------------------------------------------------------------------
  // Wandering loop — autonomous exploration
  // ---------------------------------------------------------------------------

  void _startWander() {
    final target = _pickWanderTarget();
    _pathComponent.calculatePath(start: miniGridTuple, end: target);
    final directions = _pathComponent.directions;
    final points = _pathComponent.largeGridPoints;

    if (directions.isEmpty || points.isEmpty) {
      _wanderCooldown = 2.0;
      return;
    }

    _isWandering = true;
    _move(directions, points);
  }

  /// Pick a destination within [wanderRadius] cells of [_homeCell], so DF drifts
  /// around a small area instead of roaming the whole map. Pathfinding skips any
  /// wall cell that lands in range (empty path → [_startWander] just retries).
  (int, int) _pickWanderTarget() {
    final home = _homeCell ?? miniGridTuple;
    if (wanderRadius <= 0) return home;
    final dx = _random.nextInt(wanderRadius * 2 + 1) - wanderRadius;
    final dy = _random.nextInt(wanderRadius * 2 + 1) - wanderRadius;
    return (
      (home.$1 + dx).clamp(0, gridSize - 1),
      (home.$2 + dy).clamp(0, gridSize - 1),
    );
  }

  void _resetWanderCooldown() {
    _wanderCooldown = _minWorkDuration +
        _random.nextDouble() * (_maxWorkDuration - _minWorkDuration);
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
      if (_isWandering) {
        _isWandering = false;
        current = DreamfinderState.working;
        playing = true;
        _resetWanderCooldown();
      } else if (_isGreeting) {
        _isGreeting = false;
        current = DreamfinderState.idle;
        playing = false;
        _wanderCooldown = _postGreetingDelay;
      } else if (_serverControlled) {
        _serverControlled = false;
        current = DreamfinderState.working;
        playing = true;
        _resetWanderCooldown();
      } else {
        current = DreamfinderState.idle;
        playing = false;
      }
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
    _serverControlled = true;
    _isWandering = false;
    _isGreeting = false;
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
