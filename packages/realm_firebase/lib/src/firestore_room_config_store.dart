import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:realm/realm.dart';

/// Firestore implementation of [RoomConfigStore].
///
/// Maps the live `rooms` collection ↔ engine [RoomDescriptor]. **No-leak**: the
/// public surface accepts and returns only engine value types; Firestore's
/// `DocumentSnapshot`, `QuerySnapshot`, `Timestamp` and `FieldValue` never
/// cross the boundary. (The injected `CollectionReference` is a DI seam, the
/// same convention [FirebaseStorageProvider] uses for `FirebaseStorage`.)
///
/// ## Schema mapping (tech-world-era Firestore)
///
/// Engine metadata maps to named top-level fields (`name` →
/// [RoomDescriptor.displayName], plus `ownerId`, `ownerDisplayName`,
/// `editorIds`, `isPublic`, `worldType`). **Every other key in the document is
/// the opaque [RoomDescriptor.worldConfig]** — copied through verbatim without
/// interpretation, so a tilemap (`mapData`), a `mapVersion`, or any future
/// world-authored key rides along and this plugin never depends on `tech_world`.
///
/// ## Visibility: `unlisted` is this backend's ceiling
///
/// The engine's [RoomVisibility] is three-state, but the live schema stores a
/// two-state `isPublic` bool that controls *listing only*, not
/// reachability-by-id. The honest mapping is therefore `true ↔ public`,
/// `false ↔ unlisted`. **[RoomVisibility.private] is deliberately unsupported
/// here**: this backend cannot gate reachability without a Firestore
/// security-rules change, and returning or accepting `private` while anyone
/// holding the id can still join would make the interface lie. [createRoom]
/// throws on `private` rather than silently downgrading it.
///
/// ## `getRoom` is a pure read
///
/// Unlike `tech_world`'s `RoomData.fromFirestore` (which self-heals renames and
/// wall styles by *writing during the read*), this store never writes during a
/// read. Those migrations relocate to the step-5 metadata-update door.
class FirestoreRoomConfigStore implements RoomConfigStore {
  /// Creates a store over [collection] (defaults to the `rooms` collection).
  ///
  /// [worldTypeRegistry] validates each document's `worldType` wire string on
  /// read — the brand is forgeable and carries no registry watermark, so a
  /// stored value is re-`parse`d against this registry rather than trusted.
  /// [defaultWorldType] is used for legacy documents that carry no `worldType`
  /// field (every live room today is implicitly `tech_world`).
  FirestoreRoomConfigStore({
    required WorldTypeRegistry worldTypeRegistry,
    CollectionReference<Map<String, dynamic>>? collection,
    String defaultWorldType = 'tech_world',
  })  : _registry = worldTypeRegistry,
        _defaultWorldType = defaultWorldType,
        _collection =
            collection ?? FirebaseFirestore.instance.collection('rooms');

  final WorldTypeRegistry _registry;
  final String _defaultWorldType;
  final CollectionReference<Map<String, dynamic>> _collection;

  /// Keys the engine owns. Every other document key is opaque `worldConfig`.
  static const _engineKeys = {
    'name',
    'ownerId',
    'ownerDisplayName',
    'editorIds',
    'isPublic',
    'worldType',
    'createdAt',
    'updatedAt',
  };

  @override
  Future<List<RoomDescriptor>> listRooms({
    UserId? ownedBy,
    RoomVisibility? minVisibility,
  }) async {
    Query<Map<String, dynamic>> query = _collection;
    if (ownedBy != null) {
      query = query.where('ownerId', isEqualTo: ownedBy.value);
    }
    // Two-state backend: only `public` (rank 3) is expressible as a filter
    // (`isPublic == true`). `unlisted` (rank 2) means public + unlisted = every
    // room, so it needs no filter; `private` cannot exist in this backend.
    // Per-caller authorization (who may see a given room) is enforced by
    // Firestore security rules server-side, not re-implemented here.
    if (minVisibility != null &&
        minVisibility.isAtLeast(RoomVisibility.public)) {
      query = query.where('isPublic', isEqualTo: true);
    }
    final snap = await query.get();
    return snap.docs.map(_toDescriptor).toList();
  }

  @override
  Future<RoomDescriptor?> getRoom(RoomId roomId) async {
    final doc = await _collection.doc(roomId.value).get();
    if (!doc.exists || doc.data() == null) return null;
    return _toDescriptor(doc);
  }

  @override
  Stream<RoomDescriptor> watchRoom(RoomId roomId) => _collection
      .doc(roomId.value)
      .snapshots()
      .where((doc) => doc.exists && doc.data() != null)
      .map(_toDescriptor);

  @override
  Future<RoomDescriptor> createRoom(NewRoomSpec spec) async {
    final data = <String, dynamic>{
      'name': spec.displayName,
      'ownerId': spec.ownerId.value,
      'editorIds': spec.editorIds.map((e) => e.value).toList(),
      'isPublic': _isPublicFor(spec.visibility),
      'worldType': spec.worldType.value,
      ...spec.worldConfig, // opaque world keys, stored at top level
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    };
    final ref = await _collection.add(data);
    return RoomDescriptor(
      id: RoomId(ref.id),
      displayName: spec.displayName,
      worldType: spec.worldType,
      visibility: spec.visibility,
      ownerId: spec.ownerId,
      worldConfig: spec.worldConfig,
      editorIds: spec.editorIds,
    );
  }

  @override
  Future<void> updateRoomConfig(
    RoomId roomId,
    Map<String, Object?> patch,
  ) async {
    // This door patches `worldConfig` ONLY. A patch key that collides with an
    // engine-metadata field would smuggle a rename/visibility/owner change
    // through the config door — exactly what the step-5 metadata door is for.
    final collisions = patch.keys.where(_engineKeys.contains).toList();
    if (collisions.isNotEmpty) {
      throw ArgumentError.value(
        collisions,
        'patch',
        'updateRoomConfig patches worldConfig only; these engine-owned '
            'metadata keys must go through the step-5 metadata-update door',
      );
    }
    await _collection.doc(roomId.value).update({
      ...patch,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  bool _isPublicFor(RoomVisibility v) => switch (v) {
        RoomVisibility.public => true,
        RoomVisibility.unlisted => false,
        RoomVisibility.private => throw UnsupportedError(
            'FirestoreRoomConfigStore does not support RoomVisibility.private: '
            'the Firestore backend cannot gate reachability-by-id without a '
            'security-rules change. Use unlisted, or add rules enforcement '
            'first (step-5 metadata door).',
          ),
      };

  RoomDescriptor _toDescriptor(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data()!;
    final worldConfig = <String, Object?>{
      for (final e in data.entries)
        if (!_engineKeys.contains(e.key)) e.key: e.value,
    };
    return RoomDescriptor(
      id: RoomId(doc.id),
      displayName: data['name'] as String,
      // Re-parse the wire against our own registry — a stored brand is not
      // proof of registration (see WorldTypeId's forgeability contract).
      worldType: WorldTypeId.parse(
        data['worldType'] as String? ?? _defaultWorldType,
        _registry,
      ),
      visibility: (data['isPublic'] as bool? ?? true)
          ? RoomVisibility.public
          : RoomVisibility.unlisted,
      ownerId: UserId(data['ownerId'] as String),
      ownerDisplayName: data['ownerDisplayName'] as String?,
      editorIds: (data['editorIds'] as List<dynamic>?)
              ?.map((e) => UserId(e as String))
              .toList() ??
          const [],
      worldConfig: worldConfig,
    );
  }
}
