import 'package:flame/components.dart';
import 'package:flame/game.dart';
import 'package:flame/input.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart' show KeyEventResult;
import 'package:tech_world/flame/components/player_component.dart';
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
///   included via [directionForKeys]) on every tick and, on a cooldown matched
///   to the per-cell animation ([PlayerComponent.cellMoveDuration]), forwards it
///   to [TechWorld.moveInDirection] — which routes through the same tap-to-move
///   path (pathfind → move → broadcast). Holding a key therefore walks
///   continuously; releasing it stops at the next cell boundary.
///
/// The cooldown gives one cell-step per [PlayerComponent.cellMoveDuration]
/// regardless of cardinal vs diagonal, so a diagonal is not √2 faster (no speed
/// boost). Tap-to-move is unaffected, and keystrokes are ignored while a text
/// field is focused so typing in chat / prompt / DM inputs never walks the
/// avatar.
class TechWorldGame extends FlameGame with KeyboardEvents {
  TechWorldGame({required super.world});

  late final SnapshotComponent root;

  /// Registry for loading and accessing tileset sprite sheets.
  late final TilesetRegistry tilesetRegistry;

  /// Movement keys currently held down. Maintained by [onKeyEvent]; consumed by
  /// [update] each tick to drive continuous-while-held movement.
  final Set<LogicalKeyboardKey> _keysPressed = {};

  /// Cooldown-gated cadence for held-key auto-repeat. Step interval matches the
  /// per-cell move animation so the repeat rate stays in lock-step with motion
  /// (and a diagonal is not √2 faster — one cell per interval either way).
  final MovementTicker _moveTicker =
      MovementTicker(stepInterval: PlayerComponent.cellMoveDuration);

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
        // Fire the first step immediately so a tap feels responsive; the
        // ticker then governs subsequent held-key repeats in [update].
        if (_keysPressed.add(key)) _moveTicker.reset();
      case KeyUpEvent():
        _keysPressed.remove(key);
      case KeyRepeatEvent():
        // OS auto-repeat is irrelevant — [update]'s cooldown owns repeat cadence.
        break;
    }
    return KeyEventResult.handled;
  }

  @override
  void update(double dt) {
    super.update(dt);

    final techWorld = world;
    if (techWorld is! TechWorld) return;

    // The whole step decision (direction resolution + idle re-entrancy guard +
    // cadence floor) lives in the pure [nextKeyboardStep] so it is unit-tested
    // without a live TechWorld and the runtime/test paths can't drift.
    final direction = nextKeyboardStep(
      keysPressed: _keysPressed,
      playerIsMoving: techWorld.isUserPlayerMoving,
      ticker: _moveTicker,
      dt: dt,
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
