import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:tech_world/flame/shared/constants.dart';
import 'package:tech_world/flame/shared/direction.dart';

/// Pure input-mapping helpers for keyboard-driven player movement.
///
/// These functions are deliberately free of Flame and rendering concerns so the
/// key → move-intent translation can be unit-tested in isolation. The Flame side
/// ([TechWorldGame] / [TechWorld]) consumes the [Direction] and routes it
/// through the *same* tap-to-move path (pathfind → move → publish position) so a
/// keyboard step broadcasts identically to a tap.
///
/// **v2** adds continuous-while-held movement and diagonals on top of v1's
/// single-key mapping:
///
/// - [directionForKey] (v1) still maps one key → one single-axis [Direction] and
///   is kept for callers that resolve a single key in isolation.
/// - [directionForKeys] (v2) resolves the *whole set* of currently-held keys
///   into a single combined [Direction], producing diagonals when two
///   perpendicular keys are held and cancelling opposing keys on the same axis.
///   [TechWorldGame] tracks the pressed-key set and re-resolves it each
///   `update(dt)` tick, stepping one cell whenever the player is idle — so
///   holding a key walks continuously rather than one step per physical press.
/// - [movementVelocity] (v2) is the authoritative definition of "no √2 diagonal
///   speed boost": it returns a velocity whose magnitude equals `speed` for both
///   cardinal and diagonal directions. The grid-stepping integration inherits
///   the equality as one-cell-per-tick cadence (a diagonal advances one cell per
///   move-completion, exactly like a cardinal).

/// Map a [LogicalKeyboardKey] to the movement [Direction] it requests.
///
/// Supports WASD and the arrow keys. Returns `null` for any key that is not a
/// movement key, so callers can cheaply ignore irrelevant input.
Direction? directionForKey(LogicalKeyboardKey key) => switch (key) {
      LogicalKeyboardKey.keyW || LogicalKeyboardKey.arrowUp => Direction.up,
      LogicalKeyboardKey.keyS || LogicalKeyboardKey.arrowDown => Direction.down,
      LogicalKeyboardKey.keyA || LogicalKeyboardKey.arrowLeft => Direction.left,
      LogicalKeyboardKey.keyD ||
      LogicalKeyboardKey.arrowRight =>
        Direction.right,
      _ => null,
    };

/// Resolve the full set of currently-held [keysPressed] into a single combined
/// movement [Direction], including diagonals.
///
/// Each held movement key contributes its axis offset; the axes are summed and
/// the sign of each summed axis selects the [Direction]:
///
/// - One key → its single-axis direction (up / down / left / right).
/// - Two perpendicular keys (e.g. W+D) → the matching diagonal (upRight).
/// - Opposing keys on the same axis (W+S, A+D) cancel that axis out.
/// - No live axis (empty set, only non-movement keys, or everything cancelled)
///   → [Direction.none], which callers treat as "don't move this tick".
///
/// This is the v2 continuous-while-held resolver: [TechWorldGame] re-runs it on
/// every tick against the live pressed-key set rather than once per key-down.
Direction directionForKeys(Set<LogicalKeyboardKey> keysPressed) {
  var dx = 0;
  var dy = 0;
  for (final key in keysPressed) {
    switch (directionForKey(key)) {
      case Direction.up:
        dy -= 1;
      case Direction.down:
        dy += 1;
      case Direction.left:
        dx -= 1;
      case Direction.right:
        dx += 1;
      default:
        break; // non-movement key, or a value directionForKey never returns
    }
  }
  // Clamp to the unit cell deltas the directionFromTuple map is keyed on.
  final sx = dx.sign;
  final sy = dy.sign;
  if (sx == 0 && sy == 0) return Direction.none;
  return directionFromTuple[(sx, sy)] ?? Direction.none;
}

/// The per-frame velocity for moving in [direction] at [speed] (pixels/second),
/// normalised so diagonal movement is **not** faster than cardinal movement.
///
/// This is the pure, testable definition of "no √2 diagonal speed boost": the
/// returned [Offset] always has magnitude `speed` (or zero for [Direction.none]),
/// whether [direction] is cardinal or diagonal. Screen coordinates: +x is right,
/// +y is down, so up is negative y.
Offset movementVelocity(Direction direction, {required double speed}) {
  final dx = direction.offsetX;
  final dy = direction.offsetY;
  if (dx == 0 && dy == 0) return Offset.zero;
  final magnitude = math.sqrt(dx * dx + dy * dy);
  return Offset(dx / magnitude * speed, dy / magnitude * speed);
}

