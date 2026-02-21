import 'dart:math';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tech_world/flame/maps/game_map.dart';
import 'package:tech_world/rooms/room_data.dart';

void main() {
  group('RoomData', () {
    const testMap = GameMap(
      id: 'test_map',
      name: 'Test Map',
      barriers: [Point(1, 2), Point(3, 4)],
      spawnPoint: Point(10, 15),
      terminals: [Point(5, 5)],
    );

    test('canEdit returns true for owner', () {
      const room = RoomData(
        id: 'room-1',
        name: 'Test Room',
        ownerId: 'owner-uid',
        ownerDisplayName: 'Nick',
        mapData: testMap,
      );
      expect(room.canEdit('owner-uid'), isTrue);
    });

    test('canEdit returns true for editor', () {
      const room = RoomData(
        id: 'room-1',
        name: 'Test Room',
        ownerId: 'owner-uid',
        ownerDisplayName: 'Nick',
        editorIds: ['editor-1', 'editor-2'],
        mapData: testMap,
      );
      expect(room.canEdit('editor-1'), isTrue);
      expect(room.canEdit('editor-2'), isTrue);
    });

    test('canEdit returns false for non-owner non-editor', () {
      const room = RoomData(
        id: 'room-1',
        name: 'Test Room',
        ownerId: 'owner-uid',
        ownerDisplayName: 'Nick',
        editorIds: ['editor-1'],
        mapData: testMap,
      );
      expect(room.canEdit('random-user'), isFalse);
    });

    test('isOwner returns true for owner', () {
      const room = RoomData(
        id: 'room-1',
        name: 'Test Room',
        ownerId: 'owner-uid',
        ownerDisplayName: 'Nick',
        mapData: testMap,
      );
      expect(room.isOwner('owner-uid'), isTrue);
      expect(room.isOwner('someone-else'), isFalse);
    });

    test('copyWith preserves unchanged fields', () {
      const original = RoomData(
        id: 'room-1',
        name: 'Original',
        ownerId: 'owner-uid',
        ownerDisplayName: 'Nick',
        editorIds: ['editor-1'],
        isPublic: true,
        mapData: testMap,
      );

      final copy = original.copyWith(name: 'Updated');

      expect(copy.id, equals('room-1'));
      expect(copy.name, equals('Updated'));
      expect(copy.ownerId, equals('owner-uid'));
      expect(copy.editorIds, equals(['editor-1']));
      expect(copy.isPublic, isTrue);
    });

    test('toFirestore produces correct map', () {
      const room = RoomData(
        id: 'room-1',
        name: 'Test Room',
        ownerId: 'owner-uid',
        ownerDisplayName: 'Nick',
        editorIds: ['editor-1'],
        isPublic: true,
        mapData: testMap,
      );

      final json = room.toFirestore();

      expect(json['name'], equals('Test Room'));
      expect(json['ownerId'], equals('owner-uid'));
      expect(json['ownerDisplayName'], equals('Nick'));
      expect(json['editorIds'], equals(['editor-1']));
      expect(json['isPublic'], isTrue);
      expect(json['mapData'], isA<Map<String, dynamic>>());
      // mapData should NOT contain id or name (those are room-level).
      expect((json['mapData'] as Map).containsKey('id'), isFalse);
      expect((json['mapData'] as Map).containsKey('name'), isFalse);
      // But should contain spawnPoint and barriers.
      expect(json['mapData']['spawnPoint'], equals({'x': 10, 'y': 15}));
      expect(json['mapData']['barriers'], hasLength(2));
    });

    test('fromFirestore round-trips correctly', () async {
      final fakeFirestore = FakeFirebaseFirestore();
      const room = RoomData(
        id: '', // Will be set by Firestore doc ID.
        name: 'Test Room',
        ownerId: 'owner-uid',
        ownerDisplayName: 'Nick',
        editorIds: ['editor-1'],
        isPublic: false,
        mapData: testMap,
      );

      final data = room.toFirestore();
      await fakeFirestore.collection('rooms').doc('room-abc').set(data);
      final doc =
          await fakeFirestore.collection('rooms').doc('room-abc').get();

      final restored = RoomData.fromFirestore(doc);

      expect(restored.id, equals('room-abc'));
      expect(restored.name, equals('Test Room'));
      expect(restored.ownerId, equals('owner-uid'));
      expect(restored.ownerDisplayName, equals('Nick'));
      expect(restored.editorIds, equals(['editor-1']));
      expect(restored.isPublic, isFalse);
      expect(restored.mapData.barriers, hasLength(2));
      expect(restored.mapData.spawnPoint, equals(const Point(10, 15)));
      expect(restored.mapData.terminals, hasLength(1));
    });
  });
}
