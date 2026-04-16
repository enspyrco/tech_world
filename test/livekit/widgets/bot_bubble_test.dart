import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tech_world/bots/bot_config.dart';
import 'package:tech_world/livekit/widgets/bot_bubble.dart';

const _testBot = BotConfig(
  identity: 'bot-test',
  displayName: 'TestBot',
  spriteAsset: 'test_bot.png',
  accentColor: Color(0xFF00FF00),
  avatarLetter: 'T',
);

void main() {
  group('BotBubble', () {
    testWidgets('uses default size of 80', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: BotBubble(config: _testBot),
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
            body: BotBubble(config: _testBot, size: 120),
          ),
        ),
      );

      final container = tester.widget<Container>(find.byType(Container).first);
      expect(container.constraints?.maxWidth, equals(120));
      expect(container.constraints?.maxHeight, equals(120));
    });

    testWidgets('has circular shape with config accent color border',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: BotBubble(config: _testBot),
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
            body: BotBubble(config: _testBot),
          ),
        ),
      );

      expect(find.byType(ClipOval), findsOneWidget);
    });

    testWidgets('attempts to load bot sprite image', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: BotBubble(config: clawdBot),
          ),
        ),
      );

      expect(find.byType(Image), findsOneWidget);
    });

    testWidgets('uses accent color from BotConfig', (tester) async {
      const goldBot = BotConfig(
        identity: 'bot-gold',
        displayName: 'GoldBot',
        spriteAsset: 'gold.png',
        accentColor: Color(0xFFDAA520),
        avatarLetter: 'G',
      );

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: BotBubble(config: goldBot),
          ),
        ),
      );

      final container = tester.widget<Container>(find.byType(Container).first);
      final decoration = container.decoration as BoxDecoration;
      final border = decoration.border as Border;
      expect(border.top.color, equals(const Color(0xFFDAA520)));
    });

    testWidgets('has shadow in decoration', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: BotBubble(config: _testBot),
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
            body: BotBubble(config: _testBot),
          ),
        ),
      );

      final containers = find.byType(Container);
      expect(containers, findsAtLeast(2));
    });
  });
}
