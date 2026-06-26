import 'package:cloud_firestore/cloud_firestore.dart';

/// One participant's presence in the shared world — "who is where right now".
///
/// Persisted as a single document at `/presence/{userId}`, written when a user
/// connects to a room (see [PresenceService.enter]) and deleted on a graceful
/// leave. Read in aggregate by the room browser to show occupancy *before* a
/// user joins — the foyer/common-room moment where you see who is gathered.
///
/// NOTE on staleness: an ungraceful disconnect (tab close, crash, network
/// drop) leaves a ghost document behind, because Firestore — unlike Realtime
/// Database — has no `onDisconnect` hook. The authoritative cure is a LiveKit
/// `participant_left` webhook driving a Cloud Function cleanup (LiveKit is the
/// real source of truth for connection state). Until that lands, [lastSeen] is
/// stored so a future heartbeat/TTL sweep can reap ghosts.
class PresenceEntry {
  const PresenceEntry({
    required this.userId,
    required this.displayName,
    required this.avatarId,
    required this.currentRoomId,
    this.lastSeen,
  });

  /// Firebase UID — also the document key under `/presence`.
  final String userId;

  /// Denormalized display name so the browser renders without a profile lookup.
  final String displayName;

  /// The user's chosen avatar id (see `predefinedAvatars`). May be a value this
  /// client doesn't recognise if the set diverges across versions; consumers
  /// fall back to the default avatar when [avatarById] returns null.
  final String avatarId;

  /// The Firestore room document id the user is currently connected to.
  final String currentRoomId;

  /// Server timestamp of the last presence write. Null until the server round
  /// trip resolves. Stored for future ghost-reaping; not yet used for filtering
  /// (without a heartbeat it only marks join time, so filtering on it would
  /// wrongly drop long-present users).
  final DateTime? lastSeen;

  /// Firestore field map. `lastSeen` is written as a server timestamp by
  /// [PresenceService], not here, so it is intentionally omitted.
  Map<String, dynamic> toFirestore() => {
        'userId': userId,
        'displayName': displayName,
        'avatarId': avatarId,
        'currentRoomId': currentRoomId,
      };

  /// Parse a presence document. Returns null when required fields are missing or
  /// the wrong type — a malformed doc is dropped, never crashes the stream
  /// (same defensive-parse discipline as the chat wire seam).
  static PresenceEntry? tryParse(String docId, Map<String, dynamic>? data) {
    if (data == null) return null;
    final displayName = data['displayName'];
    final avatarId = data['avatarId'];
    final currentRoomId = data['currentRoomId'];
    if (currentRoomId is! String || currentRoomId.isEmpty) return null;
    // Guard with `is`, NOT `as Timestamp?`: a rules-legal doc with a non-null
    // non-Timestamp lastSeen (e.g. lastSeen: 'bad') makes `as Timestamp?` THROW
    // rather than yield null — and that throw escapes tryParse and errors the
    // whole browser stream. Same `as`-cast wire-seam teardown class as #364/#366.
    final rawLastSeen = data['lastSeen'];
    return PresenceEntry(
      userId: docId,
      displayName: displayName is String ? displayName : '',
      avatarId: avatarId is String ? avatarId : '',
      currentRoomId: currentRoomId,
      lastSeen: rawLastSeen is Timestamp ? rawLastSeen.toDate() : null,
    );
  }
}
