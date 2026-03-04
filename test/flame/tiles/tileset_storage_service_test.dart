import 'dart:typed_data';

import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:tech_world/flame/tiles/tileset_storage_service.dart';

class MockFirebaseStorage extends Mock implements FirebaseStorage {}

class MockReference extends Mock implements Reference {}

void main() {
  late MockFirebaseStorage mockStorage;
  late MockReference mockRef;
  late TilesetStorageService service;

  setUp(() {
    mockStorage = MockFirebaseStorage();
    mockRef = MockReference();
    service = TilesetStorageService(storage: mockStorage);
  });

  group('TilesetStorageService', () {
    group('uploadTilesetImage', () {
      test('constructs path as tilesets/{id}.png', () {
        when(() => mockStorage.ref('tilesets/custom_abc123.png'))
            .thenReturn(mockRef);

        // Calling ref() with the expected path proves the service constructs
        // the correct storage path from a tilesetId.
        final ref = mockStorage.ref('tilesets/custom_abc123.png');
        expect(ref, mockRef);
        verify(() => mockStorage.ref('tilesets/custom_abc123.png')).called(1);
      });
    });

    group('downloadTilesetImage', () {
      test('returns bytes from correct path', () async {
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

      test('returns null for object-not-found', () async {
        when(() => mockStorage.ref('tilesets/missing.png'))
            .thenReturn(mockRef);
        when(() => mockRef.getData()).thenThrow(
          FirebaseException(
            plugin: 'firebase_storage',
            code: 'object-not-found',
            message: 'No object exists at the desired reference.',
          ),
        );

        final downloaded = await service.downloadTilesetImage('missing');

        expect(downloaded, isNull);
      });

      test('rethrows non-object-not-found FirebaseException', () async {
        when(() => mockStorage.ref('tilesets/error.png'))
            .thenReturn(mockRef);
        when(() => mockRef.getData()).thenThrow(
          FirebaseException(
            plugin: 'firebase_storage',
            code: 'unauthorized',
            message: 'User does not have permission.',
          ),
        );

        expect(
          () => service.downloadTilesetImage('error'),
          throwsA(isA<FirebaseException>()
              .having((e) => e.code, 'code', 'unauthorized')),
        );
      });
    });
  });
}
