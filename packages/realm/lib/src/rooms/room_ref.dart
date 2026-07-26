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
final class LocalRoomRef extends RoomRef {
  /// References the local room [roomId].
  const LocalRoomRef(this.roomId);

  /// The referenced room.
  final RoomId roomId;
}

/// A room on another operator's instance. **Declared in v1, emitted only in v2.**
///
/// The type is *declared* in v1 so that every consumer's exhaustive `switch`
/// over [RoomRef] already carries an arm for it — which is exactly what lets v2
/// begin *emitting* it without breaking a single switch. But v1 must never
/// *construct* one, and the constructor enforces that by throwing
/// unconditionally.
///
/// **Why an unconditional `throw`, not an `assert`** (Kelvin + Tesla's catch): a
/// constructor `assert` is stripped from release and profile builds, so the
/// reservation would hold in tests and dev but silently evaporate exactly where
/// users run. A `throw` is a runtime law in every build mode. There is no
/// performance cost to guard against — constructing this in v1 is never a hot
/// path; it is never meant to happen at all.
///
/// **v2 activation is deferred with the rest of federation** and is NOT "a
/// downstream package edits this constructor" — that would be an open/closed
/// violation (Kelvin's catch). When federation lands, the engine itself
/// introduces the sanctioned mint path (a capability-token factory is the
/// likely shape: a private constructor plus a public factory that requires a
/// token only the federation subsystem can produce). Designing that mint is a
/// federation concern, so it waits; v1's only commitment is the guarantee below
/// — this type exists in the sealed family but cannot be constructed. There is
/// deliberately no mutable "federation active" flag: a flag was the very thing
/// forcing the release-strip hole, and deleting it removes the coupling instead
/// of guarding it.
final class FederatedRoomRef extends RoomRef {
  /// Always throws in v1 — see the class doc.
  FederatedRoomRef({required this.operatorUri, required this.roomId}) {
    throw UnsupportedError(
      'FederatedRoomRef is reserved for v2 federation and cannot be '
      'constructed in v1.',
    );
  }

  /// Base URI of the operator hosting [roomId].
  final Uri operatorUri;

  /// The referenced room, in the remote operator's id space.
  final RoomId roomId;
}
