import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:tech_world/rooms/presence_entry.dart';

/// Reads and writes the shared-world presence layer in Firestore.
///
/// Presence answers "who is in each room right now" so the room browser can
/// show occupancy before a user joins. It rides the existing Firestore
/// room-lifecycle bus (the same place room documents and deletion live) rather
/// than introducing a new transport.
///
/// Lifecycle wiring lives in [RoomSession]: [enter] on a successful connect (and
/// reconnect), [heartbeat] every [heartbeatInterval] while connected, [leave] on
/// a graceful leave. The browser calls [watchAll] (which hides stale entries)
/// and groups with [groupByRoom]. See [PresenceEntry] for how ghosts are
/// hidden and then garbage-collected.
class PresenceService {
  PresenceService({FirebaseFirestore? firestore, DateTime Function()? clock})
      : _firestore = firestore ?? FirebaseFirestore.instance,
        _now = clock ?? DateTime.now;

  final FirebaseFirestore _firestore;
  final DateTime Function() _now;

  /// How often a connected session refreshes its `lastSeen`.
  static const heartbeatInterval = Duration(seconds: 60);

  /// An entry not seen for this long is a ghost and is hidden by [watchAll].
  /// Three missed heartbeats — tolerates a slow tick or a brief offline blip.
  static const staleAfter = Duration(minutes: 3);

  /// How far ahead `expireAt` is stamped. The TTL policy deletes the doc once
  /// it passes, so this is "how long a ghost lingers in storage" — never what
  /// readers see. Must stay inside the window `firestore.rules` accepts.
  static const expireAfter = Duration(hours: 1);

  static const _collection = 'presence';

  CollectionReference<Map<String, dynamic>> get _presence =>
      _firestore.collection(_collection);

  /// Record that [userId] is now present in [roomId].
  ///
  /// Overwrites any prior presence doc for the user (moving rooms is just a new
  /// `currentRoomId`), stamps `lastSeen` with the server clock and `expireAt`
  /// for TTL. Safe to call again on reconnect — idempotent on the document key.
  Future<void> enter({
    required String userId,
    required String displayName,
    required String avatarId,
    required String roomId,
  }) async {
    final entry = PresenceEntry(
      userId: userId,
      displayName: displayName,
      avatarId: avatarId,
      currentRoomId: roomId,
    );
    await _presence.doc(userId).set({
      ...entry.toFirestore(),
      ..._freshnessStamp(),
    });
  }

  /// Refresh [userId]'s `lastSeen` and `expireAt` without touching anything else.
  ///
  /// Uses `update`, not `set`, ON PURPOSE: a heartbeat that lands after [leave]
  /// deleted the doc fails (not-found) instead of resurrecting a ghost. Callers
  /// treat failure as best-effort.
  Future<void> heartbeat(String userId) =>
      _presence.doc(userId).update(_freshnessStamp());

  Map<String, Object> _freshnessStamp() => {
        'lastSeen': FieldValue.serverTimestamp(),
        'expireAt': Timestamp.fromDate(_now().add(expireAfter)),
      };

  /// Remove [userId]'s presence document — they have left the world (or moved
  /// back to the browser). Best-effort: a missing document is not an error.
  Future<void> leave(String userId) async {
    await _presence.doc(userId).delete();
  }

  /// Stream of every present user across all rooms, with ghosts hidden. The
  /// browser subscribes once and groups client-side with [groupByRoom] — one
  /// stream feeds every card, rather than one listener per room.
  ///
  /// Freshness is re-checked every [recheckEvery] as well as on each snapshot:
  /// a ghost produces no Firestore event when it goes stale, so without the
  /// tick it would only vanish when someone ELSE's presence changed. A tick
  /// only emits when the visible set actually changed.
  Stream<List<PresenceEntry>> watchAll({
    Duration recheckEvery = const Duration(seconds: 30),
  }) {
    late final StreamController<List<PresenceEntry>> controller;
    StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? snapshotSub;
    Timer? recheck;
    var all = const <PresenceEntry>[];
    List<PresenceEntry>? lastEmitted;

    List<PresenceEntry> visible() =>
        all.where((e) => e.isFreshAt(_now(), staleAfter)).toList();

    void emit({required bool onlyIfChanged}) {
      final next = visible();
      if (onlyIfChanged && _sameUsers(lastEmitted, next)) return;
      lastEmitted = next;
      controller.add(next);
    }

    controller = StreamController<List<PresenceEntry>>(
      onListen: () {
        snapshotSub = _presence.snapshots().listen(
          (snapshot) {
            all = snapshot.docs
                .map((doc) => PresenceEntry.tryParse(doc.id, doc.data()))
                .whereType<PresenceEntry>()
                .toList();
            emit(onlyIfChanged: false);
          },
          onError: controller.addError,
        );
        recheck = Timer.periodic(
            recheckEvery, (_) => emit(onlyIfChanged: true));
      },
      onCancel: () async {
        recheck?.cancel();
        await snapshotSub?.cancel();
      },
    );
    return controller.stream;
  }

  static bool _sameUsers(List<PresenceEntry>? a, List<PresenceEntry> b) {
    if (a == null || a.length != b.length) return false;
    final ids = {for (final e in a) e.userId};
    return b.every((e) => ids.contains(e.userId));
  }

  /// Group a flat presence list by room id. Pure function — no I/O — so the
  /// foyer's core logic is unit-testable without a database.
  static Map<String, List<PresenceEntry>> groupByRoom(
      List<PresenceEntry> entries) {
    final grouped = <String, List<PresenceEntry>>{};
    for (final entry in entries) {
      (grouped[entry.currentRoomId] ??= []).add(entry);
    }
    return grouped;
  }
}
