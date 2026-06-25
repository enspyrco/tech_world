import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tech_world/rooms/presence_entry.dart';
import 'package:tech_world/rooms/presence_service.dart';

void main() {
  late FakeFirebaseFirestore firestore;
  late PresenceService service;

  setUp(() {
    firestore = FakeFirebaseFirestore();
    service = PresenceService(firestore: firestore);
  });

  group('PresenceService.enter', () {
    test('writes a presence doc keyed by userId with the right fields',
        () async {
      await service.enter(
        userId: 'u1',
        displayName: 'Ada',
        avatarId: 'npc12',
        roomId: 'room-a',
      );

      final doc = await firestore.collection('presence').doc('u1').get();
      expect(doc.exists, isTrue);
      final data = doc.data()!;
      expect(data['userId'], 'u1');
      expect(data['displayName'], 'Ada');
      expect(data['avatarId'], 'npc12');
      expect(data['currentRoomId'], 'room-a');
      expect(data['lastSeen'], isNotNull, reason: 'server timestamp stamped');
    });

    test('is idempotent on the doc key — re-entering overwrites currentRoomId',
        () async {
      await service.enter(
        userId: 'u1',
        displayName: 'Ada',
        avatarId: 'npc12',
        roomId: 'room-a',
      );
      await service.enter(
        userId: 'u1',
        displayName: 'Ada',
        avatarId: 'npc12',
        roomId: 'room-b',
      );

      final snap = await firestore.collection('presence').get();
      expect(snap.docs.length, 1, reason: 'one user => one doc');
      expect(snap.docs.single.data()['currentRoomId'], 'room-b');
    });
  });

  group('PresenceService.leave', () {
    test('deletes the user\'s presence doc', () async {
      await service.enter(
        userId: 'u1',
        displayName: 'Ada',
        avatarId: 'npc12',
        roomId: 'room-a',
      );
      await service.leave('u1');

      final doc = await firestore.collection('presence').doc('u1').get();
      expect(doc.exists, isFalse);
    });

    test('is a no-op (no throw) when the doc does not exist', () async {
      await expectLater(service.leave('ghost'), completes);
    });
  });

  group('PresenceService.watchAll', () {
    test('emits parsed entries and reacts to add/remove', () async {
      final emissions = <List<PresenceEntry>>[];
      final sub = service.watchAll().listen(emissions.add);

      await service.enter(
        userId: 'u1',
        displayName: 'Ada',
        avatarId: 'npc12',
        roomId: 'room-a',
      );
      await service.enter(
        userId: 'u2',
        displayName: 'Grace',
        avatarId: 'npc13',
        roomId: 'room-a',
      );
      await service.leave('u1');
      // Let the stream settle.
      await Future<void>.delayed(Duration.zero);

      final last = emissions.last;
      expect(last.map((e) => e.userId), ['u2']);
      expect(last.single.displayName, 'Grace');
      expect(last.single.currentRoomId, 'room-a');

      await sub.cancel();
    });

    test('drops malformed docs without crashing the stream', () async {
      // A doc missing currentRoomId is unparseable and must be skipped.
      await firestore
          .collection('presence')
          .doc('bad')
          .set({'displayName': 'No Room'});
      await firestore.collection('presence').doc('u1').set({
        'userId': 'u1',
        'displayName': 'Ada',
        'avatarId': 'npc12',
        'currentRoomId': 'room-a',
      });

      final entries = await service.watchAll().first;
      expect(entries.map((e) => e.userId), ['u1'],
          reason: 'malformed doc dropped, valid one kept');
    });
  });

  group('PresenceService.groupByRoom', () {
    test('buckets entries by currentRoomId', () {
      final entries = [
        const PresenceEntry(
            userId: 'u1',
            displayName: 'Ada',
            avatarId: 'npc12',
            currentRoomId: 'room-a'),
        const PresenceEntry(
            userId: 'u2',
            displayName: 'Grace',
            avatarId: 'npc13',
            currentRoomId: 'room-a'),
        const PresenceEntry(
            userId: 'u3',
            displayName: 'Linus',
            avatarId: 'npc11',
            currentRoomId: 'room-b'),
      ];

      final grouped = PresenceService.groupByRoom(entries);
      expect(grouped.keys.toSet(), {'room-a', 'room-b'});
      expect(grouped['room-a']!.map((e) => e.userId), ['u1', 'u2']);
      expect(grouped['room-b']!.map((e) => e.userId), ['u3']);
    });

    test('returns an empty map for no entries', () {
      expect(PresenceService.groupByRoom([]), isEmpty);
    });
  });
}
