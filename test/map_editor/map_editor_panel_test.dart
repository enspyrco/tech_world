import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tech_world/map_editor/map_editor_panel.dart';
import 'package:tech_world/map_editor/map_editor_state.dart';

void main() {
  group('MapEditorPanel', () {
    late MapEditorState state;

    setUp(() {
      state = MapEditorState();
    });

    testWidgets('Apply button triggers onApply callback', (tester) async {
      var applyCalled = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 480,
              child: MapEditorPanel(
                state: state,
                onApply: () async => applyCalled = true,
                onCancel: () async {},
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.byIcon(Icons.check));
      await tester.pumpAndSettle();

      expect(applyCalled, isTrue);
    });

    testWidgets('Cancel button triggers onCancel callback', (tester) async {
      var cancelCalled = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 480,
              child: MapEditorPanel(
                state: state,
                onApply: () async {},
                onCancel: () async => cancelCalled = true,
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.byIcon(Icons.close));
      await tester.pumpAndSettle();

      expect(cancelCalled, isTrue);
    });

    testWidgets('Apply button has correct tooltip', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 480,
              child: MapEditorPanel(
                state: state,
                onApply: () async {},
                onCancel: () async {},
              ),
            ),
          ),
        ),
      );

      final applyButton = tester.widget<IconButton>(
        find.widgetWithIcon(IconButton, Icons.check),
      );
      expect(applyButton.tooltip, 'Apply changes');
    });

    testWidgets('Cancel button has correct tooltip', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 480,
              child: MapEditorPanel(
                state: state,
                onApply: () async {},
                onCancel: () async {},
              ),
            ),
          ),
        ),
      );

      final cancelButton = tester.widget<IconButton>(
        find.widgetWithIcon(IconButton, Icons.close),
      );
      expect(cancelButton.tooltip, 'Discard changes');
    });
  });
}
