import 'package:flame/components.dart';
import 'package:flame/game.dart';
import 'package:flame_test/flame_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tech_world/flame/tech_world_game.dart';

/// Game-level keyboard tests for [TechWorldGame] — specifically the
/// focus-stranding guard in [TechWorldGame.update].
///
/// Movement emits from `update()`, not from `onKeyEvent`. Focus can move to a
/// text field by mouse/tap with NO keyboard event, so the onKeyEvent guard alone
/// would leave keys held and keep walking the avatar while the user types. The
/// guard is therefore re-checked in `update()`; these tests pin that it clears
/// the held-key set.
class _KeyboardTestGame extends TechWorldGame {
  _KeyboardTestGame() : super(world: World());

  @override
  Future<void> onLoad() async {
    // Skip asset loading / tileset setup — these tests only drive key state.
    camera.viewfinder.anchor = Anchor.center;
  }
}

KeyDownEvent _keyDown(LogicalKeyboardKey key) => KeyDownEvent(
      logicalKey: key,
      physicalKey: PhysicalKeyboardKey.keyW, // physical key is irrelevant here
      timeStamp: Duration.zero,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWithGame<_KeyboardTestGame>(
    'a held movement key is tracked when no text field is focused',
    _KeyboardTestGame.new,
    (game) async {
      await game.ready();

      game.onKeyEvent(_keyDown(LogicalKeyboardKey.keyD), {});
      expect(game.heldMovementKeys, contains(LogicalKeyboardKey.keyD));
    },
  );

  testWidgets(
    'update() clears held keys when a text field gains focus (no key event)',
    (tester) async {
      final game = _KeyboardTestGame();

      // Mount the game inside a widget tree that also has a TextField, so a real
      // FocusManager / EditableText exists for isTextFieldFocused().
      final focusNode = FocusNode();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                Expanded(child: GameWidget(game: game)),
                TextField(focusNode: focusNode),
              ],
            ),
          ),
        ),
      );
      await tester.pump();

      // Hold a movement key while NOTHING is focused.
      game.onKeyEvent(_keyDown(LogicalKeyboardKey.keyD), {});
      expect(game.heldMovementKeys, isNotEmpty,
          reason: 'key tracked before focus moves');

      // Focus a text field by (simulated) tap/programmatic focus — crucially,
      // with NO keyboard event delivered to the game.
      focusNode.requestFocus();
      await tester.pump();

      // A game tick now runs. The update() focus guard must drop the held keys
      // so the avatar does not keep walking while the user types.
      game.update(1 / 60);
      expect(game.heldMovementKeys, isEmpty,
          reason: 'focus-stranding guard clears held keys in update()');

      focusNode.dispose();
    },
  );
}
