import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:tech_world/flame/maps/tmx_importer.dart';
import 'package:tech_world/map_editor/map_editor_state.dart';

/// Tabbed import dialog with ASCII and TMX tabs.
///
/// The ASCII tab pastes `.#ST` grid art (existing flow).
/// The TMX tab pastes Tiled `.tmx` XML and converts it to a [GameMap] via
/// [TmxImporter].
class ImportDialog extends StatefulWidget {
  const ImportDialog({required this.state, super.key});

  final MapEditorState state;

  static const _headerBg = Color(0xFF2D2D2D);

  @override
  State<ImportDialog> createState() => _ImportDialogState();
}

class _ImportDialogState extends State<ImportDialog>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  final _asciiController = TextEditingController();
  final _tmxController = TextEditingController();
  final _nameController = TextEditingController();
  final _idController = TextEditingController();
  String? _pickedFileName;

  // Multi-file bundle state.
  String? _bundleTmxXml;
  List<InMemoryTsxProvider>? _bundleTsxProviders;
  Map<String, Uint8List>? _bundleImageBytes;
  String? _bundleFileNames;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _asciiController.dispose();
    _tmxController.dispose();
    _nameController.dispose();
    _idController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: ImportDialog._headerBg,
      title: const Text('Import Map', style: TextStyle(color: Colors.white)),
      contentPadding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
      content: SizedBox(
        width: 520,
        height: 460,
        child: Column(
          children: [
            TabBar(
              controller: _tabController,
              indicatorColor: const Color(0xFF4FC3F7),
              labelColor: Colors.white,
              unselectedLabelColor: Colors.grey,
              tabs: const [
                Tab(text: 'ASCII'),
                Tab(text: 'TMX'),
              ],
            ),
            const SizedBox(height: 12),
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  _buildAsciiTab(),
                  _buildTmxTab(),
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _handleImport,
          child: const Text('Import'),
        ),
      ],
    );
  }

  Widget _buildAsciiTab() {
    return TextField(
      controller: _asciiController,
      maxLines: null,
      expands: true,
      style: const TextStyle(
        color: Colors.white,
        fontFamily: 'monospace',
        fontSize: 10,
      ),
      decoration: InputDecoration(
        hintText: 'Paste ASCII art here (50x50, .#ST)...',
        hintStyle: TextStyle(color: Colors.grey.shade600),
        border: OutlineInputBorder(
          borderSide: BorderSide(color: Colors.grey.shade700),
        ),
      ),
    );
  }

  Widget _buildTmxTab() {
    return Column(
      children: [
        // Optional map name & ID fields
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _nameController,
                style: const TextStyle(color: Colors.white, fontSize: 12),
                decoration: InputDecoration(
                  labelText: 'Map Name (optional)',
                  labelStyle:
                      TextStyle(color: Colors.grey.shade500, fontSize: 11),
                  isDense: true,
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                  enabledBorder: OutlineInputBorder(
                    borderSide: BorderSide(color: Colors.grey.shade700),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderSide: const BorderSide(color: Color(0xFF4FC3F7)),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: _idController,
                style: const TextStyle(color: Colors.white, fontSize: 12),
                decoration: InputDecoration(
                  labelText: 'Map ID (optional)',
                  labelStyle:
                      TextStyle(color: Colors.grey.shade500, fontSize: 11),
                  isDense: true,
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                  enabledBorder: OutlineInputBorder(
                    borderSide: BorderSide(color: Colors.grey.shade700),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderSide: const BorderSide(color: Color(0xFF4FC3F7)),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        // File picker row
        Row(
          children: [
            ElevatedButton.icon(
              onPressed: _pickTmxFile,
              icon: const Icon(Icons.file_open, size: 16),
              label: const Text('.tmx File'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF4FC3F7),
                foregroundColor: Colors.black87,
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                textStyle: const TextStyle(fontSize: 12),
              ),
            ),
            const SizedBox(width: 8),
            ElevatedButton.icon(
              onPressed: _pickMultipleFiles,
              icon: const Icon(Icons.upload_file, size: 16),
              label: const Text('Multiple Files'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF81C784),
                foregroundColor: Colors.black87,
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                textStyle: const TextStyle(fontSize: 12),
              ),
            ),
            if (_pickedFileName != null || _bundleFileNames != null) ...[
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _bundleFileNames ?? _pickedFileName!,
                  style: TextStyle(
                    color: Colors.grey.shade400,
                    fontSize: 11,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 8),
        // TMX XML paste area
        Expanded(
          child: TextField(
            controller: _tmxController,
            maxLines: null,
            expands: true,
            style: const TextStyle(
              color: Colors.white,
              fontFamily: 'monospace',
              fontSize: 10,
            ),
            decoration: InputDecoration(
              hintText: 'Select a .tmx file or paste XML below...',
              hintStyle: TextStyle(color: Colors.grey.shade600),
              border: OutlineInputBorder(
                borderSide: BorderSide(color: Colors.grey.shade700),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _pickTmxFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['tmx'],
      withData: true,
    );

    if (result == null || result.files.isEmpty) return;

    final file = result.files.first;
    if (file.bytes == null) return;

    final String content;
    try {
      content = utf8.decode(file.bytes!);
    } on FormatException {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('File is not valid UTF-8 text.'),
          backgroundColor: Colors.red.shade700,
        ),
      );
      return;
    }
    setState(() {
      _tmxController.text = content;
      _pickedFileName = file.name;
    });

    // Auto-populate map name from filename if empty.
    if (_nameController.text.trim().isEmpty) {
      final baseName = file.name.replaceAll(RegExp(r'\.tmx$', caseSensitive: false), '');
      // Convert snake_case/kebab-case to Title Case.
      final titleCase = baseName
          .replaceAll(RegExp(r'[_-]'), ' ')
          .split(' ')
          .where((w) => w.isNotEmpty)
          .map((w) => w[0].toUpperCase() + w.substring(1).toLowerCase())
          .join(' ');
      _nameController.text = titleCase;
    }
  }

  Future<void> _pickMultipleFiles() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['tmx', 'tsx', 'png', 'jpg', 'jpeg'],
      allowMultiple: true,
      withData: true,
    );

    if (result == null || result.files.isEmpty) return;

    final extracted = classifyFiles(result.files);

    if (extracted.tmxXml == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text(
            'No .tmx file found. Please include a .tmx map file.',
          ),
          backgroundColor: Colors.red.shade700,
        ),
      );
      return;
    }

    setState(() {
      _bundleTmxXml = extracted.tmxXml;
      _bundleTsxProviders = extracted.tsxProviders;
      _bundleImageBytes = extracted.imageBytes;
      _bundleFileNames =
          result.files.map((f) => f.name).join(', ');
      // Show TMX XML in the text field for visibility.
      _tmxController.text = extracted.tmxXml!;
      _pickedFileName = null; // Clear single-file pick.
    });

    // Auto-populate map name from TMX filename if empty.
    if (_nameController.text.trim().isEmpty) {
      final tmxFile = result.files.firstWhere(
        (f) => f.name.toLowerCase().endsWith('.tmx'),
      );
      final baseName = tmxFile.name.replaceAll(
        RegExp(r'\.tmx$', caseSensitive: false),
        '',
      );
      final titleCase = baseName
          .replaceAll(RegExp(r'[_-]'), ' ')
          .split(' ')
          .where((w) => w.isNotEmpty)
          .map((w) => w[0].toUpperCase() + w.substring(1).toLowerCase())
          .join(' ');
      _nameController.text = titleCase;
    }
  }

  void _handleImport() {
    if (_tabController.index == 0) {
      // ASCII import
      widget.state.loadFromAscii(_asciiController.text);
      Navigator.pop(context);
    } else {
      // TMX import — multi-file bundle or single file/paste.
      if (_bundleTmxXml != null) {
        _importTmxFromBundle();
      } else {
        _importTmx();
      }
    }
  }

  void _importTmx() {
    final tmxXml = _tmxController.text.trim();
    if (tmxXml.isEmpty) return;

    final mapName =
        _nameController.text.trim().isEmpty ? null : _nameController.text.trim();
    final mapId =
        _idController.text.trim().isEmpty ? null : _idController.text.trim();

    try {
      final warnings = widget.state.loadFromTmx(
        tmxXml,
        mapName: mapName,
        mapId: mapId,
      );
      Navigator.pop(context);
      _showWarnings(warnings);
    } on TmxImportException catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Import failed: ${e.message}'),
          backgroundColor: Colors.red.shade700,
        ),
      );
    }
  }

  void _importTmxFromBundle() {
    final tmxXml = _bundleTmxXml!;
    final mapName =
        _nameController.text.trim().isEmpty ? null : _nameController.text.trim();
    final mapId =
        _idController.text.trim().isEmpty ? null : _idController.text.trim();

    try {
      final result = widget.state.loadFromTmxWithCustomTilesets(
        tmxXml,
        customImages: _bundleImageBytes ?? {},
        tsxProviders: _bundleTsxProviders,
        mapName: mapName,
        mapId: mapId,
      );
      Navigator.pop(context, result);
      _showWarnings(result.warnings);
    } on TmxImportException catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Import failed: ${e.message}'),
          backgroundColor: Colors.red.shade700,
        ),
      );
    }
  }

  void _showWarnings(List<TmxImportWarning> warnings) {
    if (warnings.isEmpty) return;
    final message = warnings.map((w) => w.message).join('\n');
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Import succeeded with ${warnings.length} warning(s):\n$message',
          style: const TextStyle(fontSize: 12),
        ),
        duration: const Duration(seconds: 6),
        backgroundColor: Colors.orange.shade800,
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Multi-file classification
// ---------------------------------------------------------------------------

