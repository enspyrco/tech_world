import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tech_world/livekit/widgets/screen_share_panel.dart';

void main() {
  group('ScreenSharePanel', () {
    testWidgets('renders title bar with sharer name', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Stack(
              children: [
                ScreenSharePanel(
                  sharerName: 'Alice',
                  // No videoTrack — panel should still render its chrome.
                  videoTrack: null,
                  onClose: () {},
                ),
              ],
            ),
          ),
        ),
      );

      expect(find.text('Alice'), findsOneWidget);
    });

    testWidgets('close button calls onClose callback', (tester) async {
      var closed = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Stack(
              children: [
                ScreenSharePanel(
                  sharerName: 'Bob',
                  videoTrack: null,
                  onClose: () => closed = true,
                ),
              ],
            ),
          ),
        ),
      );

      await tester.tap(find.byIcon(Icons.close));
      await tester.pumpAndSettle();

      expect(closed, isTrue);
    });

    testWidgets('maximize button toggles maximized state', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Stack(
              children: [
                ScreenSharePanel(
                  sharerName: 'Charlie',
                  videoTrack: null,
                  onClose: () {},
                ),
              ],
            ),
          ),
        ),
      );

      // Initially should show maximize icon (open_in_full).
      expect(find.byIcon(Icons.open_in_full), findsOneWidget);

      // Tap maximize.
      await tester.tap(find.byIcon(Icons.open_in_full));
      await tester.pumpAndSettle();

      // Should now show minimize icon (close_fullscreen).
      expect(find.byIcon(Icons.close_fullscreen), findsOneWidget);

      // Tap again to restore.
      await tester.tap(find.byIcon(Icons.close_fullscreen));
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.open_in_full), findsOneWidget);
    });

    testWidgets('shows placeholder when no video track', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Stack(
              children: [
                ScreenSharePanel(
                  sharerName: 'Diana',
                  videoTrack: null,
                  onClose: () {},
                ),
              ],
            ),
          ),
        ),
      );

      // Title bar has a small 16px icon; body placeholder has a large 48px one.
      // Verify the large placeholder icon is present.
      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget is Icon &&
              widget.icon == Icons.screen_share &&
              widget.size == 48,
        ),
        findsOneWidget,
      );
    });

    testWidgets('default size is 640x400', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Stack(
              children: [
                ScreenSharePanel(
                  sharerName: 'Eve',
                  videoTrack: null,
                  onClose: () {},
                ),
              ],
            ),
          ),
        ),
      );

      // Find the panel container (the outermost Positioned or SizedBox).
      final panel = tester.widget<SizedBox>(
        find.byWidgetPredicate(
          (widget) =>
              widget is SizedBox &&
              widget.width == 640 &&
              widget.height == 400,
        ),
      );
      expect(panel, isNotNull);
    });
  });
}
