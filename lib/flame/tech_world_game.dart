import 'package:flame/components.dart';
import 'package:flame/game.dart';
import 'package:flame/input.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart' show KeyEventResult;
import 'package:tech_world/flame/shared/direction.dart';
import 'package:tech_world/flame/shared/keyboard_movement.dart';
import 'package:tech_world/flame/tech_world.dart';
import 'package:tech_world/flame/tiles/predefined_tilesets.dart';
import 'package:tech_world/flame/tiles/tileset_registry.dart';

class SnapshotComponent extends PositionComponent with Snapshot {}

/// We extend FlameGame where we set the world component, load texture images
/// and setup the camera.
///
/// The [KeyboardEvents] mixin adds WASD / arrow-key player movement. **v2** is
/// continuous-while-held with diagonals:
///
/// - [onKeyEvent] only maintains the set of currently-held movement keys
///   ([_keysPressed]); it does not move the player directly.
/// - [update] re-resolves that set into a combined [Direction] (diagonals
///   included via [directionForKeys]) every tick and, whenever the player is
///   idle, forwards it to [TechWorld.moveInDirection] — which routes through the
///   same tap-to-move path (pathfind → move → broadcast). Holding a key walks
///   continuously; releasing it stops at the next cell boundary.
///
/// The per-cell move animation *is* the cadence: a new step is issued only once
/// the previous cell-move has finished, which both paces continuous movement
/// (no idle gap) and prevents a re-entrant move that would abandon the in-flight
/// effect mid-cell. There is no separate repeat timer. Movement is one cell per
/// step in any direction (grid cadence); a diagonal cell covers more pixels than
/// a cardinal one, so diagonals are not pixel-speed-matched — see
/// [nextKeyboardStep].
///
/// Tap-to-move is unaffected, and movement is suppressed while a text field is
/// focused (checked in *both* [onKeyEvent] and [update], because focus can move
/// to a field by mouse/tap with no keyboard event) so typing never walks the
/// avatar.
class TechWorldGame extends FlameGame with KeyboardEvents {
  TechWorldGame({required super.world});

  late final SnapshotComponent root;

  /// Registry for loading and accessing tileset sprite sheets.
  late final TilesetRegistry tilesetRegistry;

  /// Movement keys currently held down. Maintained by [onKeyEvent]; consumed by
  /// [update] each tick to drive continuous-while-held movement.
  final Set<LogicalKeyboardKey> _keysPressed = {};

  /// Read-only view of the currently-held movement keys, for tests asserting the
  /// focus-stranding guard clears them.
  @visibleForTesting
  Set<LogicalKeyboardKey> get heldMovementKeys =>
      Set.unmodifiable(_keysPressed);

  @override
  KeyEventResult onKeyEvent(
    KeyEvent event,
    Set<LogicalKeyboardKey> keysPressed,
  ) {
    // Never capture movement keys while the user is typing (chat / prompt / DM).
    // Drop any tracked keys so a focus change mid-hold can't strand the player
    // walking, then let the focused field handle the event.
    if (isTextFieldFocused()) {
      _keysPressed.clear();
      return KeyEventResult.ignored;
    }

    final key = event.logicalKey;
    // Only track keys that actually request movement; ignore everything else.
    if (directionForKey(key) == null) return KeyEventResult.ignored;

    switch (event) {
      case KeyDownEvent():
        _keysPressed.add(key);
      case KeyUpEvent():
        _keysPressed.remove(key);
      case KeyRepeatEvent():
        // OS auto-repeat is irrelevant — [update] paces movement off the move
        // animation, not off key-repeat events.
        break;
    }
    return KeyEventResult.handled;
  }

  @override
  void update(double dt) {
    super.update(dt);

    // Focus can move to a text field by mouse/tap with NO keyboard event, so the
    // onKeyEvent guard isn't enough — re-check here (the emission point) and drop
    // any held keys, or a held key would keep walking the avatar while typing.
    if (isTextFieldFocused()) {
      _keysPressed.clear();
      return;
    }

    final techWorld = world;
    if (techWorld is! TechWorld) return;

    // The step decision (direction resolution + idle gate) lives in the pure
    // [nextKeyboardStep] so it is unit-tested without a live TechWorld and the
    // runtime/test paths can't drift. The idle gate makes the move animation the
    // cadence — no separate timer.
    final direction = nextKeyboardStep(
      keysPressed: _keysPressed,
      playerIsMoving: techWorld.isUserPlayerMoving,
    );
    if (direction == null) return;

    techWorld.moveInDirection(direction);
  }

  @override
  Future<void> onLoad() async {
    await images.loadAll([
      'NPC11.png',
      'NPC12.png',
      'NPC13.png',
      'claude_bot.png',
      'dreamfinder_bot_sheet.png',
    ]);

    // Initialize tileset registry and load all predefined tilesets.
    tilesetRegistry = TilesetRegistry(images: images);
    await tilesetRegistry.loadAll(allTilesets);

    // Add a snapshot component.
    root = SnapshotComponent();
    add(root);

    camera.viewfinder.anchor = Anchor.center;
  }
}
