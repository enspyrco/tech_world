import 'dart:typed_data';

import 'package:firebase_storage/firebase_storage.dart';

/// Handles tileset image upload and retrieval from Firebase Storage.
///
/// Custom tilesets are stored at `tilesets/{id}.png`. Content-hash-based IDs
/// make re-uploads idempotent — uploading the same image twice is a no-op.
class TilesetStorageService {
  TilesetStorageService({FirebaseStorage? storage})
      : _storage = storage ?? FirebaseStorage.instance;

  final FirebaseStorage _storage;

  /// Upload a tileset image to Firebase Storage.
  ///
  /// Returns the download URL on success. The path `tilesets/{tilesetId}.png`
  /// is deterministic so repeated uploads of the same content are idempotent.
  Future<String> uploadTilesetImage({
    required String tilesetId,
    required Uint8List imageBytes,
  }) async {
    final ref = _storage.ref('tilesets/$tilesetId.png');
    await ref.putData(
      imageBytes,
      SettableMetadata(contentType: 'image/png'),
    );
    return ref.getDownloadURL();
  }

  /// Download a tileset image from Firebase Storage.
  ///
  /// Returns the raw PNG bytes, or `null` if the file doesn't exist.
  Future<Uint8List?> downloadTilesetImage(String tilesetId) async {
    final ref = _storage.ref('tilesets/$tilesetId.png');
    return ref.getData();
  }
}