/// Classified contents from individually picked files for TMX import.
class ClassifiedFiles {
  const ClassifiedFiles({
    required this.tmxXml,
    required this.tsxProviders,
    required this.imageBytes,
  });

  /// The TMX XML string, or `null` if no `.tmx` file was picked.
  final String? tmxXml;
  final List<InMemoryTsxProvider> tsxProviders;
  final Map<String, Uint8List> imageBytes;
}

/// Classify picked files into TMX, TSX, and image categories.
///
/// Returns a [ClassifiedFiles] with `tmxXml` set to `null` if no `.tmx` file
/// is present — callers should check and show an appropriate error.
@visibleForTesting
ClassifiedFiles classifyFiles(List<PlatformFile> files) {
  String? tmxXml;
  final tsxProviders = <InMemoryTsxProvider>[];
  final imageBytes = <String, Uint8List>{};

  for (final file in files) {
    if (file.bytes == null) continue;

    final name = file.name;
    final lowerName = name.toLowerCase();

    if (lowerName.endsWith('.tmx')) {
      tmxXml = utf8.decode(file.bytes!);
    } else if (lowerName.endsWith('.tsx')) {
      final xml = utf8.decode(file.bytes!);
      tsxProviders.add(InMemoryTsxProvider(name, xml));
    } else if (lowerName.endsWith('.png') ||
        lowerName.endsWith('.jpg') ||
        lowerName.endsWith('.jpeg')) {
      imageBytes[name] = file.bytes!;
    }
  }

  return ClassifiedFiles(
    tmxXml: tmxXml,
    tsxProviders: tsxProviders,
    imageBytes: imageBytes,
  );
}