/// Cooldown-gated cadence for continuous-while-held keyboard movement.
///
/// This is the pure, Flame-free brain of [TechWorldGame]'s `update(dt)` loop:
/// it decides *when* the next held-key cell-step should fire without knowing how
/// the step is enacted. Keeping it here means the held-key cadence (immediate
/// first step, then one step per [stepInterval]) is unit-testable by driving
/// [tick] with simulated `dt` values, exactly as the game loop would.
///
/// Usage per tick:
/// ```dart
/// final direction = directionForKeys(keysPressed);
/// if (direction != Direction.none && ticker.tick(dt)) {
///   moveInDirection(direction); // enact one cell-step
/// }
/// ```
class MovementTicker {
  MovementTicker({required this.stepInterval});

  /// Seconds between consecutive held-key cell-steps. Matched to the per-cell
  /// move animation so cadence stays in lock-step with motion.
  final double stepInterval;

  double _cooldown = 0;

  /// Advance the cooldown by [dt] and report whether a step should fire now.
  ///
  /// Returns `true` (and re-arms the cooldown to [stepInterval]) when the
  /// cooldown has elapsed; `false` otherwise. The first call after a [reset]
  /// fires immediately, so a fresh key-press steps without waiting a full
  /// interval — then subsequent steps are spaced by [stepInterval].
  bool tick(double dt) {
    if (_cooldown > 0) _cooldown -= dt;
    if (_cooldown > 0) return false;
    _cooldown = stepInterval;
    return true;
  }

  /// Re-arm so the next [tick] fires immediately. Call when a new movement key
  /// is first pressed so the initial step feels responsive.
  void reset() => _cooldown = 0;
}

/// Decide the cell-step (if any) to enact for one game tick of continuous
/// keyboard movement, and advance [ticker] as a side-effect.
///
/// This is the pure, Flame-free decision the [TechWorldGame.update] loop runs
/// each frame, factored out so the gate ordering is unit-testable without
/// standing up a [TechWorld]. Returns the [Direction] to move, or `null` when no
/// step should be issued this tick. The gate order is load-bearing:
///
/// 1. No live direction ([Direction.none]) → no step.
/// 2. [playerIsMoving] → no step **and the ticker is not advanced**, so a step
///    is ready on the very first tick after the move completes rather than one
///    [MovementTicker.stepInterval] later. Move-completion is the real pacer;
///    the ticker is only a lower bound on cadence. This is the re-entrancy guard
///    that stops a step being re-issued mid-cell (which would abandon the
///    in-flight [MoveEffect] and stutter).
/// 3. [MovementTicker.tick] gates the cadence floor; only then do we step.
Direction? nextKeyboardStep({
  required Set<LogicalKeyboardKey> keysPressed,
  required bool playerIsMoving,
  required MovementTicker ticker,
  required double dt,
}) {
  final direction = directionForKeys(keysPressed);
  if (direction == Direction.none) return null;
  if (playerIsMoving) return null;
  if (!ticker.tick(dt)) return null;
  return direction;
}

/// Compute the grid cell one step away from [current] in [direction].
///
/// Cells are `(x, y)` tuples matching the a_star / pathfinding convention used
/// by [PathComponent]. The per-direction offsets come from [Direction] itself
/// (one [gridSquareSizeDouble] per step), divided back down to grid units so the
/// result is a cell delta of -1/0/+1 per axis.
(int, int) targetCellForDirection((int, int) current, Direction direction) {
  final dx = (direction.offsetX / gridSquareSizeDouble).round();
  final dy = (direction.offsetY / gridSquareSizeDouble).round();
  return (current.$1 + dx, current.$2 + dy);
}

/// Whether a text-editing widget currently holds focus.
///
/// Keyboard movement MUST be suppressed while the user is typing (chat input,
/// prompt-challenge input, DM input) — otherwise "swap" typed into chat would
/// also walk the avatar. A focused [TextField] / [TextFormField] delegates focus
/// to an internal [EditableText], so we check the focused element's widget and
/// its ancestors for an [EditableText].
bool isTextFieldFocused() {
  final focused = FocusManager.instance.primaryFocus;
  final context = focused?.context;
  if (context == null) return false;

  if (context.widget is EditableText) return true;

  var found = false;
  context.visitAncestorElements((element) {
    if (element.widget is EditableText) {
      found = true;
      return false; // stop walking
    }
    return true;
  });
  return found;
}
