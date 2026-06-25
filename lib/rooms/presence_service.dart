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
  Stream<List<PresenceEntry>> watchAll() {
    return _presence.snapshots().map((snapshot) => snapshot.docs
        .map((doc) => PresenceEntry.tryParse(doc.id, doc.data()))
        .whereType<PresenceEntry>()
        .toList());
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
