/// Realm — a multiplayer worldbuilding engine.
///
/// Realm hosts named rooms; each room instantiates a [World]. The engine
/// provides the shared substrate — identity, room records, presence, voice
/// transport, blob storage — so that a world can be just its own vocabulary.
///
/// This library is the engine's entire public surface. It declares interfaces
/// and value types only: **no implementations, and no dependency on any
/// backend.** Firebase-backed implementations live in `realm_firebase`; other
/// backends are somebody else's package. See `DESIGN.md` for the architectural
/// pin and the nine-step migration plan this is step three of.
///
/// ## The no-leak rule
///
/// No backend-specific type may cross an engine interface. The engine defines
/// [RealmUser], [RoomDescriptor], [BlobRef], [PeerPresence] and friends;
/// implementations translate to and from their backend's vocabulary. A
/// `DocumentSnapshot` or a `firebase_auth.User` appearing in this library is a
/// bug, and eventually a CI failure.
///
/// ## Two evolution surfaces, never confused
///
/// **Audience-bounded sealed surfaces** — [LeaveReason], [FoyerVisibility],
/// [PeerPresence], [RoomPreview], [RoomRef]. Their variant sets live entirely
/// within the engine's audience contract. Adding a variant is a **breaking
/// change** for consumers' exhaustive switches; each addition ships as a
/// minor-version bump with a migration note.
///
/// **Plugin-extension interfaces** — [AuthMethod], [TokenEndpointAuthStrategy],
/// [PreviewShape], and the registry-validated branded ids ([WorldTypeId],
/// [StorageBackendId], [AuthProviderId]). These are interfaces, not sealed.
/// Adding an implementation is non-breaking by design: no changelog entry, no
/// version bump. Consumers branch non-exhaustively.
///
/// Re-sealing anything in the second group defeats the extension point it
/// exists to be.
library;

export 'src/auth/auth_provider.dart';
export 'src/ids.dart';
export 'src/livekit/livekit_token_endpoint.dart';
export 'src/presence/presence_service.dart';
export 'src/rooms/room_config_store.dart';
export 'src/rooms/room_ref.dart';
export 'src/rooms/world_type.dart';
export 'src/storage/storage_provider.dart';
export 'src/world/room_preview.dart';
export 'src/world/world.dart';

/// The engine's version, as a value consumers can print.
///
/// Also load-bearing structurally: `examples/livekit-token-server/` imports it
/// to pin the dependency direction — the server depends on the engine, and the
/// engine never depends on the server. That asymmetry is one of the two
/// artifacts that keep secret-bearing auth strategies out of the client bundle
/// (see [TokenEndpointAuthStrategy]).
const realmEngineVersion = '0.0.1';
