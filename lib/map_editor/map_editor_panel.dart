import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:tech_world/flame/maps/predefined_maps.dart';
import 'package:tech_world/flame/shared/constants.dart';
import 'package:tech_world/map_editor/map_editor_state.dart';

/// Sidebar panel for the visual map editor.
///
/// Provides a toolbar for selecting paint tools, a paintable mini-grid, and
/// import/export controls. Follows the same dark-theme pattern as
/// [CodeEditorPanel].
class MapEditorPanel extends StatelessWidget {
  const MapEditorPanel({
    required this.state,
    required this.onClose,
    super.key,
  });

  final MapEditorState state;
  final VoidCallback onClose;

  static const _headerBg = Color(0xFF2D2D2D);
  static const _panelBg = Color(0xFF1E1E1E);
  static const _border = Color(0xFF3D3D3D);

  // Tile colours — match in-game rendering.
  static const _barrierColor = Color(0xFF4444FF);
  static const _spawnColor = Color(0xFF00FF41);
  static const _terminalColor = Color(0xFFD97757);

  @override
  Widget build(BuildContext context) {
    return Container(
      color: _panelBg,
      child: Column(
        children: [
          _buildHeader(),
          _buildToolbar(),
          Expanded(child: _buildGrid()),
          _buildFooter(context),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Header
  // ---------------------------------------------------------------------------

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: const BoxDecoration(
        color: _headerBg,
        border: Border(bottom: BorderSide(color: _border)),
      ),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: _barrierColor.withValues(alpha: 0.2),
              shape: BoxShape.circle,
              border: Border.all(color: _barrierColor, width: 2),
            ),
            child: const Center(
              child: Icon(Icons.grid_on, color: _barrierColor, size: 16),
            ),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Text(
              'Map Editor',
              style: TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          IconButton(
            onPressed: onClose,
            icon: const Icon(Icons.close),
            color: Colors.grey,
            iconSize: 20,
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Toolbar — tool buttons + map name/id fields
  // ---------------------------------------------------------------------------

  Widget _buildToolbar() {
    return ListenableBuilder(
      listenable: state,
      builder: (context, _) {
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: const BoxDecoration(
            color: _headerBg,
            border: Border(bottom: BorderSide(color: _border)),
          ),
          child: Column(
            children: [
              // Tool buttons
              Row(
                children: [
                  _toolButton(EditorTool.barrier, Icons.square, 'Barrier',
                      _barrierColor),
                  const SizedBox(width: 4),
                  _toolButton(
                      EditorTool.spawn, Icons.my_location, 'Spawn', _spawnColor),
                  const SizedBox(width: 4),
                  _toolButton(EditorTool.terminal, Icons.terminal, 'Terminal',
                      _terminalColor),
                  const SizedBox(width: 4),
                  _toolButton(EditorTool.eraser, Icons.cleaning_services,
                      'Eraser', Colors.grey),
                  const Spacer(),
                  IconButton(
                    onPressed: state.clearGrid,
                    icon: const Icon(Icons.delete_sweep, size: 18),
                    color: Colors.redAccent,
                    tooltip: 'Clear grid',
                    iconSize: 18,
                    constraints: const BoxConstraints(
                        minWidth: 32, minHeight: 32),
                    padding: EdgeInsets.zero,
                  ),
                ],
              ),
              const SizedBox(height: 8),
              // Map name / id
              Row(
                children: [
                  Expanded(
                    child: _compactField(
                      label: 'Name',
                      value: state.mapName,
                      onChanged: state.setMapName,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _compactField(
                      label: 'ID',
                      value: state.mapId,
                      onChanged: state.setMapId,
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _toolButton(
      EditorTool tool, IconData icon, String tooltip, Color color) {
    final selected = state.currentTool == tool;
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: () => state.setTool(tool),
        borderRadius: BorderRadius.circular(6),
        child: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: selected ? color.withValues(alpha: 0.3) : Colors.transparent,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: selected ? color : Colors.grey.shade700,
              width: selected ? 2 : 1,
            ),
          ),
          child: Icon(icon, color: color, size: 16),
        ),
      ),
    );
  }

  Widget _compactField({
    required String label,
    required String value,
    required ValueChanged<String> onChanged,
  }) {
    return TextField(
      controller: TextEditingController(text: value),
      onChanged: onChanged,
      style: const TextStyle(color: Colors.white, fontSize: 12),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(color: Colors.grey.shade500, fontSize: 11),
        isDense: true,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        enabledBorder: OutlineInputBorder(
          borderSide: BorderSide(color: Colors.grey.shade700),
          borderRadius: BorderRadius.circular(4),
        ),
        focusedBorder: OutlineInputBorder(
          borderSide: const BorderSide(color: _barrierColor),
          borderRadius: BorderRadius.circular(4),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Paintable grid
  // ---------------------------------------------------------------------------

  Widget _buildGrid() {
    return ListenableBuilder(
      listenable: state,
      builder: (context, _) {
        return LayoutBuilder(
          builder: (context, constraints) {
            final cellSize = constraints.maxWidth / gridSize;
            return GestureDetector(
              onPanStart: (d) => _paintAt(d.localPosition, cellSize),
              onPanUpdate: (d) => _paintAt(d.localPosition, cellSize),
              onTapDown: (d) => _paintAt(d.localPosition, cellSize),
              child: CustomPaint(
                size: Size(
                  constraints.maxWidth,
                  cellSize * gridSize,
                ),
                painter: _GridPainter(state: state, cellSize: cellSize),
              ),
            );
          },
        );
      },
    );
  }

  void _paintAt(Offset position, double cellSize) {
    final x = (position.dx / cellSize).floor();
    final y = (position.dy / cellSize).floor();
    state.paintTile(x, y);
  }

  // ---------------------------------------------------------------------------
  // Footer — load, import, export
  // ---------------------------------------------------------------------------

  Widget _buildFooter(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: const BoxDecoration(
        color: _headerBg,
        border: Border(top: BorderSide(color: _border)),
      ),
      child: Column(
        children: [
          // Load existing map dropdown
          SizedBox(
            width: double.infinity,
            child: DropdownButtonHideUnderline(
              child: DropdownButton<int>(
                isExpanded: true,
                hint: const Text('Load existing map...',
                    style: TextStyle(color: Colors.grey, fontSize: 13)),
                dropdownColor: _headerBg,
                iconEnabledColor: Colors.grey,
                items: [
                  for (var i = 0; i < allMaps.length; i++)
                    DropdownMenuItem(
                      value: i,
                      child: Text(allMaps[i].name,
                          style: const TextStyle(
                              color: Colors.white, fontSize: 13)),
                    ),
                ],
                onChanged: (index) {
                  if (index != null) state.loadFromGameMap(allMaps[index]);
                },
              ),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _showImportDialog(context),
                  icon: const Icon(Icons.upload, size: 14),
                  label: const Text('Import', style: TextStyle(fontSize: 12)),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.grey.shade300,
                    side: BorderSide(color: Colors.grey.shade700),
                    padding: const EdgeInsets.symmetric(vertical: 8),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () => _exportToClipboard(context),
                  icon: const Icon(Icons.copy, size: 14),
                  label: const Text('Export', style: TextStyle(fontSize: 12)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _barrierColor,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 8),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _showImportDialog(BuildContext context) {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _headerBg,
        title: const Text('Import ASCII Map',
            style: TextStyle(color: Colors.white)),
        content: SizedBox(
          width: 500,
          height: 400,
          child: TextField(
            controller: controller,
            maxLines: null,
            expands: true,
            style: const TextStyle(
                color: Colors.white, fontFamily: 'monospace', fontSize: 10),
            decoration: InputDecoration(
              hintText: 'Paste ASCII art here (50x50, .#ST)...',
              hintStyle: TextStyle(color: Colors.grey.shade600),
              border: OutlineInputBorder(
                  borderSide: BorderSide(color: Colors.grey.shade700)),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              state.loadFromAscii(controller.text);
              Navigator.pop(ctx);
            },
            child: const Text('Import'),
          ),
        ],
      ),
    );
  }

  void _exportToClipboard(BuildContext context) {
    final ascii = state.toAsciiString();
    Clipboard.setData(ClipboardData(text: ascii));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('ASCII map copied to clipboard'),
        duration: Duration(seconds: 2),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Custom painter for the mini-grid
// ---------------------------------------------------------------------------

class _GridPainter extends CustomPainter {
  _GridPainter({required this.state, required this.cellSize});

  final MapEditorState state;
  final double cellSize;

  static const _openColor = Color(0xFF2A2A2A);
  static const _barrierColor = Color(0xFF4444FF);
  static const _spawnColor = Color(0xFF00FF41);
  static const _terminalColor = Color(0xFFD97757);
  static const _gridLineColor = Color(0xFF333333);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint();
    final linePaint = Paint()
      ..color = _gridLineColor
      ..strokeWidth = 0.5;

    for (var y = 0; y < gridSize; y++) {
      for (var x = 0; x < gridSize; x++) {
        final tile = state.tileAt(x, y);
        paint.color = _colorForTile(tile);
        canvas.drawRect(
          Rect.fromLTWH(x * cellSize, y * cellSize, cellSize, cellSize),
          paint,
        );
      }
    }

    // Grid lines
    for (var i = 0; i <= gridSize; i++) {
      final offset = i * cellSize;
      canvas.drawLine(
          Offset(offset, 0), Offset(offset, size.height), linePaint);
      canvas.drawLine(
          Offset(0, offset), Offset(size.width, offset), linePaint);
    }
  }

  Color _colorForTile(TileType tile) {
    switch (tile) {
      case TileType.open:
        return _openColor;
      case TileType.barrier:
        return _barrierColor;
      case TileType.spawn:
        return _spawnColor;
      case TileType.terminal:
        return _terminalColor;
    }
  }

  @override
  bool shouldRepaint(_GridPainter oldDelegate) => true;
}
