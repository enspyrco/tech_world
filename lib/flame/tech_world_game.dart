import 'package:flame/components.dart';
import 'package:flame/game.dart';
import 'package:flame/input.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart' show KeyEventResult;
import 'package:tech_world/flame/shared/keyboard_movement.dart';
import 'package:tech_world/flame/tech_world.dart';
import 'package:tech_world/flame/tiles/predefined_tilesets.dart';
import 'package:tech_world/flame/tiles/tileset_registry.dart';

class SnapshotComponent extends PositionComponent with Snapshot {}

/// We extend FlameGame where we set the world component, load texture images
/// and setup the camera.
///
/// The [KeyboardEvents] mixin adds WASD / arrow-key player movement: a movement
/// key-down is translated to a [Direction] and forwarded to [TechWorld], which
/// routes it through the same tap-to-move path (pathfind → move → broadcast).
/// Tap-to-move is unaffected, and keystrokes are ignored while a text field is
/// focused so typing in chat / prompt / DM inputs never walks the avatar.
class TechWorldGame extends FlameGame with KeyboardEvents {
  TechWorldGame({required super.world});

  late final SnapshotComponent root;

  /// Registry for loading and accessing tileset sprite sheets.
  late final TilesetRegistry tilesetRegistry;

  @override
  KeyEventResult onKeyEvent(
    KeyEvent event,
    Set<LogicalKeyboardKey> keysPressed,
  ) {
    // One cell per physical key-press. We deliberately ignore KeyRepeatEvent
    // (OS auto-repeat) and KeyUpEvent: each per-cell move runs a 0.2s animation,
    // and letting fast auto-repeat restart it mid-flight would stutter. Holding
    // a key therefore takes one step; continuous-while-held is a future refinement.
    if (event is! KeyDownEvent) return KeyEventResult.ignored;

    // Never capture movement keys while the user is typing.
    if (isTextFieldFocused()) return KeyEventResult.ignored;

    final direction = directionForKey(event.logicalKey);
    if (direction == null) return KeyEventResult.ignored;

    final techWorld = world;
    if (techWorld is! TechWorld) return KeyEventResult.ignored;

    techWorld.moveInDirection(direction);
    return KeyEventResult.handled;
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
