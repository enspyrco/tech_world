import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tech_world/flame/shared/direction.dart';
import 'package:tech_world/flame/shared/keyboard_movement.dart';

void main() {
  group('directionForKey', () {
    test('WASD maps to single-axis directions', () {
      expect(directionForKey(LogicalKeyboardKey.keyW), Direction.up);
      expect(directionForKey(LogicalKeyboardKey.keyS), Direction.down);
      expect(directionForKey(LogicalKeyboardKey.keyA), Direction.left);
      expect(directionForKey(LogicalKeyboardKey.keyD), Direction.right);
    });

    test('arrow keys map to single-axis directions', () {
      expect(directionForKey(LogicalKeyboardKey.arrowUp), Direction.up);
      expect(directionForKey(LogicalKeyboardKey.arrowDown), Direction.down);
      expect(directionForKey(LogicalKeyboardKey.arrowLeft), Direction.left);
      expect(directionForKey(LogicalKeyboardKey.arrowRight), Direction.right);
    });

    test('unrelated keys produce no direction', () {
      expect(directionForKey(LogicalKeyboardKey.space), isNull);
      expect(directionForKey(LogicalKeyboardKey.enter), isNull);
      expect(directionForKey(LogicalKeyboardKey.keyQ), isNull);
      expect(directionForKey(LogicalKeyboardKey.escape), isNull);
    });

    test('only single-axis (non-diagonal) directions are produced', () {
      // v1 is single-axis only; assert no key yields a diagonal.
      const diagonals = {
        Direction.upLeft,
        Direction.upRight,
        Direction.downLeft,
        Direction.downRight,
      };
      for (final key in [
        LogicalKeyboardKey.keyW,
        LogicalKeyboardKey.keyA,
        LogicalKeyboardKey.keyS,
        LogicalKeyboardKey.keyD,
        LogicalKeyboardKey.arrowUp,
        LogicalKeyboardKey.arrowDown,
        LogicalKeyboardKey.arrowLeft,
        LogicalKeyboardKey.arrowRight,
      ]) {
        final dir = directionForKey(key);
        expect(dir, isNotNull);
        expect(diagonals.contains(dir), isFalse);
      }
    });
  });

  group('targetCellForDirection', () {
    test('offsets the current cell by one grid square per direction', () {
      expect(targetCellForDirection((5, 5), Direction.up), (5, 4));
      expect(targetCellForDirection((5, 5), Direction.down), (5, 6));
      expect(targetCellForDirection((5, 5), Direction.left), (4, 5));
      expect(targetCellForDirection((5, 5), Direction.right), (6, 5));
    });

    test('Direction.none leaves the cell unchanged', () {
      expect(targetCellForDirection((3, 7), Direction.none), (3, 7));
    });
  });

  group('isTextFieldFocused', () {
    test('false when nothing is focused', () {
      // No widget tree mounted -> primaryFocus is null.
      expect(isTextFieldFocused(), isFalse);
    });

    testWidgets('true when a TextField has focus', (tester) async {
      final focusNode = FocusNode();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TextField(focusNode: focusNode),
          ),
        ),
      );
      focusNode.requestFocus();
      await tester.pump();

      expect(isTextFieldFocused(), isTrue);
      focusNode.dispose();
    });

    testWidgets('false when focus is on a non-text widget', (tester) async {
      final focusNode = FocusNode();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Focus(
              focusNode: focusNode,
              child: const SizedBox(width: 10, height: 10),
            ),
          ),
        ),
      );
      focusNode.requestFocus();
      await tester.pump();

      expect(isTextFieldFocused(), isFalse);
      focusNode.dispose();
    });
  });
}
