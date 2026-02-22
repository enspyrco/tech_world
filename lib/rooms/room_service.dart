import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:tech_world/flame/maps/game_map.dart';
import 'package:tech_world/flame/maps/tile_map_format.dart';
import 'package:tech_world/rooms/room_data.dart';

/// Firestore CRUD service for rooms.
///
/// Follows the same pattern as [UserProfileService] — constructor-injected
/// collection reference for testability, simple async methods.
class RoomService {
  RoomService({CollectionReference<Map<String, dynamic>>? collection})
      : _collection =
            collection ?? FirebaseFirestore.instance.collection('rooms');

  final CollectionReference<Map<String, dynamic>> _collection;

  /// Create a new room and return the created [RoomData] with its Firestore ID.
  Future<RoomData> createRoom({
    required String name,
    required String ownerId,
    required String ownerDisplayName,
    required GameMap map,
    bool isPublic = true,
  }) async {
    final room = RoomData(
      id: '', // Placeholder — Firestore will assign the real ID.
      name: name,
      ownerId: ownerId,
      ownerDisplayName: ownerDisplayName,
      isPublic: isPublic,
      mapData: map,
    );

    final data = room.toFirestore();
    data['createdAt'] = FieldValue.serverTimestamp();
    data['updatedAt'] = FieldValue.serverTimestamp();

    final docRef = await _collection.add(data);

    // Return a copy with the real Firestore document ID.
    return RoomData(
      id: docRef.id,
      name: name,
      ownerId: ownerId,
      ownerDisplayName: ownerDisplayName,
      editorIds: room.editorIds,
      isPublic: isPublic,
      mapData: map,
    );
  }

  /// Update the map data for an existing room.
  Future<void> updateRoomMap(String roomId, GameMap map) async {
    final fullJson = _mapDataJson(map);
    await _collection.doc(roomId).update({
      'mapData': fullJson,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Update the room name.
  Future<void> updateRoomName(String roomId, String name) async {
    await _collection.doc(roomId).update({
      'name': name,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Delete a room. Only the owner should call this.
  Future<void> deleteRoom(String roomId) async {
    await _collection.doc(roomId).delete();
  }

  /// Fetch a single room by ID. Returns `null` if not found.
  Future<RoomData?> getRoom(String roomId) async {
    final doc = await _collection.doc(roomId).get();
    if (!doc.exists || doc.data() == null) return null;
    return RoomData.fromFirestore(doc);
  }

  /// List all public rooms, ordered by most recently updated.
  Future<List<RoomData>> listPublicRooms() async {
    final snapshot = await _collection
        .where('isPublic', isEqualTo: true)
        .orderBy('updatedAt', descending: true)
        .limit(50)
        .get();
    return snapshot.docs.map(RoomData.fromFirestore).toList();
  }

  /// List rooms owned by the given user, ordered by most recently updated.
  Future<List<RoomData>> listMyRooms(String userId) async {
    final snapshot = await _collection
        .where('ownerId', isEqualTo: userId)
        .orderBy('updatedAt', descending: true)
        .limit(50)
        .get();
    return snapshot.docs.map(RoomData.fromFirestore).toList();
  }

  /// Add a user to the editor list (Firestore arrayUnion).
  Future<void> addEditor(String roomId, String userId) async {
    await _collection.doc(roomId).update({
      'editorIds': FieldValue.arrayUnion([userId]),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Remove a user from the editor list (Firestore arrayRemove).
  Future<void> removeEditor(String roomId, String userId) async {
    await _collection.doc(roomId).update({
      'editorIds': FieldValue.arrayRemove([userId]),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Toggle public visibility.
  Future<void> setPublic(String roomId, {required bool isPublic}) async {
    await _collection.doc(roomId).update({
      'isPublic': isPublic,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Build the `mapData` JSON without `id`/`name` (those live at the room level).
  static Map<String, dynamic> _mapDataJson(GameMap map) {
    final json = TileMapFormat.toJson(map);
    json.remove('id');
    json.remove('name');
    return json;
  }
}
