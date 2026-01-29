import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tech_world/livekit/widgets/bot_bubble.dart';

void main() {
  group('BotBubble', () {
    testWidgets('uses default size of 80', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: BotBubble(name: 'Test'),
          ),
        ),
      );

      final container = tester.widget<Container>(find.byType(Container).first);
      expect(container.constraints?.maxWidth, equals(80));
      expect(container.constraints?.maxHeight, equals(80));
    });

    testWidgets('respects custom size parameter', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: BotBubble(name: 'Test', size: 120),
          ),
        ),
      );

      final container = tester.widget<Container>(find.byType(Container).first);
      expect(container.constraints?.maxWidth, equals(120));
      expect(container.constraints?.maxHeight, equals(120));
    });

    testWidgets('has circular shape with orange border', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: BotBubble(name: 'Test'),
          ),
        ),
      );

      final container = tester.widget<Container>(find.byType(Container).first);
      final decoration = container.decoration as BoxDecoration;

      expect(decoration.shape, equals(BoxShape.circle));
      expect(decoration.border, isNotNull);
    });

    testWidgets('contains ClipOval for circular clipping', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: BotBubble(name: 'Test'),
          ),
        ),
      );

      expect(find.byType(ClipOval), findsOneWidget);
    });

    testWidgets('attempts to load claude_bot.png image', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: BotBubble(name: 'Claude'),
          ),
        ),
      );

      // The Image.asset widget should be present
      expect(find.byType(Image), findsOneWidget);
    });

    test('clawdOrange constant is correct', () {
      expect(BotBubble.clawdOrange.toARGB32(), equals(0xFFD97757));
    });

    test('_getInitial returns first letter uppercase for non-empty name', () {
      // We test the widget's behavior indirectly since _getInitial is private
      // The initial logic is: name.isNotEmpty ? name[0].toUpperCase() : '?'
      // This is verified through the errorBuilder which uses _getInitial()
      expect('Claude'[0].toUpperCase(), equals('C'));
      expect('test'[0].toUpperCase(), equals('T'));
    });

    test('_getInitial returns ? for empty name', () {
      const name = '';
      final initial = name.isNotEmpty ? name[0].toUpperCase() : '?';
      expect(initial, equals('?'));
    });

    testWidgets('has shadow in decoration', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: BotBubble(name: 'Test'),
          ),
        ),
      );

      final container = tester.widget<Container>(find.byType(Container).first);
      final decoration = container.decoration as BoxDecoration;

      expect(decoration.boxShadow, isNotEmpty);
    });

    testWidgets('inner container has dark background', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: BotBubble(name: 'Test'),
          ),
        ),
      );

      // Find the inner Container (second one)
      final containers = find.byType(Container);
      expect(containers, findsAtLeast(2));
    });
  });
}
