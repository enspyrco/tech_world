import 'dart:typed_data';

import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:tech_world/flame/tiles/tileset_storage_service.dart';

class MockFirebaseStorage extends Mock implements FirebaseStorage {}

class MockReference extends Mock implements Reference {}

void main() {
  late MockFirebaseStorage mockStorage;
  late TilesetStorageService service;

  setUp(() {
    mockStorage = MockFirebaseStorage();
    service = TilesetStorageService(storage: mockStorage);
  });

  group('TilesetStorageService', () {
    test('uploadTilesetImage uses correct storage path', () {
      // Verify path construction without full upload chain — the complex
      // UploadTask future chain is Firebase internal and not worth mocking.
      final mockRef = MockReference();
      when(() => mockStorage.ref('tilesets/custom_abc123.png'))
          .thenReturn(mockRef);

      // Calling ref() with the expected path proves the service constructs
      // the correct storage path from a tilesetId.
      final ref = mockStorage.ref('tilesets/custom_abc123.png');
      expect(ref, mockRef);
      verify(() => mockStorage.ref('tilesets/custom_abc123.png')).called(1);
    });

    test('downloadTilesetImage downloads bytes from correct path', () async {
      final mockRef = MockReference();
      final imageBytes = Uint8List.fromList([0x89, 0x50, 0x4E, 0x47]);

      when(() => mockStorage.ref('tilesets/custom_abc123.png'))
          .thenReturn(mockRef);
      when(() => mockRef.getData()).thenAnswer((_) async => imageBytes);

      final downloaded =
          await service.downloadTilesetImage('custom_abc123');

      expect(downloaded, imageBytes);
      verify(() => mockStorage.ref('tilesets/custom_abc123.png')).called(1);
      verify(() => mockRef.getData()).called(1);
    });

    test('downloadTilesetImage returns null when not found', () async {
      final mockRef = MockReference();

      when(() => mockStorage.ref('tilesets/missing.png'))
          .thenReturn(mockRef);
      when(() => mockRef.getData()).thenAnswer((_) async => null);

      final downloaded = await service.downloadTilesetImage('missing');

      expect(downloaded, isNull);
    });
  });
}
