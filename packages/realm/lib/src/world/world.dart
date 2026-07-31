import '../auth/auth_provider.dart';
import '../ids.dart';
import '../rooms/room_config_store.dart';
import 'room_preview.dart';

/// One room's worth of meaning.
///
/// The engine knows that rooms exist, that users join them, that presence
/// happens, that voice flows, that data channels carry typed messages and that
/// blobs live somewhere. Worlds bring everything else — doors, spellbooks,
/// repositories, bodies.
///
/// **This is an `abstract interface class`, not a base class, and that is
/// forced rather than chosen.** Tech World already does
/// `extends flame.World with TapCallbacks`; Dart's single inheritance means it
/// cannot extend a second base class. Making the engine's world an interface
/// that classes `implements` is the only structurally valid path — and it has
/// the happy consequence that a world may sit on Flame, on a raw
/// `CustomPainter`, on a 3D stack, or on nothing visual at all.
///
/// ## Contract versioning
///
/// **Never add an abstract method to this interface after v1.0.** Doing so
/// breaks every implementing world at compile time. The additive-evolution
/// pattern is a new *sibling* interface that worlds opt into:
///
/// ```dart
/// abstract interface class WorldFederationHooks {
///   Future<void> onPortalTransit(PortalTransit transit);
/// }
///
/// class TechWorld extends flame.World with TapCallbacks
///     implements World, WorldFederationHooks { /* … */ }
/// ```
///
/// v1 worlds that don't implement the sibling keep compiling against a v2
/// engine; the engine checks `world is WorldFederationHooks` before
/// dispatching. This rule applies to every engine interface, not just this one.
abstract interface class World {
  /// The room this world instance is hosting.
  RoomId get roomId;

  /// The record this world was instantiated from.
  RoomDescriptor get descriptor;

  /// Called once when the local user enters the room.
  ///
  /// Implementations subscribe to their data channels, register listeners and
  /// initialise world-specific state here.
  Future<void> onEnter();

  /// Called when a peer's participant connects.
  void onPeerJoin(RealmUser peer);

  /// Called when a peer leaves. The local user remains.
  void onPeerLeave(UserId peerId);

  /// Called when the local user leaves, for any reason.
  Future<void> onLeave(LeaveReason reason);

  /// A renderer-neutral snapshot of this room for display in a room-listing
  /// surface such as a foyer.
  ///
  /// Returns `null` if this world shouldn't appear in room listings — a foyer
  /// world returns `null`, since a foyer doesn't list itself.
  ///
  /// **No Flutter types in the return value.** The consuming renderer wraps the
  /// result in its own rendering stack, which is what keeps the engine portable across
  /// rendering stacks — Flame, `CustomPainter`, 3D, or a text-mode bot.
  Future<RoomPreview?> previewSnapshot();
}

/// Why the local user left a room.
///
/// An audience-bounded sealed surface: adding a value IS a breaking change for
/// consumers' exhaustive switches, and lands as a minor-version bump with a
/// migration note.
enum LeaveReason {
  /// The user chose to leave.
  userLeft('user_left'),

  /// The connection dropped.
  disconnect('disconnect'),

  /// The user stepped through a portal to a federated room.
  ///
  /// **Reserved for v2.** Declared in v1 so that lighting up federation later
  /// isn't a sealed-add break — v1 consumers must already carry an arm for it,
  /// canonically "should not occur in v1".
  portalTransit('portal_transit');

  const LeaveReason(this.wire);

  /// The on-the-wire representation, stable across renames of the Dart value.
  final String wire;

  /// Parses [wire] strictly, throwing [ArgumentError] on an unknown string.
  ///
  /// Ships alongside [tryParse] as the same "two doors at the boundary" pair as
  /// [RoomVisibility] — a strict door for callers that want a loud failure on
  /// a malformed wire value, a lenient one for callers that choose their own
  /// fallback.
  static LeaveReason parse(String wire) => values.firstWhere(
        (v) => v.wire == wire,
        orElse: () =>
            throw ArgumentError.value(wire, 'wire', 'Unknown LeaveReason'),
      );

  /// Parses [wire], returning `null` on an unknown string.
  static LeaveReason? tryParse(String wire) {
    for (final v in values) {
      if (v.wire == wire) return v;
    }
    return null;
  }
}
