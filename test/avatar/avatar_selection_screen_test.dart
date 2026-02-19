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
}
