import '../auth/auth_provider.dart';
import '../ids.dart';

/// Watching who is in a room — including rooms you have not joined.
///
/// Powers the foyer's cross-room presence display and, eventually,
/// federation's cross-instance presence layer.
///
/// ## Why this is engine, not world
///
/// Presence-of-others is foundational substrate. Every world wants it. Building
/// it once here prevents N presence implementations per world — and, more
/// importantly, prevents N different projection-by-audience policies, where any
/// one bug becomes a privacy leak.
///
/// ## The PII boundary
///
/// Presence carries user ids, display names and join times — all PII. A naive
/// cross-room watch API would broadcast that to anyone who can name a room.
/// This interface uses **audience-narrowed return types** so the boundary is
/// enforced by the compiler rather than by implementation discipline:
/// in-room watchers get [FullProjection], foyer watchers get
/// [PublicProjection], and a buggy implementation cannot emit the wrong one
/// because the return type forbids it.
///
/// **No-leak rule**: LiveKit's `RemoteParticipant`, `Track` and
/// `TrackPublication` must not cross this boundary.
abstract interface class PresenceService {
  /// Watches full-fidelity presence for a room [viewer] is inside.
  ///
  /// Implementations MUST check membership — this succeeds only if [viewer] is
  /// currently present in [roomId].
  ///
  /// **Snapshot semantics, not delta**: each emitted `Set` is the *complete*
  /// current participant set, not a diff. Because equality is on [userId], a
  /// consumer folding deltas would silently drop field updates (a changed
  /// `displayName`), so the contract is a full set per event — the implementer
  /// re-emits the whole set on any change. Applies to both watch methods.
  Stream<Set<FullProjection>> watchInRoom(RoomId roomId, RealmUser viewer);

  /// Watches low-fidelity presence for a room [viewer] is NOT inside.
  ///
  /// Succeeds only for rooms whose visibility is public; unlisted and private
  /// rooms refuse, so a foyer cannot enumerate them at all.
  Stream<Set<PublicProjection>> watchFromFoyer(RoomId roomId, RealmUser viewer);
}

/// A peer's presence, at whatever fidelity the audience is entitled to.
///
/// **Carries no data of its own, on purpose.** Every PII-bearing field lives on
/// a specific subtype, so the base type cannot become a covert leak channel —
/// a field added here would land on every projection by default. Future fields
/// go on the subtype authorised to expose them.
///
/// An audience-bounded sealed surface: adding a variant IS a breaking change
/// for consumers' exhaustive switches. The leaves are `final` so the closure is
/// total — `sealed` alone stops another package from adding a NEW direct
/// subtype, but not from *subclassing a leaf* (`class Leaky extends
/// PublicProjection { String email; }`) and smuggling in-room PII onto the
/// foyer type while still satisfying `Stream<Set<PublicProjection>>`. `sealed`
/// root + `final` leaves is the Dart 3 idiom for a genuinely closed value
/// hierarchy (Tesla's catch).
sealed class PeerPresence {
  /// Creates a presence projection.
  const PeerPresence();
}

/// Full-fidelity presence. **In-room visibility only.**
///
/// Equality is on [userId] — participants are unique per room, and the
/// `Set` semantics of [PresenceService.watchInRoom] depend on it.
final class FullProjection extends PeerPresence {
  /// Creates a full-fidelity projection.
  const FullProjection({
    required this.userId,
    required this.joinedAt,
    this.displayName,
    this.avatarUrl,
    this.worldMetadata = const {},
  });

  /// The peer's id. **PII** — in-room only.
  final UserId userId;

  /// The peer's name. **PII** — in-room only.
  final String? displayName;

  /// The peer's avatar, if any.
  final Uri? avatarUrl;

  /// When the peer joined. **PII (timing)** — in-room only, and deliberately
  /// absent from [PublicProjection].
  final DateTime joinedAt;

  /// World-specific presence data, opaque to the engine and parsed by the
  /// world that wrote it.
  final Map<String, Object?> worldMetadata;

  @override
  bool operator ==(Object other) =>
      other is FullProjection && other.userId == userId;

  @override
  int get hashCode => userId.hashCode;
}

/// Low-fidelity presence, safe to show to someone outside the room.
///
/// Its job is "is anyone there? how many? render placeholders" — not activity
/// surveillance. Equality is on [userIdHash].
final class PublicProjection extends PeerPresence {
  /// Creates a public projection.
  const PublicProjection({required this.userIdHash, this.opaqueAvatarRef});

  /// A per-room hash of the peer's id: `SHA256(roomId || userId)[:8]`.
  ///
  /// Salted with the room id so the same user appears as a different value in
  /// every room — cross-room identification via the public projection is not
  /// possible.
  ///
  /// **Collision posture is deliberate.** Eight bytes is a 64-bit per-room
  /// space, so two co-present users could in principle collide. The foyer
  /// accepts that: a longer hash would give an attacker a near-certain join
  /// key into other rooms, and the collision rate inside one room is negligible
  /// at any plausible room size. Unlinkability beats precision here.
  final String userIdHash;

  /// An opaque avatar reference the foyer may render, or `null` if the user
  /// opted out.
  ///
  /// [userIdHash] is always emitted even when this is `null`, because the
  /// foyer needs *some* token to distinguish "three people inside" from
  /// "nobody inside".
  final Uri? opaqueAvatarRef;

  // Deliberately no `joinedAt`. Timing is in-room PII: exposing it cross-room
  // would let any foyer observer build a longitudinal profile of who was where,
  // when.

  @override
  bool operator ==(Object other) =>
      other is PublicProjection && other.userIdHash == userIdHash;

  @override
  int get hashCode => userIdHash.hashCode;
}
