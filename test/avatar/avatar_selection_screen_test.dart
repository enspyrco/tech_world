import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tech_world/avatar/avatar.dart';
import 'package:tech_world/avatar/avatar_selection_screen.dart';
import 'package:tech_world/avatar/predefined_avatars.dart';

void main() {
  group('AvatarSelectionScreen', () {
    testWidgets('displays all predefined avatars with names', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: AvatarSelectionScreen(onAvatarSelected: (_) {}),
      ));

      for (final avatar in predefinedAvatars) {
        expect(find.text(avatar.displayName), findsOneWidget);
      }
    });

    testWidgets('default avatar is initially selected', (tester) async {
      Avatar? selectedAvatar;

      await tester.pumpWidget(MaterialApp(
        home: AvatarSelectionScreen(
          onAvatarSelected: (avatar) => selectedAvatar = avatar,
        ),
      ));

      // Confirm immediately — should return the default avatar
      await tester.tap(find.text('Confirm'));
      await tester.pumpAndSettle();

      expect(selectedAvatar, equals(defaultAvatar));
    });

    testWidgets('tapping an avatar selects it', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: AvatarSelectionScreen(onAvatarSelected: (_) {}),
      ));

      // Tap the second avatar (Ranger / NPC12)
      await tester.tap(find.text(predefinedAvatars[1].displayName));
      await tester.pumpAndSettle();

      // Now there should be a selected border on the tapped card
      // We verify by checking the confirm button callback fires with the right avatar
    });

    testWidgets('confirm button calls onAvatarSelected with chosen avatar',
        (tester) async {
      Avatar? selectedAvatar;

      await tester.pumpWidget(MaterialApp(
        home: AvatarSelectionScreen(
          onAvatarSelected: (avatar) => selectedAvatar = avatar,
        ),
      ));

      // Tap the second avatar
      await tester.tap(find.text(predefinedAvatars[1].displayName));
      await tester.pumpAndSettle();

      // Tap the confirm button
      await tester.tap(find.text('Confirm'));
      await tester.pumpAndSettle();

      expect(selectedAvatar, equals(predefinedAvatars[1]));
    });

    testWidgets('confirm button with default selection returns default avatar',
        (tester) async {
      Avatar? selectedAvatar;

      await tester.pumpWidget(MaterialApp(
        home: AvatarSelectionScreen(
          onAvatarSelected: (avatar) => selectedAvatar = avatar,
        ),
      ));

      // Tap confirm without changing selection
      await tester.tap(find.text('Confirm'));
      await tester.pumpAndSettle();

      expect(selectedAvatar, equals(defaultAvatar));
    });

    testWidgets('initialAvatar prop pre-selects a previously saved avatar',
        (tester) async {
      Avatar? selectedAvatar;

      await tester.pumpWidget(MaterialApp(
        home: AvatarSelectionScreen(
          onAvatarSelected: (avatar) => selectedAvatar = avatar,
          initialAvatar: predefinedAvatars[2], // Scholar / NPC13
        ),
      ));

      // Confirm without changing — should return the initial avatar
      await tester.tap(find.text('Confirm'));
      await tester.pumpAndSettle();

      expect(selectedAvatar, equals(predefinedAvatars[2]));
    });

    testWidgets('displays a title', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: AvatarSelectionScreen(onAvatarSelected: (_) {}),
      ));

      expect(find.text('Choose Your Character'), findsOneWidget);
    });
  });

  // Regression: on a short phone viewport the avatar cards wrap to extra rows
  // and the content is taller than the screen. Previously the Confirm button
  // was pushed off the bottom with no way to scroll — you could not get past
  // character selection on a phone. The screen is now scrollable.
  group('AvatarSelectionScreen on a short phone viewport', () {
    // Shorter than the content's natural height, forcing overflow-or-scroll.
    const phone = Size(360, 480);

    Future<void> pumpPhone(WidgetTester tester, ValueChanged<Avatar> onPick) async {
      tester.view.physicalSize = phone;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(MaterialApp(
        home: AvatarSelectionScreen(onAvatarSelected: onPick),
      ));
      await tester.pumpAndSettle();
    }

    testWidgets('does not overflow', (tester) async {
      await pumpPhone(tester, (_) {});
      // A RenderFlex overflow throws during layout; testWidgets surfaces it as
      // a caught exception. None means the content scrolled instead.
      expect(tester.takeException(), isNull);
    });

    testWidgets('Confirm can be scrolled into view', (tester) async {
      await pumpPhone(tester, (_) {});

      final confirm = find.widgetWithText(ElevatedButton, 'Confirm');
      expect(confirm, findsOneWidget);
      // ensureVisible throws if the target cannot be scrolled into view, so
      // reaching the assertion below proves Confirm is reachable on a phone —
      // no tap, so this stays clear of the local ink-splash shader skew.
      await tester.ensureVisible(confirm);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('can select an avatar and confirm it', (tester) async {
      Avatar? picked;
      await pumpPhone(tester, (a) => picked = a);

      final ranger = find.text(predefinedAvatars[1].displayName);
      await tester.ensureVisible(ranger);
      await tester.pumpAndSettle();
      await tester.tap(ranger);
      await tester.pumpAndSettle();

      final confirm = find.widgetWithText(ElevatedButton, 'Confirm');
      await tester.ensureVisible(confirm);
      await tester.pumpAndSettle();
      await tester.tap(confirm);
      await tester.pumpAndSettle();

      expect(picked, equals(predefinedAvatars[1]));
    });
  });
}
