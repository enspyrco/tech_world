import 'dart:math';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tech_world/flame/maps/game_map.dart';
import 'package:tech_world/rooms/room_service.dart';

void main() {
  group('RoomService', () {
    late FakeFirebaseFirestore fakeFirestore;
    late RoomService service;

    const testMap = GameMap(
      id: 'test_map',
      name: 'Test Map',
      barriers: [Point(1, 2), Point(3, 4)],
      spawnPoint: Point(10, 15),
      terminals: [Point(5, 5)],
    );

    setUp(() {
      fakeFirestore = FakeFirebaseFirestore();
      service = RoomService(
        collection: fakeFirestore.collection('rooms'),
      );
    });

    group('createRoom', () {
      test('creates a room and returns it with Firestore ID', () async {
        final room = await service.createRoom(
          name: 'My Room',
          ownerId: 'user-123',
          ownerDisplayName: 'Nick',
          map: testMap,
        );

        expect(room.id, isNotEmpty);
        expect(room.name, equals('My Room'));
        expect(room.ownerId, equals('user-123'));
        expect(room.ownerDisplayName, equals('Nick'));
        expect(room.isPublic, isTrue);
        expect(room.mapData.barriers, hasLength(2));
      });

      test('creates a room in Firestore', () async {
        final room = await service.createRoom(
          name: 'Persistent Room',
          ownerId: 'user-456',
          ownerDisplayName: 'Alice',
          map: testMap,
        );

        final doc =
            await fakeFirestore.collection('rooms').doc(room.id).get();
        expect(doc.exists, isTrue);
        expect(doc.data()?['name'], equals('Persistent Room'));
        expect(doc.data()?['ownerId'], equals('user-456'));
      });
    });

    group('getRoom', () {
      test('returns room when it exists', () async {
        final created = await service.createRoom(
          name: 'Existing Room',
          ownerId: 'user-123',
          ownerDisplayName: 'Nick',
          map: testMap,
        );

        final fetched = await service.getRoom(created.id);

        expect(fetched, isNotNull);
        expect(fetched!.name, equals('Existing Room'));
        expect(fetched.mapData.barriers, hasLength(2));
      });

      test('returns null when room does not exist', () async {
        final fetched = await service.getRoom('non-existent-id');
        expect(fetched, isNull);
      });
    });

    group('updateRoomMap', () {
      test('updates map data without changing other fields', () async {
        final created = await service.createRoom(
          name: 'Map Update Test',
          ownerId: 'user-123',
          ownerDisplayName: 'Nick',
          map: testMap,
        );

        const updatedMap = GameMap(
          id: 'doesnt_matter',
          name: 'Ignored Name',
          barriers: [Point(10, 10)],
          spawnPoint: Point(20, 20),
        );

        await service.updateRoomMap(created.id, updatedMap);

        final fetched = await service.getRoom(created.id);
        expect(fetched!.name, equals('Map Update Test')); // Name unchanged.
        expect(fetched.mapData.barriers, hasLength(1));
        expect(fetched.mapData.spawnPoint, equals(const Point(20, 20)));
      });
    });

    group('updateRoomName', () {
      test('updates the room name', () async {
        final created = await service.createRoom(
          name: 'Old Name',
          ownerId: 'user-123',
          ownerDisplayName: 'Nick',
          map: testMap,
        );

        await service.updateRoomName(created.id, 'New Name');

        final fetched = await service.getRoom(created.id);
        expect(fetched!.name, equals('New Name'));
      });
    });

    group('deleteRoom', () {
      test('deletes the room', () async {
        final created = await service.createRoom(
          name: 'To Delete',
          ownerId: 'user-123',
          ownerDisplayName: 'Nick',
          map: testMap,
        );

        await service.deleteRoom(created.id);

        final fetched = await service.getRoom(created.id);
        expect(fetched, isNull);
      });
    });

    group('listPublicRooms', () {
      test('returns only public rooms', () async {
        await service.createRoom(
          name: 'Public Room',
          ownerId: 'user-1',
          ownerDisplayName: 'Alice',
          map: testMap,
          isPublic: true,
        );
        await service.createRoom(
          name: 'Private Room',
          ownerId: 'user-2',
          ownerDisplayName: 'Bob',
          map: testMap,
          isPublic: false,
        );

        final publicRooms = await service.listPublicRooms();
        expect(publicRooms, hasLength(1));
        expect(publicRooms.first.name, equals('Public Room'));
      });
    });

    group('listMyRooms', () {
      test('returns only rooms owned by user', () async {
        await service.createRoom(
          name: 'My Room',
          ownerId: 'user-1',
          ownerDisplayName: 'Alice',
          map: testMap,
        );
        await service.createRoom(
          name: 'Someone Else Room',
          ownerId: 'user-2',
          ownerDisplayName: 'Bob',
          map: testMap,
        );

        final myRooms = await service.listMyRooms('user-1');
        expect(myRooms, hasLength(1));
        expect(myRooms.first.name, equals('My Room'));
      });
    });

    group('editor management', () {
      test('addEditor adds user to editor list', () async {
        final created = await service.createRoom(
          name: 'Editor Test',
          ownerId: 'user-owner',
          ownerDisplayName: 'Nick',
          map: testMap,
        );

        await service.addEditor(created.id, 'user-editor');

        final fetched = await service.getRoom(created.id);
        expect(fetched!.editorIds, contains('user-editor'));
      });

      test('removeEditor removes user from editor list', () async {
        final created = await service.createRoom(
          name: 'Editor Test',
          ownerId: 'user-owner',
          ownerDisplayName: 'Nick',
          map: testMap,
        );

        await service.addEditor(created.id, 'user-editor');
        await service.removeEditor(created.id, 'user-editor');

        final fetched = await service.getRoom(created.id);
        expect(fetched!.editorIds, isNot(contains('user-editor')));
      });
    });

    group('setPublic', () {
      test('toggles visibility', () async {
        final created = await service.createRoom(
          name: 'Visibility Test',
          ownerId: 'user-1',
          ownerDisplayName: 'Nick',
          map: testMap,
          isPublic: true,
        );

        await service.setPublic(created.id, isPublic: false);

        final fetched = await service.getRoom(created.id);
        expect(fetched!.isPublic, isFalse);
      });
    });
  });
}
