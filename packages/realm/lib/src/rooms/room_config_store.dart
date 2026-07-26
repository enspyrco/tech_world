import '../auth/auth_provider.dart';
import '../ids.dart';
import 'world_type.dart';

/// Reads and writes the room records a Realm instance hosts.
///
/// **No-leak rule**: no backend type may cross this boundary. Implementations
/// translate `DocumentSnapshot`, `QuerySnapshot`, `Timestamp` and Firestore
/// references into the engine types below.
abstract interface class RoomConfigStore {
  /// Lists rooms the caller is allowed to see.
  ///
  /// [ownedBy] filters to one owner; [minVisibility] filters to rooms at or
  /// above a visibility level. `null` means no filter on that axis.
  ///
  /// Authorization is the implementation's job: this returning a room is an
  /// assertion that the caller may see it.
  Future<List<RoomDescriptor>> listRooms({
    UserId? ownedBy,
    FoyerVisibility? minVisibility,
  });

  /// Fetches one room, or `null` if it does not exist or is not visible.
  Future<RoomDescriptor?> getRoom(RoomId roomId);

  /// Watches one room for configuration changes.
  ///
  /// Emits on every change to the room record — rename, visibility change,
  /// editor added, world config patched.
  Stream<RoomDescriptor> watchRoom(RoomId roomId);

  /// Creates a room from [spec] and returns it with its assigned [RoomId].
  Future<RoomDescriptor> createRoom(NewRoomSpec spec);

  /// Applies a partial update to a room's world config.
  ///
  /// [patch] is merged into the existing [RoomDescriptor.worldConfig]. The
  /// engine does not interpret its contents — see [RoomDescriptor.worldConfig].
  Future<void> updateRoomConfig(RoomId roomId, Map<String, Object?> patch);
}

/// A room record, as the engine understands one.
class RoomDescriptor {
  /// Creates a room descriptor.
  const RoomDescriptor({
    required this.id,
    required this.displayName,
    required this.worldType,
    required this.foyerVisibility,
    this.worldConfig = const {},
    this.owner,
    this.editorIds = const [],
  });

  /// This room's identifier.
  final RoomId id;

  /// Human-readable room name.
  final String displayName;

  /// Which world this room instantiates. Registry-validated.
  final WorldTypeId worldType;

  /// How visible this room is from the foyer.
  final FoyerVisibility foyerVisibility;

  /// Per-world configuration, **opaque to the engine**.
  ///
  /// The engine stores and returns this map without interpreting a single key.
  /// Each world owns a `parseConfig(Map) → TypedConfig` method and validates
  /// at room creation — the same shape as parsing a wire string into a typed
  /// id at a boundary.
  ///
  /// This is the trapdoor that keeps world vocabulary (tilemaps, challenge
  /// sets, body layouts) out of the engine's contract.
  final Map<String, Object?> worldConfig;

  /// The room's owner, if the implementation resolves owner identity.
  final RealmUser? owner;

  /// Users granted edit rights beyond the owner.
  final List<UserId> editorIds;

  // NOTE: federation's `connectedTo` field is deliberately NOT here in v1.
  // Reserving the type (`RoomRef`) is cheap; reserving a field on the public
  // listing contract is not — `listRooms()` returns RoomDescriptor, so any
  // field here is already part of the v1 listing surface and already subject
  // to v1 authorization decisions. v2 federation introduces `connectedTo` as
  // an additive minor-version change alongside a `FederationGraphStore`
  // interface that owns its read/write/authorization.
}

/// The parameters needed to create a room.
///
/// Distinct from [RoomDescriptor] because a room being created has no [RoomId]
/// yet — the store assigns one — and names its owner by [UserId] rather than
/// carrying a resolved [RealmUser] projection.
class NewRoomSpec {
  /// Describes a room to create.
  const NewRoomSpec({
    required this.displayName,
    required this.worldType,
    required this.ownerId,
    this.worldConfig = const {},
    this.foyerVisibility = FoyerVisibility.private,
    this.editorIds = const [],
  });

  /// Human-readable room name.
  final String displayName;

  /// Which world the new room instantiates.
  final WorldTypeId worldType;

  /// Who owns the new room.
  final UserId ownerId;

  /// Initial per-world configuration. Opaque to the engine.
  final Map<String, Object?> worldConfig;

  /// Initial visibility.
  ///
  /// Defaults to [FoyerVisibility.private] — a room becomes visible by an
  /// explicit act, never by forgetting to pass an argument.
  final FoyerVisibility foyerVisibility;

  /// Users granted edit rights at creation.
  final List<UserId> editorIds;
}

/// How visible a room is from the foyer.
///
/// An audience-bounded sealed surface: adding a value here IS a breaking
/// change for consumers' exhaustive switches, and lands as a minor-version
/// bump with a migration note.
enum FoyerVisibility {
  /// Listed in the foyer; anyone may watch its public presence projection.
  public('public'),

  /// Not listed, but reachable by anyone holding the room id.
  unlisted('unlisted'),

  /// Not listed and not reachable without an explicit grant.
  private('private');

  const FoyerVisibility(this.wire);

  /// The on-the-wire representation, stable across renames of the Dart value.
  final String wire;

  /// Parses [wire] strictly.
  ///
  /// Throws [ArgumentError] on an unknown string rather than silently
  /// downgrading to [private] — a typo in the wire format should surface
  /// loudly, not quietly change a room's visibility. Use this when you want a
  /// non-nullable result and an explicit exception on miss.
  static FoyerVisibility parse(String wire) => values.firstWhere(
        (v) => v.wire == wire,
        orElse: () => throw ArgumentError.value(
          wire,
          'wire',
          'Unknown FoyerVisibility',
        ),
      );

  /// Parses [wire], returning `null` on an unknown string.
  ///
  /// Idiomatic at trust boundaries (backend reads, room-metadata reads) where
  /// the caller wants to choose its own fallback policy without a try/catch:
  /// `FoyerVisibility.tryParse(wire) ?? FoyerVisibility.private`.
  ///
  /// Both doors ship together on purpose — throwing and try-parsing are
  /// different jobs, and forcing one caller to emulate the other is where
  /// silent visibility downgrades come from.
  static FoyerVisibility? tryParse(String wire) {
    for (final v in values) {
      if (v.wire == wire) return v;
    }
    return null;
  }
}
