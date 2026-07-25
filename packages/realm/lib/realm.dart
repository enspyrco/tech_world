/// Realm — a multiplayer worldbuilding engine.
///
/// Engine package skeleton (migration step 2: workspace scaffold). The engine
/// interfaces — `AuthProvider`, `RoomConfigStore`, `StorageProvider`,
/// `LiveKitTokenEndpoint`, `PresenceService`, and the `World` interface — land
/// in migration step 3. See `DESIGN.md` for the architectural pin.
library;

/// Marker constant until the engine interfaces land. Consumed by the
/// reference `examples/livekit-token-server/` member purely to pin the
/// dependency direction (server depends on engine, never the reverse).
const realmEngineVersion = '0.0.1';
