import 'dart:typed_data';

import 'package:firebase_storage/firebase_storage.dart';
import 'package:realm/realm.dart';

/// Firebase Cloud Storage implementation of [StorageProvider].
///
/// No-leak: the public surface accepts and returns only [BlobRef] and plain
/// Dart values. `firebase_storage`'s `Reference`, `UploadTask` and
/// `SettableMetadata` never cross the boundary.
///
/// The `FirebaseStorage` instance is injectable so tests can substitute a
/// mock/fake — the same DI-seam convention the app's `ProfilePictureService`
/// and `TilesetStorageService` already use.
class FirebaseStorageProvider implements StorageProvider {
  /// Creates a provider over [storage] (defaults to [FirebaseStorage.instance]).
  FirebaseStorageProvider({FirebaseStorage? storage})
      : _storage = storage ?? FirebaseStorage.instance;

  final FirebaseStorage _storage;

  @override
  Future<BlobRef> upload(
    Uint8List bytes, {
    required String path,
    String? contentType,
  }) async {
    final ref = _storage.ref(path);
    await ref.putData(
      bytes,
      contentType == null
          ? SettableMetadata()
          : SettableMetadata(contentType: contentType),
    );
    return BlobRef(backend: StorageBackendId.firebase, path: path);
  }

  @override
  Future<Uint8List> download(BlobRef ref) async {
    _assertFirebaseBackend(ref);
    final data = await _storage.ref(ref.path).getData();
    if (data == null) {
      throw StateError('No blob at "${ref.path}".');
    }
    return data;
  }

  @override
  Future<Uri> publicUrl(BlobRef ref) async {
    _assertFirebaseBackend(ref);
    return Uri.parse(await _storage.ref(ref.path).getDownloadURL());
  }

  @override
  Future<void> delete(BlobRef ref) async {
    _assertFirebaseBackend(ref);
    await _storage.ref(ref.path).delete();
  }

  /// A [BlobRef] minted by another backend (s3/local) must never be routed
  /// through the Firebase provider — the `path` grammar is backend-specific.
  /// Compared by `.value` to avoid extension-type `==` subtleties.
  void _assertFirebaseBackend(BlobRef ref) {
    if (ref.backend.value != StorageBackendId.firebase.value) {
      throw ArgumentError.value(
        ref.backend.value,
        'ref.backend',
        'FirebaseStorageProvider only handles firebase-backed blobs',
      );
    }
  }
}
