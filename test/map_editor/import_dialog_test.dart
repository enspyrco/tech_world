import 'dart:convert';
import 'dart:typed_data';

import 'package:cross_file/cross_file.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tech_world/map_editor/import_dialog.dart';
import 'package:tech_world/map_editor/map_editor_state.dart';

/// A [PlatformFile] fake holding its content in memory, for tests.
///
/// file_picker 13 made [PlatformFile] an abstract class with no public
/// constructor — content is read via [readAsBytes]/[readAsByteStream], not a
/// `bytes` field — so tests provide their own implementation, following the
/// pattern in file_picker_platform_interface's own test suite.
base class _MemoryPlatformFile extends PlatformFile {
  _MemoryPlatformFile(this.name, Uint8List bytes) : _bytes = bytes;

  @override
  final String name;
  final Uint8List _bytes;

  @override
  Uri get uri => Uri.file(name);

  @override
  XFile get xFile => XFile.fromData(_bytes, name: name);

  @override
  int? lengthSync() => _bytes.length;

  @override
  Future<int?> length() async => _bytes.length;

  @override
  Future<Uint8List> readAsBytes() async => _bytes;

  @override
  Stream<Uint8List> readAsByteStream() => Stream.value(_bytes);
}

/// Create a [PlatformFile] with the given name and byte content.
PlatformFile platformFile(String name, List<int> bytes) {
  return _MemoryPlatformFile(name, Uint8List.fromList(bytes));
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

    testWidgets('TMX tab shows file pick and multi-file buttons',
        (tester) async {
      await tester.pumpWidget(buildDialog());

      // Open the dialog.
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      // Switch to TMX tab.
      await tester.tap(find.text('TMX'));
      await tester.pumpAndSettle();

      // Verify both buttons are visible.
      expect(find.text('.tmx File'), findsOneWidget);
      expect(find.text('Multiple Files'), findsOneWidget);
      expect(find.byIcon(Icons.file_open), findsOneWidget);
      expect(find.byIcon(Icons.upload_file), findsOneWidget);
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

  group('classifyFiles', () {
    test('extracts TMX from file list', () async {
      final files = [
        platformFile('my_map.tmx', utf8.encode(_validTmx)),
      ];

      final result = await classifyFiles(files);

      expect(result.tmxXml, _validTmx);
      expect(result.tsxProviders, isEmpty);
      expect(result.imageBytes, isEmpty);
    });

    test('extracts TSX providers from file list', () async {
      const tsxXml = '<?xml version="1.0" encoding="UTF-8"?>'
          '<tileset version="1.10" name="Desert" tilewidth="32" tileheight="32" '
          'tilecount="64" columns="8">'
          '<image source="desert.png" width="256" height="256"/>'
          '</tileset>';

      final files = [
        platformFile('my_map.tmx', utf8.encode(_validTmx)),
        platformFile('desert.tsx', utf8.encode(tsxXml)),
      ];

      final result = await classifyFiles(files);

      expect(result.tmxXml, _validTmx);
      expect(result.tsxProviders, hasLength(1));
      expect(result.tsxProviders.first.filename, 'desert.tsx');
    });

    test('extracts PNG image bytes from file list', () async {
      final pngBytes = Uint8List.fromList(List.filled(32, 0xAB));

      final files = [
        platformFile('my_map.tmx', utf8.encode(_validTmx)),
        platformFile('desert.png', pngBytes),
      ];

      final result = await classifyFiles(files);

      expect(result.imageBytes['desert.png'], pngBytes);
    });

    test('returns null tmxXml when no TMX found', () async {
      final files = [
        platformFile('tileset.png', [0xFF, 0x00]),
      ];

      final result = await classifyFiles(files);

      expect(result.tmxXml, isNull);
    });

    test('handles multiple TSX and image files', () async {
      final pngBytes = Uint8List.fromList([0x89, 0x50, 0x4E, 0x47]);

      final files = [
        platformFile('world.tmx', utf8.encode(_validTmx)),
        platformFile(
          'terrain.tsx',
          utf8.encode(
            '<?xml version="1.0"?>'
            '<tileset name="T" tilewidth="32" tileheight="32" '
            'tilecount="4" columns="2">'
            '<image source="terrain.png" width="64" height="64"/>'
            '</tileset>',
          ),
        ),
        platformFile('terrain.png', pngBytes),
      ];

      final result = await classifyFiles(files);

      expect(result.tmxXml, _validTmx);
      expect(result.tsxProviders, hasLength(1));
      expect(result.tsxProviders.first.filename, 'terrain.tsx');
      expect(result.imageBytes.containsKey('terrain.png'), isTrue);
    });

    test('supports JPG and JPEG image files', () async {
      final jpgBytes = Uint8List.fromList([0xFF, 0xD8, 0xFF]);

      final files = [
        platformFile('map.tmx', utf8.encode(_validTmx)),
        platformFile('photo.jpg', jpgBytes),
        platformFile('background.jpeg', jpgBytes),
      ];

      final result = await classifyFiles(files);

      expect(result.imageBytes, hasLength(2));
      expect(result.imageBytes.containsKey('photo.jpg'), isTrue);
      expect(result.imageBytes.containsKey('background.jpeg'), isTrue);
    });
  });
}
