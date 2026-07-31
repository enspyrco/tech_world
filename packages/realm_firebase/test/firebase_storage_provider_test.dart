import 'dart:typed_data';

import 'package:firebase_storage_mocks/firebase_storage_mocks.dart';
import 'package:realm/realm.dart';
import 'package:realm_firebase/realm_firebase.dart';
import 'package:test/test.dart';

void main() {
  late FirebaseStorageProvider provider;

  setUp(() {
    provider = FirebaseStorageProvider(storage: MockFirebaseStorage());
  });

  test('is a StorageProvider', () {
    expect(provider, isA<StorageProvider>());
  });

  test('upload returns a firebase-backed BlobRef at the given path', () async {
    final ref = await provider.upload(
      Uint8List.fromList([1, 2, 3]),
      path: 'rooms/r1/tile.png',
      contentType: 'image/png',
    );
    expect(ref.backend.value, StorageBackendId.firebase.value);
    expect(ref.path, 'rooms/r1/tile.png');
  });

  test('upload → download round-trips the exact bytes', () async {
    final bytes = Uint8List.fromList([9, 8, 7, 6, 5]);
    final ref = await provider.upload(bytes, path: 'a/b.bin');
    expect(await provider.download(ref), equals(bytes));
  });

  test('publicUrl returns a non-empty URI', () async {
    final ref = await provider.upload(Uint8List.fromList([1]), path: 'p/q.bin');
    final url = await provider.publicUrl(ref);
    expect(url, isA<Uri>());
    expect(url.toString(), isNotEmpty);
  });

  test('delete completes for an uploaded blob', () async {
    final ref = await provider.upload(Uint8List.fromList([1]), path: 'd/e.bin');
    await expectLater(provider.delete(ref), completes);
  });

  group('cross-backend guard', () {
    // A BlobRef minted by another backend must never be routed through the
    // Firebase provider — the path grammar is backend-specific.
    final foreign = BlobRef(backend: StorageBackendId.s3, path: 'bucket/key');

    test('download rejects a non-firebase BlobRef', () {
      expect(provider.download(foreign), throwsArgumentError);
    });
    test('publicUrl rejects a non-firebase BlobRef', () {
      expect(provider.publicUrl(foreign), throwsArgumentError);
    });
    test('delete rejects a non-firebase BlobRef', () {
      expect(provider.delete(foreign), throwsArgumentError);
    });
  });
}
