import 'dart:async';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:flame/components.dart';
import 'package:flame/effects.dart';
import 'package:flutter/foundation.dart';
import 'package:tech_world/avatar/avatar_spec.dart';
import 'package:tech_world/avatar/parts/avatar_part.dart';
import 'package:tech_world/flame/shared/constants.dart';
import 'package:tech_world/flame/shared/direction.dart';
import 'package:tech_world/flame/shared/player_anim_state.dart';
import 'package:tech_world/flame/tech_world_game.dart';
import 'package:tech_world/auth/auth_user.dart';

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
class PlayerComponent extends SpriteAnimationGroupComponent<PlayerAnimState>
    with KeyboardHandler, HasGameReference<TechWorldGame>
    implements User {
  PlayerComponent({
    required super.position,
    required this.id,
    required this.displayName,
    String spriteAsset = 'NPC11.png',
    int frameCount = 3,
  })  : _spriteAsset = spriteAsset,
        _frameCount = frameCount;

  PlayerComponent.from(
    User user, {
    String spriteAsset = 'NPC11.png',
    int frameCount = 3,
  })  : id = user.id,
        displayName = user.displayName,
        _spriteAsset = spriteAsset,
        _frameCount = frameCount {
    super.position = Vector2.zero();
  }

  @override
  String id;
  @override
  String displayName;

  String _spriteAsset;
  final int _frameCount;

  /// Frames in the wave strip (sprite cells 12–15).
  static const int kWaveFrameCount = 4;

  /// The walk state to restore when a one-shot emote finishes. Updated on every
  /// path segment so the wave returns you to the way you were actually facing.
  PlayerAnimState _facing = PlayerAnimState.walkDown;

  /// The sprite sheet asset used for this player's animations.
  String get spriteAsset => _spriteAsset;

  /// Update the sprite asset and rebuild animations.
  ///
  /// Only takes effect after [onLoad] has run (i.e. when [isMounted] is true).
  set spriteAsset(String value) {
    if (value == _spriteAsset) return;
    _spriteAsset = value;
    if (isMounted) {
      _buildAnimations();
    }
  }

  /// The composed sheet this component currently holds a reference on, or null
  /// when it is rendering straight from a cached asset.
  ///
  /// Paired with [AvatarComposer.release] in [_buildAnimations] and [onRemove]
  /// — the composer shares one image between every peer wearing the same
  /// parts, so dropping the reference is what eventually frees it.
  AvatarSpec? _heldSpec;

  /// Explicitly-set appearance, when this component is a player.
  ///
  /// Takes precedence over [_spriteAsset]. Null means "no spec was set" — a
  /// bot, or a player still identified by sprite filename — and the asset
  /// lookup below decides what to do.
  AvatarSpec? _avatarSpec;

  /// The character this component renders, or null if it isn't a composable
  /// character at all.
  ///
  /// Set this rather than [spriteAsset] for players. Bots are why the fallback
  /// exists: `claude_bot.png` is 104x88 and `dreamfinder_bot_sheet.png` is
  /// 512x192, so routing every sheet through the composer would trip its
  /// 512x64 contract on components that were never characters.
  AvatarSpec? get avatarSpec => _avatarSpec ?? _specForCurrentAsset;

  set avatarSpec(AvatarSpec? value) {
    if (value == avatarSpec) return;
    _avatarSpec = value;
    if (value != null) {
      // Keep the legacy field consistent for any reader still asking, so the
      // two can't describe different characters during the migration.
      _spriteAsset = value.parts.body.asset;
    }
    if (isMounted) _buildAnimations();
  }

  /// Bridge from the legacy string API: is this sheet a composable character?
  /// Retired with [spriteAsset] once every caller passes a spec.
  AvatarSpec? get _specForCurrentAsset {
    final body = BodyId.forAsset(_spriteAsset);
    return body == null ? null : AvatarSpec.preset(CompositeAvatar(body: body));
  }

  /// Duration of a single one-cell [MoveToEffect].
  ///
  /// This animation duration *is* the continuous-keyboard-movement cadence:
  /// [TechWorldGame] issues the next held-key step only once the previous cell
  /// move has finished (gated on [isMoving]), so a held key walks at exactly one
  /// cell per [cellMoveDuration] with no separate repeat timer.
  static const double cellMoveDuration = 0.2;

  List<MoveEffect> _moveEffects = [];
  List<Direction> _directions = [];
  int _pathSegmentNum = 0;

  @override
  FutureOr<void> onLoad() {
    anchor = Anchor.centerLeft;
    _buildAnimations();
    return super.onLoad();
  }

  @override
  void onRemove() {
    _releaseSheet();
    super.onRemove();
  }

  /// Get the sheet to animate from, taking a composer reference when this
  /// avatar is composable.
  ///
  /// Swapping avatars releases the outgoing reference before taking the new
  /// one, so a player cycling through the picker never accumulates holds on
  /// sheets they are no longer wearing.
  ui.Image _acquireSheet() {
    _releaseSheet();
    final spec = avatarSpec;
    if (spec == null) return game.images.fromCache(_spriteAsset);
    _heldSpec = spec;
    return game.avatarComposer.acquire(spec);
  }

  void _releaseSheet() {
    final held = _heldSpec;
    if (held == null) return;
    _heldSpec = null;
    game.avatarComposer.release(held);
  }

  /// Build directional animations from the current [_spriteAsset].
  void _buildAnimations() {
    final image = _acquireSheet();

    final sectionWidth = _frameCount * 32.0;
    // The wave strip sits immediately after the four direction strips.
    // Player sheets are 512 wide = 16 cells: 12 walk (4 strips x 3) + 4 wave.
    final waveStart = sectionWidth * 4;
    final hasWaveStrip = image.width >= waveStart + kWaveFrameCount * 32;

    final downAnimation = SpriteAnimation.fromFrameData(
      image,
      SpriteAnimationData.sequenced(
        amount: _frameCount,
        textureSize: Vector2(32, 64),
        stepTime: 0.12,
      ),
    );

    final leftAnimation = SpriteAnimation.fromFrameData(
      image,
      SpriteAnimationData.sequenced(
        amount: _frameCount,
        textureSize: Vector2(32, 64),
        stepTime: 0.12,
        texturePosition: Vector2(sectionWidth, 0),
      ),
    );

    final upAnimation = SpriteAnimation.fromFrameData(
      image,
      SpriteAnimationData.sequenced(
        amount: _frameCount,
        textureSize: Vector2(32, 64),
        stepTime: 0.12,
        texturePosition: Vector2(sectionWidth * 2, 0),
      ),
    );

    final rightAnimation = SpriteAnimation.fromFrameData(
      image,
      SpriteAnimationData.sequenced(
        amount: _frameCount,
        textureSize: Vector2(32, 64),
        stepTime: 0.12,
        texturePosition: Vector2(sectionWidth * 3, 0),
      ),
    );

    animations = {
      PlayerAnimState.walkUp: upAnimation,
      PlayerAnimState.walkUpLeft: leftAnimation,
      PlayerAnimState.walkUpRight: rightAnimation,
      PlayerAnimState.walkDown: downAnimation,
      PlayerAnimState.walkDownLeft: leftAnimation,
      PlayerAnimState.walkDownRight: rightAnimation,
      PlayerAnimState.walkLeft: leftAnimation,
      PlayerAnimState.walkRight: rightAnimation,
      if (hasWaveStrip)
        PlayerAnimState.wave: SpriteAnimation.fromFrameData(
          image,
          SpriteAnimationData.sequenced(
            amount: kWaveFrameCount,
            textureSize: Vector2(32, 64),
            stepTime: 0.15,
            texturePosition: Vector2(waveStart, 0),
            loop: false, // one-shot; [wave] restores the facing on complete
          ),
        ),
    };
    current = PlayerAnimState.walkDown; // Set after animations is initialized
  }

  /// Play the one-shot wave emote, then return to the current facing.
  ///
  /// No-op if the sheet carries no wave strip, if animations aren't built yet,
  /// or if a wave is already playing (so mashing the key can't restart it into
  /// a stutter). Movement interrupts it naturally: [_addNextMoveEffect] sets
  /// [current] to a walk state on the next path segment.
  void wave() {
    final anims = animations;
    if (anims == null || !anims.containsKey(PlayerAnimState.wave)) return;
    if (current == PlayerAnimState.wave) return;

    current = PlayerAnimState.wave;
    playing = true;
    final ticker = animationTicker;
    ticker?.reset();
    ticker?.onComplete = () {
      // Only restore if a move hasn't already taken over the animation.
      if (current == PlayerAnimState.wave) {
        current = _facing;
        playing = false;
      }
    };
  }

  /// Whether the wave emote is currently playing. Test seam.
  @visibleForTesting
  bool get isWaving => current == PlayerAnimState.wave;

  @override
  void update(double dt) {
    super.update(dt);
    priority = (position.y.round() ~/ gridSquareSize) * kPriorityStride +
        (position.x.round().abs() % kPriorityStride);
  }

  // We round the player position before calculating the miniGrid position,
  // as position values are doubles and do not necessarily hold exact values.
  Point<int> get miniGridPosition => Point(
        position.x.round() ~/ gridSquareSize,
        position.y.round() ~/ gridSquareSize,
      );

  /// Returns mini grid position as tuple (for a_star_algorithm compatibility)
  (int, int) get miniGridTuple => (
        position.x.round() ~/ gridSquareSize,
        position.y.round() ~/ gridSquareSize,
      );

  /// Whether a cell-move is currently animating.
  ///
  /// A [MoveToEffect] is added per path segment by [move] and auto-removed on
  /// completion (`removeOnFinish` defaults to `true`), so the presence of any
  /// un-completed [MoveEffect] child is an authoritative "mid-move" signal —
  /// independent of the animation `playing` flag, which flickers false for one
  /// frame between multi-segment path effects.
  ///
  /// Keyboard auto-repeat ([TechWorldGame.update]) gates the next held-key step
  /// on this so a step is never issued while a move is in flight (which would
  /// abandon the in-flight effect mid-cell and stutter). Move-completion, not a
  /// coincidental timer, becomes the cadence pacer.
  bool get isMoving =>
      children.whereType<MoveEffect>().any((e) => !e.controller.completed);

  /// Create a list of [MoveEffect]s that each add the next [MoveEffect]
  /// when the previous has finished.
  void move(List<Direction> directions, List<Vector2> largeGridPoints) {
    removeAllEffects();
    _pathSegmentNum = 0;
    _moveEffects = [];
    _directions = directions;

    // If no directions but we have points, just set position directly (e.g., bot spawn)
    if (directions.isEmpty && largeGridPoints.isNotEmpty) {
      position = largeGridPoints.first;
      return;
    }
    // Skip the first point (player's current position) — effects start from
    // the second point so each effect corresponds to a direction.
    for (int i = 1; i < largeGridPoints.length; i++) {
      _moveEffects.add(
        MoveToEffect(
          largeGridPoints[i],
          EffectController(duration: cellMoveDuration),
          onComplete: () {
            // Don't touch the animation if a one-shot emote has taken over:
            // this callback assumes `current` is a walk state, and clobbering
            // `playing`/the ticker mid-wave freezes the avatar with its arm up
            // until the next move. The emote owns its own restore (see [wave]).
            if (current != PlayerAnimState.wave) {
              playing = false;
              animationTicker?.reset();
            }
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
    final direction = _directions[_pathSegmentNum];
    // Skip Direction.none — it has no animation and zero offset.
    if (direction == Direction.none) {
      _pathSegmentNum++;
      _addNextMoveEffect();
      return;
    }
    // Guard against move() being called before onLoad sets up animations.
    if (animations == null) return;
    _facing = PlayerAnimState.forDirection(direction);
    current = _facing;
    playing = true;
    add(_moveEffects[_pathSegmentNum]);
    _pathSegmentNum++;
  }

  void removeAllEffects() {
    // Create a list of effects to remove
    final effectsToRemove = children.whereType<Effect>().toList();

    // Remove each effect
    for (final effect in effectsToRemove) {
      effect.removeFromParent();
    }
  }
}
