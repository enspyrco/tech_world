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
/// reconnect), [leave] on a graceful leave. The browser calls [watchAll] and
/// groups with [groupByRoom].
class PresenceService {
  PresenceService({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  static const _collection = 'presence';

  /// How often a connected client re-stamps its own presence document.
  ///
  /// Read by [RoomSession], which owns the timer — this class stays I/O only.
  static const heartbeatInterval = Duration(seconds: 60);

  /// How long a presence document is trusted without a refresh.
  ///
  /// Three heartbeats, so two may be missed — a GC pause, a backgrounded tab, a
  /// brief network drop — before a genuinely-present user blinks out of the
  /// foyer. Erring long is the right direction: a ghost that lingers three
  /// minutes is a smaller lie than a present player who keeps vanishing.
  static const presenceTtl = Duration(minutes: 3);

  CollectionReference<Map<String, dynamic>> get _presence =>
      _firestore.collection(_collection);

  /// Record that [userId] is now present in [roomId].
  ///
  /// Overwrites any prior presence doc for the user (moving rooms is just a new
  /// `currentRoomId`), and stamps `lastSeen` with the server clock. Safe to call
  /// again on reconnect — it is idempotent on the document key.
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
      'lastSeen': FieldValue.serverTimestamp(),
    });
  }

  /// Remove [userId]'s presence document — they have left the world (or moved
  /// back to the browser). Best-effort: a missing document is not an error.
  Future<void> leave(String userId) async {
    await _presence.doc(userId).delete();
  }

  /// Stream of every present user across all rooms. The browser subscribes once
  /// and groups client-side with [groupByRoom] — one stream feeds every card,
  /// rather than one listener per room.
  ///
  /// Entries staler than [presenceTtl] are dropped. Firestore has no
  /// `onDisconnect` hook, so an ungraceful exit — a force-quit, a closed lid, a
  /// dropped connection — leaves the document behind with nothing to remove it.
  /// Observed 2026-09-11: three ghosts still listed as "in the room" six hours
  /// after their clients died.
  ///
  /// Filtering here rather than in the browser so every consumer of this stream
  /// gets the same answer; a second reader that forgot to filter would show the
  /// ghosts again.
  ///
  /// This is a SWEEP, NOT A CURE. The documents are still written by clients
  /// and still outlive them; this only stops the foyer believing them. The
  /// authoritative fix is LiveKit's `participant_left` webhook driving a
  /// server-side delete, because LiveKit is the only party that actually knows
  /// who is connected — see [PresenceEntry]'s class comment and the tracker.
  ///
  /// [clock] is a test seam; production uses [DateTime.now].
  Stream<List<PresenceEntry>> watchAll({DateTime Function()? clock}) {
    final now = clock ?? DateTime.now;
    return _presence.snapshots().map((snapshot) => snapshot.docs
        .map((doc) => PresenceEntry.tryParse(doc.id, doc.data()))
        .whereType<PresenceEntry>()
        .where((entry) => isFresh(entry, now()))
        .toList());
  }

  /// Whether [entry] is recent enough to be believed at [now].
  ///
  /// A null [PresenceEntry.lastSeen] counts as FRESH. Firestore reports its own
  /// pending server timestamps as null until the write round-trips, so a user
  /// reading the foyer immediately after entering would otherwise watch
  /// themselves flicker out and back. Every document is written by [enter],
  /// which always stamps the field, so null means "in flight", never "ancient".
  ///
  /// Pure and static so the rule is testable without Firestore or a clock.
  ///
  /// CAVEAT: this compares a SERVER timestamp against a CLIENT clock. A device
  /// whose clock is badly wrong will mis-judge freshness in whichever direction
  /// it is skewed — a slow clock hides real players, a fast one keeps ghosts.
  /// [presenceTtl] is generous partly to absorb ordinary skew, but a
  /// server-side sweep would not have this failure mode at all.
  static bool isFresh(PresenceEntry entry, DateTime now) {
    final lastSeen = entry.lastSeen;
    if (lastSeen == null) return true;
    return now.difference(lastSeen) < presenceTtl;
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
