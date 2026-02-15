import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:tech_world/flame/maps/game_map.dart';
import 'package:tech_world/flame/maps/predefined_maps.dart';
import 'package:tech_world/flame/shared/constants.dart';
import 'package:tech_world/map_editor/map_editor_state.dart';
import 'package:tech_world/map_editor/tile_colors.dart';

/// Sidebar panel for the visual map editor.
///
/// Provides a toolbar for selecting paint tools, a paintable mini-grid, and
/// import/export controls. Follows the same dark-theme pattern as
/// [CodeEditorPanel].
class MapEditorPanel extends StatelessWidget {
  const MapEditorPanel({
    required this.state,
    required this.onClose,
    this.referenceMap,
    super.key,
  });

  final MapEditorState state;
  final VoidCallback onClose;

  /// Optional game map to render as a faint reference layer under the grid.
  final GameMap? referenceMap;

  static const _headerBg = Color(0xFF2D2D2D);
  static const _panelBg = Color(0xFF1E1E1E);
  static const _border = Color(0xFF3D3D3D);

  @override
  Widget build(BuildContext context) {
    return Container(
      color: _panelBg,
      child: Column(
        children: [
          _buildHeader(),
          _MapToolbar(state: state),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                // Scale so the game grid area (gridSize * gridSquareSize pixels)
                // maps exactly to the sidebar grid width.
                final cellSize = constraints.maxWidth / gridSize;
                final imageScale = cellSize / gridSquareSizeDouble;
                return Stack(
                  clipBehavior: Clip.hardEdge,
                  children: [
                    // Paintable grid
                    _buildGrid(),
                    // PNG map image on top, scaled to align with grid
                    Positioned(
                      top: 0,
                      left: 0,
                      child: IgnorePointer(
                        child: Opacity(
                          opacity: 0.5,
                          child: Transform.scale(
                            scale: imageScale,
                            alignment: Alignment.topLeft,
                            child: Image.asset(
                              'assets/images/single_room.png',
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
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
              color: TileColors.barrier.withValues(alpha: 0.2),
              shape: BoxShape.circle,
              border: Border.all(color: TileColors.barrier, width: 2),
            ),
            child: const Center(
              child:
                  Icon(Icons.grid_on, color: TileColors.barrier, size: 16),
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
                painter: _GridPainter(
                  state: state,
                  cellSize: cellSize,
                  referenceMap: referenceMap,
                ),
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
                    backgroundColor: TileColors.barrier,
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
// Toolbar — StatefulWidget to properly manage TextEditingControllers
// ---------------------------------------------------------------------------

class _MapToolbar extends StatefulWidget {
  const _MapToolbar({required this.state});

  final MapEditorState state;

  @override
  State<_MapToolbar> createState() => _MapToolbarState();
}

class _MapToolbarState extends State<_MapToolbar> {
  late final TextEditingController _nameController;
  late final TextEditingController _idController;

  static const _headerBg = Color(0xFF2D2D2D);
  static const _border = Color(0xFF3D3D3D);

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.state.mapName);
    _idController = TextEditingController(text: widget.state.mapId);
    widget.state.addListener(_onStateChanged);
  }

  @override
  void dispose() {
    widget.state.removeListener(_onStateChanged);
    _nameController.dispose();
    _idController.dispose();
    super.dispose();
  }

  void _onStateChanged() {
    // Update controllers when state changes externally (e.g., loading a map),
    // but only if the value actually differs to avoid cursor jumps.
    if (_nameController.text != widget.state.mapName) {
      _nameController.text = widget.state.mapName;
    }
    if (_idController.text != widget.state.mapId) {
      _idController.text = widget.state.mapId;
    }
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
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
                  TileColors.barrier),
              const SizedBox(width: 4),
              _toolButton(EditorTool.spawn, Icons.my_location, 'Spawn',
                  TileColors.spawn),
              const SizedBox(width: 4),
              _toolButton(EditorTool.terminal, Icons.terminal, 'Terminal',
                  TileColors.terminal),
              const SizedBox(width: 4),
              _toolButton(EditorTool.eraser, Icons.cleaning_services, 'Eraser',
                  Colors.grey),
              const Spacer(),
              IconButton(
                onPressed: widget.state.clearGrid,
                icon: const Icon(Icons.delete_sweep, size: 18),
                color: Colors.redAccent,
                tooltip: 'Clear grid',
                iconSize: 18,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
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
                  controller: _nameController,
                  onChanged: widget.state.setMapName,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _compactField(
                  label: 'ID',
                  controller: _idController,
                  onChanged: widget.state.setMapId,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _toolButton(
      EditorTool tool, IconData icon, String tooltip, Color color) {
    final selected = widget.state.currentTool == tool;
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: () => widget.state.setTool(tool),
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
    required TextEditingController controller,
    required ValueChanged<String> onChanged,
  }) {
    return TextField(
      controller: controller,
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
          borderSide: const BorderSide(color: TileColors.barrier),
          borderRadius: BorderRadius.circular(4),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Custom painter for the mini-grid
// ---------------------------------------------------------------------------

class _GridPainter extends CustomPainter {
  _GridPainter({
    required this.state,
    required this.cellSize,
    this.referenceMap,
  });

  final MapEditorState state;
  final double cellSize;
  final GameMap? referenceMap;

  // Pre-compute reference map lookup for O(1) access.
  late final Set<Point<int>> _refBarriers =
      referenceMap?.barriers.toSet() ?? {};
  late final Set<Point<int>> _refTerminals =
      referenceMap?.terminals.toSet() ?? {};

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint();
    final linePaint = Paint()
      ..color = TileColors.gridLine
      ..strokeWidth = 0.5;

    // Draw reference map as underlay, then editable grid on top.
    for (var y = 0; y < gridSize; y++) {
      for (var x = 0; x < gridSize; x++) {
        final rect =
            Rect.fromLTWH(x * cellSize, y * cellSize, cellSize, cellSize);

        // Reference layer — draw every cell so the full map shape is visible.
        if (referenceMap != null) {
          final pt = Point(x, y);
          if (_refBarriers.contains(pt)) {
            paint.color = const Color(0xFF333399); // dim blue
          } else if (_refTerminals.contains(pt)) {
            paint.color = const Color(0xFF805030); // dim orange
          } else if (referenceMap!.spawnPoint == pt) {
            paint.color = const Color(0xFF206020); // dim green
          } else {
            paint.color = const Color(0xFF2A3A2A); // dark grass
          }
          canvas.drawRect(rect, paint);
        }

        // Editable grid on top.
        final tile = state.tileAt(x, y);
        if (tile != TileType.open) {
          paint.color = _colorForTile(tile);
          canvas.drawRect(rect, paint);
        }
      }
    }

    // Light grid lines
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
        return TileColors.open;
      case TileType.barrier:
        return TileColors.barrier;
      case TileType.spawn:
        return TileColors.spawn;
      case TileType.terminal:
        return TileColors.terminal;
    }
  }

  @override
  bool shouldRepaint(_GridPainter oldDelegate) => true;
}
