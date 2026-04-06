import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tech_world/map_editor/wall_style_picker.dart';

void main() {
  group('WallStylePicker', () {
    testWidgets('shows all style swatches', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: WallStylePicker(
            selectedStyle: 'modern_gray_07',
            onStyleSelected: (_) {},
          ),
        ),
      ));

      final swatches = find.byType(WallStyleSwatch);
      expect(swatches, findsWidgets);
      // 53 styles defined (54 minus empty slots).
      expect(
        tester.widgetList(swatches).length,
        equals(wallStyleSwatches.length),
      );
    });

    testWidgets('tapping a swatch calls onStyleSelected', (tester) async {
      String? selectedStyle;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: WallStylePicker(
            selectedStyle: 'modern_gray_07',
            onStyleSelected: (s) => selectedStyle = s,
          ),
        ),
      ));

      // Tap the first swatch (diamond_wallpaper).
      final firstSwatch = find.byType(WallStyleSwatch).first;
      await tester.tap(firstSwatch);
      expect(selectedStyle, equals('diamond_wallpaper'));
    });

    testWidgets('selected style swatch is marked', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: WallStylePicker(
            selectedStyle: 'coral_red',
            onStyleSelected: (_) {},
          ),
        ),
      ));

      final swatches = tester.widgetList<WallStyleSwatch>(
        find.byType(WallStyleSwatch),
      );
      final selected = swatches.where((s) => s.isSelected);
      expect(selected, hasLength(1));
      expect(selected.first.styleId, 'coral_red');
    });

    testWidgets('swatch tooltip shows display name', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: WallStylePicker(
            selectedStyle: 'modern_gray_07',
            onStyleSelected: (_) {},
          ),
        ),
      ));

      // Long-press to show tooltip.
      final graySwatch = find.byType(WallStyleSwatch).at(6); // index 6 = modern_gray_07
      await tester.longPress(graySwatch);
      await tester.pumpAndSettle();
      expect(find.text('Modern Gray 07'), findsOneWidget);
    });
  });
}
