import 'dart:math';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tech_world/auth/user_profile_service.dart';
import 'package:tech_world/flame/maps/game_map.dart';
import 'package:tech_world/rooms/manage_editors_dialog.dart';
import 'package:tech_world/rooms/room_data.dart';
import 'package:tech_world/rooms/room_service.dart';

/// Minimal [GameMap] for testing.
GameMap _blankMap() => const GameMap(
      id: 'test',
      name: 'Test',
      barriers: [],
      spawnPoint: Point(0, 0),
      terminals: [],
    );

/// Build the dialog inside a [MaterialApp] for testing.
Widget _buildDialog({
  required RoomData room,
  required RoomService roomService,
  required UserProfileService userProfileService,
}) {
  return MaterialApp(
    home: Scaffold(
      body: Builder(
        builder: (context) => ElevatedButton(
          onPressed: () => showDialog<void>(
            context: context,
            builder: (_) => ManageEditorsDialog(
              room: room,
              roomService: roomService,
              userProfileService: userProfileService,
            ),
          ),
          child: const Text('Open'),
        ),
      ),
    ),
  );
}

void main() {
  group('ManageEditorsDialog', () {
    late FakeFirebaseFirestore fakeFirestore;
    late RoomService roomService;
    late UserProfileService userProfileService;

    setUp(() {
      fakeFirestore = FakeFirebaseFirestore();
      roomService = RoomService(
        collection: fakeFirestore.collection('rooms'),
      );
      userProfileService = UserProfileService(
        collection: fakeFirestore.collection('users'),
      );
    });

    testWidgets('shows current editors on open', (tester) async {
      // Seed editor profiles.
      await fakeFirestore.collection('users').doc('editor-1').set({
        'displayName': 'Alice',
        'displayNameLower': 'alice',
      });
      await fakeFirestore.collection('users').doc('editor-2').set({
        'displayName': 'Bob',
        'displayNameLower': 'bob',
      });

      final room = RoomData(
        id: 'room-1',
        name: 'Test Room',
        ownerId: 'owner-1',
        ownerDisplayName: 'Owner',
        editorIds: const ['editor-1', 'editor-2'],
        mapData: _blankMap(),
      );

      await tester.pumpWidget(_buildDialog(
        room: room,
        roomService: roomService,
        userProfileService: userProfileService,
      ));

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(find.text('Manage Editors'), findsOneWidget);
      expect(find.text('Alice'), findsOneWidget);
      expect(find.text('Bob'), findsOneWidget);
      expect(find.text('Editors (2)'), findsOneWidget);
    });

    testWidgets('shows empty state when no editors', (tester) async {
      final room = RoomData(
        id: 'room-1',
        name: 'Test Room',
        ownerId: 'owner-1',
        ownerDisplayName: 'Owner',
        mapData: _blankMap(),
      );

      await tester.pumpWidget(_buildDialog(
        room: room,
        roomService: roomService,
        userProfileService: userProfileService,
      ));

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(find.text('Editors (0)'), findsOneWidget);
      expect(
        find.text('No editors yet — search below to add people.'),
        findsOneWidget,
      );
    });

    testWidgets('remove editor calls removeEditor and updates UI',
        (tester) async {
      // Create room in Firestore so removeEditor can operate.
      await fakeFirestore.collection('rooms').doc('room-1').set({
        'name': 'Test Room',
        'ownerId': 'owner-1',
        'ownerDisplayName': 'Owner',
        'editorIds': ['editor-1'],
        'isPublic': true,
        'mapData': {},
      });
      await fakeFirestore.collection('users').doc('editor-1').set({
        'displayName': 'Alice',
        'displayNameLower': 'alice',
      });

      final room = RoomData(
        id: 'room-1',
        name: 'Test Room',
        ownerId: 'owner-1',
        ownerDisplayName: 'Owner',
        editorIds: const ['editor-1'],
        mapData: _blankMap(),
      );

      await tester.pumpWidget(_buildDialog(
        room: room,
        roomService: roomService,
        userProfileService: userProfileService,
      ));

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(find.text('Alice'), findsOneWidget);

      // Tap the remove button.
      await tester.tap(find.byIcon(Icons.remove_circle_outline));
      await tester.pumpAndSettle();

      // Alice should be gone.
      expect(find.text('Alice'), findsNothing);
      expect(find.text('Editors (0)'), findsOneWidget);

      // Verify Firestore was updated.
      final doc = await fakeFirestore.collection('rooms').doc('room-1').get();
      expect(doc.data()?['editorIds'], isEmpty);
    });

    testWidgets('search and add editor', (tester) async {
      // Create room in Firestore.
      await fakeFirestore.collection('rooms').doc('room-1').set({
        'name': 'Test Room',
        'ownerId': 'owner-1',
        'ownerDisplayName': 'Owner',
        'editorIds': [],
        'isPublic': true,
        'mapData': {},
      });
      // Seed a searchable user.
      await fakeFirestore.collection('users').doc('user-charlie').set({
        'displayName': 'Charlie',
        'displayNameLower': 'charlie',
      });

      final room = RoomData(
        id: 'room-1',
        name: 'Test Room',
        ownerId: 'owner-1',
        ownerDisplayName: 'Owner',
        mapData: _blankMap(),
      );

      await tester.pumpWidget(_buildDialog(
        room: room,
        roomService: roomService,
        userProfileService: userProfileService,
      ));

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      // Search for "char".
      await tester.enterText(find.byType(TextField), 'char');
      // Wait for debounce + Firestore query.
      await tester.pumpAndSettle(const Duration(milliseconds: 500));

      expect(find.text('Charlie'), findsOneWidget);

      // Tap the add button.
      await tester.tap(find.byIcon(Icons.add_circle_outline));
      await tester.pumpAndSettle();

      // Charlie should now be in the editors list.
      expect(find.text('Editors (1)'), findsOneWidget);

      // Verify Firestore was updated.
      final doc = await fakeFirestore.collection('rooms').doc('room-1').get();
      expect(doc.data()?['editorIds'], contains('user-charlie'));
    });

    testWidgets('search excludes owner and existing editors', (tester) async {
      // Seed users including the owner and an existing editor.
      await fakeFirestore.collection('users').doc('owner-1').set({
        'displayName': 'Owen Owner',
        'displayNameLower': 'owen owner',
      });
      await fakeFirestore.collection('users').doc('editor-1').set({
        'displayName': 'Oscar Editor',
        'displayNameLower': 'oscar editor',
      });
      await fakeFirestore.collection('users').doc('user-olivia').set({
        'displayName': 'Olivia',
        'displayNameLower': 'olivia',
      });

      final room = RoomData(
        id: 'room-1',
        name: 'Test Room',
        ownerId: 'owner-1',
        ownerDisplayName: 'Owen Owner',
        editorIds: const ['editor-1'],
        mapData: _blankMap(),
      );

      await tester.pumpWidget(_buildDialog(
        room: room,
        roomService: roomService,
        userProfileService: userProfileService,
      ));

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      // Search for "o" — should match Owen, Oscar, and Olivia,
      // but only Olivia should appear in results.
      await tester.enterText(find.byType(TextField), 'o');
      await tester.pumpAndSettle(const Duration(milliseconds: 500));

      // Olivia should appear in search results (with add button).
      expect(find.byIcon(Icons.add_circle_outline), findsOneWidget);
      expect(find.text('Olivia'), findsOneWidget);
    });

    testWidgets('close button dismisses dialog', (tester) async {
      final room = RoomData(
        id: 'room-1',
        name: 'Test Room',
        ownerId: 'owner-1',
        ownerDisplayName: 'Owner',
        mapData: _blankMap(),
      );

      await tester.pumpWidget(_buildDialog(
        room: room,
        roomService: roomService,
        userProfileService: userProfileService,
      ));

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(find.byType(ManageEditorsDialog), findsOneWidget);

      await tester.tap(find.byIcon(Icons.close));
      await tester.pumpAndSettle();

      expect(find.byType(ManageEditorsDialog), findsNothing);
    });
  });
}
