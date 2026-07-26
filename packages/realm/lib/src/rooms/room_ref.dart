import '../ids.dart';

/// A reference to a room, local or (in v2) on another operator's instance.
///
/// **Both variants exist from v1 on purpose.** The sealed family IS the
/// contract surface: if [FederatedRoomRef] were absent in v1, adding it in v2
/// would break every consumer's exhaustive switch at upgrade time. Instead v1
/// reserves it as a *declared-but-never-emitted* variant — the type exists, no
/// v1 implementation constructs it, and v1 consumers must already carry a
/// [FederatedRoomRef] arm (canonically "should not occur in v1; assert or
/// skip"). v2 lights up emission without changing the sealed surface: no
/// breaking change, no migration note.
sealed class RoomRef {
  /// Creates a room reference.
  const RoomRef();
}

/// A room on this operator's instance. Emitted by v1 and v2 alike.
class LocalRoomRef extends RoomRef {
  /// References the local room [roomId].
  const LocalRoomRef(this.roomId);

  /// The referenced room.
  final RoomId roomId;
}

/// A room on another operator's instance. **Declared in v1, emitted only in v2.**
///
/// v1 implementations MUST NOT construct this. The assertion below gives
/// debug builds a loud failure on accidental construction; release-mode v1
/// builds rely on `realm_lints` rule (c), and until that ships, on cage-match
/// grep for `FederatedRoomRef(`.
class FederatedRoomRef extends RoomRef {
  /// References [roomId] hosted by the operator at [operatorUri].
  ///
  /// Throws in debug builds while federation is inactive, which is always in
  /// v1 — see the class doc.
  FederatedRoomRef({required this.operatorUri, required this.roomId})
      : assert(
          _federationActive,
          'FederatedRoomRef cannot be constructed in v1 — reserved but never '
          'emitted per the v1 federation constraints. If you see this in a v2 '
          'stack trace, the federation capability was not activated before '
          'construction.',
        );

  /// Base URI of the operator hosting [roomId].
  final Uri operatorUri;

  /// The referenced room, in the remote operator's id space.
  final RoomId roomId;
}

/// Whether cross-operator federation is active in this process.
///
/// v1 never flips this — it exists so the [FederatedRoomRef] assertion has
/// something to read, and so v2's `FederationGraphStore` gets a single,
/// greppable switch to flip at init rather than an `assert` the engine has to
/// delete.
///
/// Deliberately **library-private**: no consumer outside the engine can flip
/// it, so no consumer can talk itself past the v1 guard. v2's federation code
/// ships inside this library and flips it there.
///
/// Deliberately **not `const`**: a const `false` would let the compiler treat
/// the assertion as dead code, which is exactly the enforcement we want alive.
// ignore: prefer_final_fields
bool _federationActive = false;
