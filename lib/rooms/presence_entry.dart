import 'package:cloud_firestore/cloud_firestore.dart';

/// One participant's presence in the shared world — "who is where right now".
///
/// Persisted as a single document at `/presence/{userId}`, written when a user
/// connects to a room (see [PresenceService.enter]) and deleted on a graceful
/// leave. Read in aggregate by the room browser to show occupancy *before* a
/// user joins — the foyer/common-room moment where you see who is gathered.
///
/// Staleness: an ungraceful disconnect (tab close, crash, network drop) leaves
/// a ghost document behind, because Firestore — unlike Realtime Database — has
/// no `onDisconnect` hook. Ghosts are handled in two layers, neither of which
/// needs a server:
///
/// 1. **Hidden** — a connected session refreshes [lastSeen] every
///    [PresenceService.heartbeatInterval]; readers drop any entry not seen
///    within [PresenceService.staleAfter] ([isFreshAt]). A ghost leaves the
///    foyer within ~3 minutes.
/// 2. **Deleted** — every write also stamps `expireAt`, which a Firestore TTL
///    policy (`firestore.indexes.json`) uses to garbage-collect the doc after
///    the heartbeats stop. TTL deletion is lazy (typically within 24h), which
///    is why hiding is the reader's job, not TTL's.
///
/// History: the previous reaper was the `livekitWebhook` Cloud Function; it
/// stopped when LiveKit's server-wide webhook was removed (~2026-09-07 — it
/// also shipped other products' room events here) and was deleted 2026-10-27.
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

  /// Server timestamp of the last presence write (enter or heartbeat). Null
  /// until the server round trip resolves.
  final DateTime? lastSeen;

  /// Whether this entry should be shown at [now]: seen within [staleAfter].
  ///
  /// A null [lastSeen] counts as fresh — it is a write still in flight, not a
  /// ghost. Readers compare a SERVER timestamp against their LOCAL clock, so a
  /// reader whose clock runs more than [staleAfter] fast hides everyone; the
  /// window is generous for that reason.
  bool isFreshAt(DateTime now, Duration staleAfter) {
    final seen = lastSeen;
    return seen == null || now.difference(seen) <= staleAfter;
  }

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
