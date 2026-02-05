import 'package:flame/components.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tech_world/flame/components/terminal_component.dart';
import 'package:tech_world/flame/shared/constants.dart';

void main() {
  group('TerminalComponent', () {
    group('constructor', () {
      test('creates component at given position', () {
        final terminal = TerminalComponent(
          position: Vector2(100, 200),
          onInteract: () {},
        );

        expect(terminal.position.x, equals(100));
        expect(terminal.position.y, equals(200));
      });

      test('has grid square size', () {
        final terminal = TerminalComponent(
          position: Vector2.zero(),
          onInteract: () {},
        );

        expect(terminal.size.x, equals(gridSquareSizeDouble));
        expect(terminal.size.y, equals(gridSquareSizeDouble));
      });

      test('has topLeft anchor', () {
        final terminal = TerminalComponent(
          position: Vector2.zero(),
          onInteract: () {},
        );

        expect(terminal.anchor, equals(Anchor.topLeft));
      });
    });

    group('interaction', () {
      test('is a PositionComponent', () {
        final terminal = TerminalComponent(
          position: Vector2.zero(),
          onInteract: () {},
        );

        expect(terminal, isA<PositionComponent>());
      });

      test('stores onInteract callback', () {
        var called = false;
        final terminal = TerminalComponent(
          position: Vector2.zero(),
          onInteract: () => called = true,
        );

        terminal.onInteract();
        expect(called, isTrue);
      });
    });

    group('positioning', () {
      test('can be positioned at grid coordinates', () {
        final gridX = 8;
        final gridY = 12;
        final terminal = TerminalComponent(
          position: Vector2(
            gridX * gridSquareSizeDouble,
            gridY * gridSquareSizeDouble,
          ),
          onInteract: () {},
        );

        expect(terminal.position.x, equals(gridX * gridSquareSizeDouble));
        expect(terminal.position.y, equals(gridY * gridSquareSizeDouble));
      });
    });
  });
}
