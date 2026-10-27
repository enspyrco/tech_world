import 'package:cloud_firestore/cloud_firestore.dart';
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

    test('a non-Timestamp lastSeen does not throw — parses with null lastSeen',
        () async {
      // Regression: `as Timestamp?` would THROW on a non-null non-Timestamp
      // value, escaping tryParse and erroring the whole stream.
      final entry = PresenceEntry.tryParse('u1', {
        'userId': 'u1',
        'displayName': 'Ada',
        'avatarId': 'npc12',
        'currentRoomId': 'room-a',
        'lastSeen': 'definitely-not-a-timestamp',
      });
      expect(entry, isNotNull);
      expect(entry!.lastSeen, isNull);
      expect(entry.currentRoomId, 'room-a');
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

  group('heartbeat + TTL stamp', () {
    final t0 = DateTime.utc(2026, 10, 27, 12);

    test('enter stamps expireAt = clock + expireAfter', () async {
      final svc = PresenceService(firestore: firestore, clock: () => t0);
      await svc.enter(
          userId: 'u1', displayName: 'Ada', avatarId: 'npc12', roomId: 'r');

      final data = (await firestore.collection('presence').doc('u1').get())
          .data()!;
      expect((data['expireAt'] as Timestamp).toDate().toUtc(),
          t0.add(PresenceService.expireAfter));
    });

    test('heartbeat refreshes lastSeen + expireAt and nothing else', () async {
      var now = t0;
      final svc = PresenceService(firestore: firestore, clock: () => now);
      await svc.enter(
          userId: 'u1', displayName: 'Ada', avatarId: 'npc12', roomId: 'r');

      now = t0.add(const Duration(minutes: 5));
      await svc.heartbeat('u1');

      final data = (await firestore.collection('presence').doc('u1').get())
          .data()!;
      expect((data['expireAt'] as Timestamp).toDate().toUtc(),
          now.add(PresenceService.expireAfter));
      expect(data['lastSeen'], isA<Timestamp>());
      expect(data['currentRoomId'], 'r', reason: 'heartbeat must not move rooms');
      expect(data['displayName'], 'Ada');
    });

    test('a heartbeat after leave fails and does NOT resurrect the doc',
        () async {
      // The whole point of update-not-set: a tick racing leave()'s delete must
      // not recreate a ghost.
      await service.enter(
          userId: 'u1', displayName: 'Ada', avatarId: 'npc12', roomId: 'r');
      await service.leave('u1');

      await expectLater(service.heartbeat('u1'), throwsA(anything));
      final doc = await firestore.collection('presence').doc('u1').get();
      expect(doc.exists, isFalse);
    });
  });

  group('staleness', () {
    final now = DateTime.utc(2026, 10, 27, 12);

    PresenceEntry seenAt(DateTime? t) => PresenceEntry(
        userId: 'u',
        displayName: '',
        avatarId: '',
        currentRoomId: 'r',
        lastSeen: t);

    test('isFreshAt: inside the window is fresh, the boundary is fresh, past '
        'it is stale, and a pending (null) write is fresh', () {
      const w = PresenceService.staleAfter;
      expect(seenAt(now.subtract(const Duration(seconds: 1))).isFreshAt(now, w),
          isTrue);
      expect(seenAt(now.subtract(w)).isFreshAt(now, w), isTrue);
      expect(
          seenAt(now.subtract(w + const Duration(seconds: 1)))
              .isFreshAt(now, w),
          isFalse);
      expect(seenAt(null).isFreshAt(now, w), isTrue);
    });

    Future<void> putDoc(String id, DateTime lastSeen) =>
        firestore.collection('presence').doc(id).set({
          'userId': id,
          'displayName': id,
          'avatarId': 'npc12',
          'currentRoomId': 'room-a',
          'lastSeen': Timestamp.fromDate(lastSeen),
        });

    test('watchAll hides ghosts and keeps the living', () async {
      final svc = PresenceService(firestore: firestore, clock: () => now);
      await putDoc('alive', now.subtract(const Duration(seconds: 30)));
      await putDoc('ghost', now.subtract(const Duration(hours: 2)));

      final entries = await svc.watchAll().first;
      expect(entries.map((e) => e.userId), ['alive']);
    });

    test('a ghost vanishes on the recheck tick with NO Firestore event, and '
        'an unchanged tick does not re-emit', () async {
      var clock = now;
      final svc = PresenceService(firestore: firestore, clock: () => clock);
      await putDoc('u1', now);

      final emissions = <List<String>>[];
      final sub = svc
          .watchAll(recheckEvery: const Duration(milliseconds: 20))
          .listen((e) => emissions.add(e.map((x) => x.userId).toList()));

      await Future<void>.delayed(const Duration(milliseconds: 70));
      expect(emissions, [
        ['u1']
      ], reason: 'still fresh: ticks fired but nothing changed, so no re-emit');

      // Time passes; u1 stops heartbeating. Firestore says nothing.
      clock = now.add(PresenceService.staleAfter + const Duration(seconds: 1));
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(emissions.last, isEmpty, reason: 'the tick hid the ghost');
      expect(emissions.length, 2);

      await sub.cancel();
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
