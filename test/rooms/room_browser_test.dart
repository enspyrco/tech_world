import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tech_world/flame/maps/game_map.dart';
import 'package:tech_world/rooms/presence_service.dart';
import 'package:tech_world/rooms/room_browser.dart';
import 'package:tech_world/rooms/room_data.dart';
import 'package:tech_world/rooms/room_service.dart';

const _room = RoomData(
  id: 'room-a',
  name: 'The Tavern',
  ownerId: 'owner-1',
  ownerDisplayName: 'Hostess',
  mapData: GameMap(id: 'm', name: 'M', barriers: []),
);

void main() {
  late FakeFirebaseFirestore firestore;
  late RoomService roomService;
  late PresenceService presenceService;

  setUp(() async {
    firestore = FakeFirebaseFirestore();
    // Seed one public room.
    await firestore.collection('rooms').doc(_room.id).set(_room.toFirestore());
    roomService = RoomService(collection: firestore.collection('rooms'));
    presenceService = PresenceService(firestore: firestore);
  });

  Future<void> pumpBrowser(WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(
      home: RoomBrowser(
        roomService: roomService,
        userId: 'viewer-1',
        presenceService: presenceService,
        onJoinRoom: (_) {},
        onCreateRoom: () {},
      ),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('shows no occupancy indicator for an empty room', (tester) async {
    await pumpBrowser(tester);

    expect(find.text('The Tavern'), findsOneWidget);
    expect(find.textContaining('here'), findsNothing);
  });

  testWidgets('renders occupant count and initial when users are present',
      (tester) async {
    await presenceService.enter(
      userId: 'u1',
      displayName: 'Ada',
      avatarId: 'npc12',
      roomId: 'room-a',
    );
    await presenceService.enter(
      userId: 'u2',
      displayName: 'Grace',
      avatarId: 'npc13',
      roomId: 'room-a',
    );

    await pumpBrowser(tester);

    expect(find.text('2 here'), findsOneWidget);
    // Initial circles for both occupants.
    expect(find.text('A'), findsOneWidget);
    expect(find.text('G'), findsOneWidget);
  });

  testWidgets('singular label for a single occupant', (tester) async {
    await presenceService.enter(
      userId: 'u1',
      displayName: 'Linus',
      avatarId: 'npc11',
      roomId: 'room-a',
    );

    await pumpBrowser(tester);

    expect(find.text('1 here'), findsOneWidget);
  });

  testWidgets('occupancy only attaches to the matching room', (tester) async {
    // Presence in a DIFFERENT room must not leak onto this card.
    await presenceService.enter(
      userId: 'u1',
      displayName: 'Ada',
      avatarId: 'npc12',
      roomId: 'some-other-room',
    );

    await pumpBrowser(tester);

    expect(find.textContaining('here'), findsNothing);
  });
}
