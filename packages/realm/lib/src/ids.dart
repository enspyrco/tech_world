/// Branded identifier types shared across the engine contract.
///
/// These are `extension type` declarations — zero-cost wrappers over [String]
/// that are distinct types to the analyzer. Passing a [UserId] where a
/// [RoomId] is expected is a compile error, but neither costs an allocation at
/// runtime.
///
/// The engine deliberately does NOT interpret the contents of either. Meaning
/// lives in the implementation that minted the value.
library;

/// Identifier for a room.
///
/// Globally unique (UUID-shaped, not `<org>:<slug>`) so that cross-instance
/// federation can collide-resist later. See the "Federation, deferred" section
/// of `DESIGN.md`.
extension type const RoomId(String value) {}

/// Identifier for a user.
///
/// Opaque to the engine; meaning lives in the `AuthProvider` that minted it.
/// Two different `AuthProvider` implementations may mint colliding values —
/// the engine makes no uniqueness guarantee across providers, and neither
/// should any consumer.
extension type const UserId(String value) {}
