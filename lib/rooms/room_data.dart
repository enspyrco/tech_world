import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:tech_world/flame/maps/game_map.dart';
import 'package:tech_world/flame/maps/tile_map_format.dart';

/// A room in Tech World — a persistent map with ownership and access control.
///
/// Each room maps to a Firestore document in the `rooms` collection.
/// The [mapData] field stores a full [GameMap] serialized via [TileMapFormat].
class RoomData {
  const RoomData({
    required this.id,
    required this.name,
    required this.ownerId,
    required this.ownerDisplayName,
    this.editorIds = const [],
    this.isPublic = true,
    this.createdAt,
    this.updatedAt,
    required this.mapData,
  });

  /// Firestore document ID.
  final String id;

  /// Display name of the room.
  final String name;

  /// Firebase UID of the room creator. Has full control (delete, rename, etc).
  final String ownerId;

  /// Display name of the owner (denormalized for listing without extra lookups).
  final String ownerDisplayName;

  /// Firebase UIDs of invited editors who can modify the map.
  final List<String> editorIds;

  /// Whether this room is visible in the public room browser.
  final bool isPublic;

  /// When the room was created.
  final DateTime? createdAt;

  /// When the room was last updated.
  final DateTime? updatedAt;

  /// The full map definition for this room.
  final GameMap mapData;

  /// Whether the given user can edit this room's map.
  bool canEdit(String userId) => userId == ownerId || editorIds.contains(userId);

  /// Whether the given user is the owner.
  bool isOwner(String userId) => userId == ownerId;

  /// Deserialize from a Firestore document snapshot.
  factory RoomData.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data()!;
    final mapJson = data['mapData'] as Map<String, dynamic>;

    // The map id and name are stored at the room level, not inside mapData.
    final gameMap = TileMapFormat.fromJson({
      ...mapJson,
      'id': doc.id,
      'name': data['name'] as String,
    });

    return RoomData(
      id: doc.id,
      name: data['name'] as String,
      ownerId: data['ownerId'] as String,
      ownerDisplayName: data['ownerDisplayName'] as String? ?? '',
      editorIds: (data['editorIds'] as List<dynamic>?)?.cast<String>() ?? [],
      isPublic: data['isPublic'] as bool? ?? true,
      createdAt: (data['createdAt'] as Timestamp?)?.toDate(),
      updatedAt: (data['updatedAt'] as Timestamp?)?.toDate(),
      mapData: gameMap,
    );
  }

  /// Serialize to a Firestore-compatible map.
  ///
  /// Excludes `id` (used as the document key) and timestamps
  /// (set via [FieldValue.serverTimestamp]).
  Map<String, dynamic> toFirestore() {
    // Build mapData without id/name — those live at the room level.
    final fullJson = TileMapFormat.toJson(mapData);
    fullJson.remove('id');
    fullJson.remove('name');

    return {
      'name': name,
      'ownerId': ownerId,
      'ownerDisplayName': ownerDisplayName,
      'editorIds': editorIds,
      'isPublic': isPublic,
      'mapData': fullJson,
    };
  }

  /// Create a copy with updated fields.
  RoomData copyWith({
    String? name,
    List<String>? editorIds,
    bool? isPublic,
    GameMap? mapData,
  }) {
    return RoomData(
      id: id,
      name: name ?? this.name,
      ownerId: ownerId,
      ownerDisplayName: ownerDisplayName,
      editorIds: editorIds ?? this.editorIds,
      isPublic: isPublic ?? this.isPublic,
      createdAt: createdAt,
      updatedAt: updatedAt,
      mapData: mapData ?? this.mapData,
    );
  }
}
