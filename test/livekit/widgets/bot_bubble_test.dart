import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tech_world/livekit/widgets/bot_bubble.dart';

void main() {
  group('BotBubble', () {
    testWidgets('displays first letter of name as uppercase', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: BotBubble(name: 'claude'),
          ),
        ),
      );

      expect(find.text('C'), findsOneWidget);
    });

    testWidgets('displays ? for empty name', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: BotBubble(name: ''),
          ),
        ),
      );

      expect(find.text('?'), findsOneWidget);
    });

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

    testWidgets('has circular shape with blue border', (tester) async {
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

    testWidgets('text is white and bold', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: BotBubble(name: 'Test'),
          ),
        ),
      );

      final text = tester.widget<Text>(find.text('T'));
      expect(text.style?.color, equals(Colors.white));
      expect(text.style?.fontWeight, equals(FontWeight.bold));
    });
  });
}
