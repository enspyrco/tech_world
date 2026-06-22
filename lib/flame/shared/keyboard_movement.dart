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
///   [TechWorldGame] re-resolves the live pressed-key set each `update(dt)` tick.
/// - [nextKeyboardStep] (v2) is the per-tick decision: it emits the next
///   cell-step only when the player is idle, so the *move animation itself* paces
///   the walk (continuous, one cell per completed move) and a step is never
///   re-issued mid-cell.
///
/// **Movement is one cell per step in any direction (grid cadence).** A diagonal
/// step covers more ground per cell than a cardinal one — `(±32, ±32)` vs
/// `(±32, 0)` — so on screen a diagonal travels ~√2 farther in the same
/// [PlayerComponent.cellMoveDuration]. There is intentionally **no** pixel-speed
/// normalisation; whether diagonals should *feel* speed-matched is a separate
/// design decision, not something this layer asserts.

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

/// Decide the cell-step (if any) to enact for one game tick of continuous
/// keyboard movement.
///
/// This is the pure, Flame-free decision the [TechWorldGame.update] loop runs
/// each frame, factored out so it is unit-testable without standing up a
/// [TechWorld]. Returns the [Direction] to move, or `null` when no step should
/// be issued this tick:
///
/// 1. No live direction ([Direction.none], e.g. nothing held or opposing keys
///    cancel) → no step.
/// 2. [playerIsMoving] → no step. The in-flight cell-move animation *is* the
///    cadence: this both prevents re-entrancy (issuing a second move mid-cell
///    would abandon the running [MoveEffect] and stutter) AND paces continuous
///    movement with no idle gap — the instant the move completes, the next held
///    tick steps again. There is no separate timer; the animation duration is
///    the interval.
Direction? nextKeyboardStep({
  required Set<LogicalKeyboardKey> keysPressed,
  required bool playerIsMoving,
}) {
  final direction = directionForKeys(keysPressed);
  if (direction == Direction.none) return null;
  if (playerIsMoving) return null;
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
