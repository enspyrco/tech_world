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
/// v1 is intentionally **single-axis**: each key maps to one of up/down/left/
/// right. Diagonals are never produced (W+A pressed together yields two
/// independent single-axis steps via OS key-repeat, not a combined diagonal).

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
