import 'dart:math';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tech_world/flame/maps/game_map.dart';
import 'package:tech_world/rooms/room_service.dart';

/// Tests for the fork-on-save logic.
///
/// When a user saves a room, the app decides whether to update in place or
/// create a new room (fork). This mirrors the logic in `_MyAppState._saveRoom`:
///
/// ```
/// final isOwnedRoom = existingRoomId != null &&
///     existingRoomId.isNotEmpty &&
///     currentRoom != null &&
///     currentRoom.isOwner(userId);
/// ```
///
/// - Owner saves → update existing room
/// - Non-owner saves → create new room (fork)
/// - New room (no roomId) → create new room
void main() {
  group('Fork-on-save logic', () {
    late FakeFirebaseFirestore fakeFirestore;
    late RoomService service;

    const testMap = GameMap(
      id: 'test_map',
      name: 'Test Map',
      barriers: [Point(1, 2)],
      spawnPoint: Point(10, 15),
    );

    const updatedMap = GameMap(
      id: 'test_map',
      name: 'Updated Map',
      barriers: [Point(5, 5), Point(6, 6)],
      spawnPoint: Point(20, 20),
    );

    setUp(() {
      fakeFirestore = FakeFirebaseFirestore();
      service = RoomService(
        collection: fakeFirestore.collection('rooms'),
      );
    });

    test('owner saving updates existing room in place', () async {
      // Create a room owned by user-1.
      final room = await service.createRoom(
        name: 'My Room',
        ownerId: 'user-1',
        ownerDisplayName: 'Nick',
        map: testMap,
      );

      // Simulate the isOwnedRoom check.
      final isOwnedRoom = room.id.isNotEmpty && room.isOwner('user-1');
      expect(isOwnedRoom, isTrue);

      // Owner updates in place.
      await service.updateRoomMap(room.id, updatedMap);
      await service.updateRoomName(room.id, 'Updated Map');

      final fetched = await service.getRoom(room.id);
      expect(fetched!.name, equals('Updated Map'));
      expect(fetched.mapData.barriers, hasLength(2));
      expect(fetched.ownerId, equals('user-1'));

      // Verify no extra rooms were created.
      final allRooms = await service.listMyRooms('user-1');
      expect(allRooms, hasLength(1));
    });

    test('non-owner saving creates a new room (fork)', () async {
      // Create a room owned by user-1.
      final originalRoom = await service.createRoom(
        name: 'Original Room',
        ownerId: 'user-1',
        ownerDisplayName: 'Nick',
        map: testMap,
      );

      // user-2 tries to "save" — isOwnedRoom should be false.
      final isOwnedRoom =
          originalRoom.id.isNotEmpty && originalRoom.isOwner('user-2');
      expect(isOwnedRoom, isFalse);

      // Non-owner creates a new room instead of updating.
      final forkedRoom = await service.createRoom(
        name: 'My Fork',
        ownerId: 'user-2',
        ownerDisplayName: 'Alice',
        map: updatedMap,
      );

      // Original is untouched.
      final original = await service.getRoom(originalRoom.id);
      expect(original!.name, equals('Original Room'));
      expect(original.ownerId, equals('user-1'));
      expect(original.mapData.barriers, hasLength(1));

      // Fork is a separate room.
      expect(forkedRoom.id, isNot(equals(originalRoom.id)));
      expect(forkedRoom.ownerId, equals('user-2'));
      expect(forkedRoom.name, equals('My Fork'));
      expect(forkedRoom.mapData.barriers, hasLength(2));
    });

    test('saving with no roomId creates a new room', () async {
      // Simulate empty roomId (new room, not editing an existing one).
      const String? roomId = null;
      final isOwnedRoom = roomId != null && roomId.isNotEmpty;
      expect(isOwnedRoom, isFalse);

      final room = await service.createRoom(
        name: 'Brand New Room',
        ownerId: 'user-1',
        ownerDisplayName: 'Nick',
        map: testMap,
      );

      expect(room.id, isNotEmpty);
      expect(room.name, equals('Brand New Room'));
    });

    test('saving with empty roomId creates a new room', () async {
      // Simulate empty string roomId (transient room from "Create Room").
      const roomId = '';
      final isOwnedRoom = roomId.isNotEmpty;
      expect(isOwnedRoom, isFalse);
    });

    test('editor (non-owner with canEdit) still forks on save', () async {
      // Create a room and add user-2 as editor.
      final room = await service.createRoom(
        name: 'Shared Room',
        ownerId: 'user-1',
        ownerDisplayName: 'Nick',
        map: testMap,
      );
      await service.addEditor(room.id, 'user-2');

      final fetched = await service.getRoom(room.id);

      // Editor can edit (paint tools), but isOwner is false.
      expect(fetched!.canEdit('user-2'), isTrue);
      expect(fetched.isOwner('user-2'), isFalse);

      // So the fork-on-save check triggers a fork.
      final isOwnedRoom =
          fetched.id.isNotEmpty && fetched.isOwner('user-2');
      expect(isOwnedRoom, isFalse);
    });
  });
}
