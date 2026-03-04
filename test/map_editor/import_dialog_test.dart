import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tech_world/map_editor/import_dialog.dart';
import 'package:tech_world/map_editor/map_editor_state.dart';

/// Build a zip archive containing the given files, as raw bytes.
Uint8List buildTestZip(Map<String, List<int>> files) {
  final archive = Archive();
  for (final entry in files.entries) {
    archive.addFile(ArchiveFile(
      entry.key,
      entry.value.length,
      entry.value,
    ));
  }
  return Uint8List.fromList(ZipEncoder().encode(archive));
}

/// Minimal valid TMX XML with a predefined tileset.
const _validTmx = '<?xml version="1.0" encoding="UTF-8"?>'
    '<map version="1.10" tiledversion="1.11.2" '
    'orientation="orthogonal" renderorder="right-down" '
    'width="2" height="2" tilewidth="32" tileheight="32" infinite="0">'
    '<tileset firstgid="1" name="Test" tilewidth="32" tileheight="32" '
    'tilecount="4" columns="2">'
    '<image source="../tilesets/test_tileset.png" width="64" height="64"/>'
    '</tileset>'
    '<layer name="Ground" width="2" height="2">'
    '<data encoding="csv">1,2,\n3,4</data>'
    '</layer>'
    '</map>';

void main() {
  group('ImportDialog', () {
    late MapEditorState state;

    setUp(() {
      state = MapEditorState();
    });

    Widget buildDialog() {
      return MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => showDialog<void>(
                context: context,
                builder: (_) => ImportDialog(state: state),
              ),
              child: const Text('Open'),
            ),
          ),
        ),
      );
    }

    testWidgets('TMX tab shows file pick and zip buttons', (tester) async {
      await tester.pumpWidget(buildDialog());

      // Open the dialog.
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      // Switch to TMX tab.
      await tester.tap(find.text('TMX'));
      await tester.pumpAndSettle();

      // Verify both buttons are visible.
      expect(find.text('.tmx File'), findsOneWidget);
      expect(find.text('.zip Bundle'), findsOneWidget);
      expect(find.byIcon(Icons.file_open), findsOneWidget);
      expect(find.byIcon(Icons.folder_zip), findsOneWidget);
    });

    testWidgets('TMX tab shows updated hint text', (tester) async {
      await tester.pumpWidget(buildDialog());

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('TMX'));
      await tester.pumpAndSettle();

      expect(
        find.text('Select a .tmx file or paste XML below...'),
        findsOneWidget,
      );
    });

    testWidgets('Import button triggers loadFromTmx via paste',
        (tester) async {
      await tester.pumpWidget(buildDialog());

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      // Switch to TMX tab.
      await tester.tap(find.text('TMX'));
      await tester.pumpAndSettle();

      // Find the TMX text field by looking for the multiline TextField.
      final tmxField = find.byWidgetPredicate(
        (w) =>
            w is TextField &&
            w.maxLines == null &&
            w.expands == true,
      );
      expect(tmxField, findsOneWidget);

      await tester.enterText(tmxField, _validTmx);
      await tester.pumpAndSettle();

      // Tap the Import button.
      await tester.tap(find.text('Import'));
      await tester.pumpAndSettle();

      // Verify the state was updated (dialog should have closed).
      expect(find.byType(ImportDialog), findsNothing);
      expect(state.mapName, isNotNull);
    });
  });

  group('_extractZipBundle', () {
    test('extracts TMX from a zip archive', () {
      final zip = buildTestZip({
        'my_map.tmx': utf8.encode(_validTmx),
      });

      final result = extractZipBundle(zip);

      expect(result.tmxXml, _validTmx);
      expect(result.tsxProviders, isEmpty);
      expect(result.imageBytes, isEmpty);
    });

    test('extracts TSX providers from zip', () {
      const tsxXml = '<?xml version="1.0" encoding="UTF-8"?>'
          '<tileset version="1.10" name="Desert" tilewidth="32" tileheight="32" '
          'tilecount="64" columns="8">'
          '<image source="desert.png" width="256" height="256"/>'
          '</tileset>';

      final zip = buildTestZip({
        'maps/my_map.tmx': utf8.encode(_validTmx),
        'tilesets/desert.tsx': utf8.encode(tsxXml),
      });

      final result = extractZipBundle(zip);

      expect(result.tmxXml, _validTmx);
      expect(result.tsxProviders, hasLength(1));
      expect(result.tsxProviders.first.filename, 'desert.tsx');
    });

    test('extracts PNG image bytes from zip', () {
      final pngBytes = Uint8List.fromList(List.filled(32, 0xAB));

      final zip = buildTestZip({
        'my_map.tmx': utf8.encode(_validTmx),
        'images/desert.png': pngBytes,
      });

      final result = extractZipBundle(zip);

      // Should be stored under both full path and filename.
      expect(result.imageBytes['images/desert.png'], pngBytes);
      expect(result.imageBytes['desert.png'], pngBytes);
    });

    test('throws FormatException when no TMX found in zip', () {
      final zip = buildTestZip({
        'readme.txt': utf8.encode('Hello'),
        'tileset.png': [0xFF, 0x00],
      });

      expect(
        () => extractZipBundle(zip),
        throwsA(isA<FormatException>().having(
          (e) => e.message,
          'message',
          contains('No .tmx file found'),
        )),
      );
    });

    test('handles nested directory structure in zip', () {
      final pngBytes = Uint8List.fromList([0x89, 0x50, 0x4E, 0x47]);

      final zip = buildTestZip({
        'project/maps/world.tmx': utf8.encode(_validTmx),
        'project/tilesets/terrain.tsx': utf8.encode(
          '<?xml version="1.0"?>'
          '<tileset name="T" tilewidth="32" tileheight="32" '
          'tilecount="4" columns="2">'
          '<image source="terrain.png" width="64" height="64"/>'
          '</tileset>',
        ),
        'project/tilesets/terrain.png': pngBytes,
      });

      final result = extractZipBundle(zip);

      expect(result.tmxXml, _validTmx);
      expect(result.tsxProviders, hasLength(1));
      expect(result.tsxProviders.first.filename, 'terrain.tsx');
      // Full path and filename both present.
      expect(result.imageBytes.containsKey('project/tilesets/terrain.png'),
          isTrue);
      expect(result.imageBytes.containsKey('terrain.png'), isTrue);
    });
  });
}
