import 'dart:typed_data';

import 'package:firebase_storage/firebase_storage.dart';

/// Handles profile picture upload and retrieval from Firebase Storage.
class ProfilePictureService {
  ProfilePictureService({FirebaseStorage? storage})
      : _storage = storage ?? FirebaseStorage.instance;

  final FirebaseStorage _storage;

  /// Uploads a profile picture for the given user.
  ///
  /// Stores at `profile_pictures/{uid}/profile.{ext}` and returns the
  /// download URL on success.
  Future<String> uploadProfilePicture({
    required String uid,
    required Uint8List imageBytes,
    required String mimeType,
  }) async {
    final ext = _extensionFromMime(mimeType);
    final ref = _storage.ref('profile_pictures/$uid/profile.$ext');

    await ref.putData(imageBytes, SettableMetadata(contentType: mimeType));
    return ref.getDownloadURL();
  }

  String _extensionFromMime(String mimeType) {
    return switch (mimeType) {
      'image/png' => 'png',
      'image/gif' => 'gif',
      'image/webp' => 'webp',
      _ => 'jpg',
    };
  }
}
