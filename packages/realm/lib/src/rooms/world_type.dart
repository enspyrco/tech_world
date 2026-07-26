import '../world/world.dart';
import 'room_config_store.dart';

/// Identifier for a kind of world. Open set, registry-validated.
///
/// External worlds can register their own type, but a value can only be
/// constructed by validating a wire string against a [WorldTypeRegistry] — so
/// a typo can never become a live `worldType` on a room document.
///
/// [WorldTypeId.parse] is deliberately NOT a static factory that consults a
/// global. Every parse site threads an explicit registry from the engine entry
/// point, which matters for:
/// - **test isolation** — parallel tests construct disjoint registries;
/// - **hot reload** — no leftover registrations survive a restart;
/// - **multi-tenancy** — different operators register different world types.
///
/// **The brand is a parse aid, not a capability.** Being an `extension type`, it
/// is erased at runtime and forgeable by cast (`'tech_world' as WorldTypeId`),
/// and it carries no registry watermark — an id parsed against one registry will
/// dispatch on another that shares the wire string. So every trust-boundary read
/// path must re-`parse` the wire against its own registry and never trust a cast
/// or a threaded value as proof of registration.
extension type const WorldTypeId._(String value) {
  /// Constructs from a wire string, validating against [registry].
  ///
  /// Throws [WorldTypeNotRegistered] if [wire] is not registered.
  factory WorldTypeId.parse(String wire, WorldTypeRegistry registry) {
    if (!registry.isRegistered(wire)) {
      throw WorldTypeNotRegistered(wire);
    }
    return WorldTypeId._(wire);
  }
}

/// Thrown when a wire string does not name a world type in the registry.
class WorldTypeNotRegistered extends ArgumentError {
  /// Creates the error for an unregistered [wire] string.
  WorldTypeNotRegistered(String wire)
      : super.value(
          wire,
          'worldType',
          'Not registered with this WorldTypeRegistry',
        );
}

/// Maps world-type wire strings to the factories that build them.
///
/// Each engine instance owns one registry; each world registers its type id
/// and factory at the engine's startup hook. The engine looks worlds up
/// through the registry instance rather than a hardcoded switch, which is what
/// lets a world ship from outside this repo.
///
/// Duplicate registration of the same wire string throws by default. Test
/// setups that deliberately swap a registration pass `allowOverride: true`, so
/// an accidental double-register in production code stays loud.
class WorldTypeRegistry {
  /// Creates an empty registry.
  WorldTypeRegistry();

  final Map<String, World Function(RoomDescriptor)> _registered = {};

  /// Registers [factory] under the [wire] string and returns its branded id.
  ///
  /// Returning the [WorldTypeId] means a caller that has just registered a type
  /// holds a validated id without threading [wire] back through
  /// [WorldTypeId.parse] — one door, no chance for the re-parsed string to
  /// drift from the registered one (Tesla's catch).
  ///
  /// Throws [StateError] if [wire] is already registered and [allowOverride]
  /// is false.
  WorldTypeId register(
    String wire,
    World Function(RoomDescriptor) factory, {
    bool allowOverride = false,
  }) {
    if (!allowOverride && _registered.containsKey(wire)) {
      throw StateError('WorldType "$wire" is already registered. '
          'Pass allowOverride: true to replace.');
    }
    _registered[wire] = factory;
    return WorldTypeId._(wire);
  }

  /// Whether [wire] names a registered world type.
  bool isRegistered(String wire) => _registered.containsKey(wire);

  /// Instantiates the world described by [desc].
  ///
  /// Throws [WorldTypeNotRegistered] if the descriptor's world type is not
  /// registered here. Callers should either branch on [isRegistered] first or
  /// catch and fall back — a room whose world type this build doesn't know is
  /// a legitimate runtime state, not a bug.
  World instantiate(RoomDescriptor desc) {
    final factory = _registered[desc.worldType.value];
    if (factory == null) throw WorldTypeNotRegistered(desc.worldType.value);
    return factory(desc);
  }
}
