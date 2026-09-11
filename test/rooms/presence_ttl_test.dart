// The foyer must stop believing presence documents whose owner is gone.
//
// Firestore has no onDisconnect hook, so an ungraceful exit — force-quit,
// closed lid, dropped wifi — leaves the document behind with nothing to remove
// it. Observed 2026-09-11: three ghosts still listed as "in the room" SIX HOURS
// after their clients died, one of them a named account.
//
// This suite pins the read-side sweep. It is not a fix for the mirror itself:
// the documents are still written by clients and still outlive them. See
// PresenceEntry's class comment for the authoritative cure (a LiveKit
// participant_left webhook driving a server-side delete).
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tech_world/rooms/presence_entry.dart';
import 'package:tech_world/rooms/presence_service.dart';

PresenceEntry _entry({required String id, DateTime? lastSeen}) => PresenceEntry(
      userId: id,
      displayName: id == 'guest' ? '' : id,
      avatarId: 'npc12',
      currentRoomId: 'room-a',
      lastSeen: lastSeen,
    );

void main() {
  final now = DateTime.utc(2026, 9, 11, 23, 30);
  final ttl = PresenceService.presenceTtl;

  group('isFresh — the rule', () {
    test('a document refreshed just now is believed', () {
      expect(
        PresenceService.isFresh(
            _entry(id: 'u1', lastSeen: now.subtract(const Duration(seconds: 1))),
            now),
        isTrue,
      );
    });

    test('a document older than the TTL is a ghost', () {
      expect(
        PresenceService.isFresh(
            _entry(id: 'u1', lastSeen: now.subtract(ttl * 2)), now),
        isFalse,
      );
    });

    test('the six-hour case actually observed', () {
      expect(
        PresenceService.isFresh(
            _entry(id: 'u1', lastSeen: now.subtract(const Duration(hours: 6))),
            now),
        isFalse,
        reason: 'this is the exact ghost Nick saw at 17:30 and again at 23:30',
      );
    });

    test('null lastSeen is treated as FRESH — a pending server timestamp', () {
      // Firestore reports its own unresolved serverTimestamp as null until the
      // write round-trips. Treating that as stale would make a user watch
      // themselves flicker out of the foyer immediately after entering.
      expect(PresenceService.isFresh(_entry(id: 'u1'), now), isTrue);
    });

    test('the boundary is exclusive: exactly TTL old is already a ghost', () {
      expect(
        PresenceService.isFresh(
            _entry(id: 'u1', lastSeen: now.subtract(ttl)), now),
        isFalse,
      );
      expect(
        PresenceService.isFresh(
            _entry(id: 'u1', lastSeen: now.subtract(ttl - const Duration(seconds: 1))),
            now),
        isTrue,
      );
    });

    test('a clock running backwards does not reap everyone', () {
      // Server timestamp vs client clock: a device whose clock is BEHIND the
      // server sees a negative age. That must read as fresh, not as a ghost —
      // otherwise skew empties the foyer.
      expect(
        PresenceService.isFresh(
            _entry(id: 'u1', lastSeen: now.add(const Duration(minutes: 10))),
            now),
        isTrue,
      );
    });

    test('the TTL is a whole number of heartbeats, and more than one', () {
      // If the TTL were <= the heartbeat interval, a single missed beat would
      // blink a present player out of the foyer.
      final beats = ttl.inMilliseconds / PresenceService.heartbeatInterval.inMilliseconds;
      expect(beats, greaterThanOrEqualTo(2),
          reason: 'must tolerate at least one missed heartbeat');
      expect(beats, beats.roundToDouble());
    });
  });

  group('watchAll — the sweep applied', () {
    late FakeFirebaseFirestore firestore;
    late PresenceService service;

    setUp(() {
      firestore = FakeFirebaseFirestore();
      service = PresenceService(firestore: firestore);
    });

    Future<void> seed(String id, DateTime lastSeen) =>
        firestore.collection('presence').doc(id).set({
          'userId': id,
          'displayName': id,
          'avatarId': 'npc12',
          'currentRoomId': 'room-a',
          'lastSeen': Timestamp.fromDate(lastSeen),
        });

    test('ghosts are excluded and the living are kept', () async {
      await seed('ghost', now.subtract(const Duration(hours: 6)));
      await seed('alive', now.subtract(const Duration(seconds: 5)));

      final entries = await service.watchAll(clock: () => now).first;

      // BOTH assertions are load-bearing. A filter that excluded EVERYTHING
      // would satisfy the first on its own — this is the must-fail arm.
      expect(entries.map((e) => e.userId), isNot(contains('ghost')));
      expect(entries.map((e) => e.userId), contains('alive'),
          reason: 'a sweep that empties the foyer is not a fix');
    });

    test('the observed configuration: three ghosts, nobody actually there',
        () async {
      // One named account plus two nameless guests — exactly what the foyer
      // showed. groupByRoom must report the room as empty, not as occupied by
      // three.
      await seed('N', now.subtract(const Duration(hours: 6)));
      await seed('guest1', now.subtract(const Duration(hours: 6)));
      await seed('guest2', now.subtract(const Duration(hours: 9)));

      final entries = await service.watchAll(clock: () => now).first;
      expect(entries, isEmpty);
      expect(PresenceService.groupByRoom(entries)['room-a'], isNull);
    });

    test('null arm: with no documents at all the stream yields empty',
        () async {
      // Distinguishes "the filter works" from "the stream is broken".
      final entries = await service.watchAll(clock: () => now).first;
      expect(entries, isEmpty);
    });
  });
}
