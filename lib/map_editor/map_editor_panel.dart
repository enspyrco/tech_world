import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:tech_world/flame/maps/game_map.dart';
import 'package:tech_world/flame/maps/generators/map_generator.dart';
import 'package:tech_world/flame/maps/predefined_maps.dart';
import 'package:tech_world/flame/shared/constants.dart';
import 'package:tech_world/map_editor/available_backgrounds.dart';
import 'package:tech_world/map_editor/map_editor_state.dart';
import 'package:tech_world/map_editor/tile_colors.dart';
import 'package:tech_world/map_editor/tile_palette.dart';

/// Sidebar panel for the visual map editor.
///
/// Provides a toolbar for selecting paint tools, a paintable mini-grid, and
/// import/export controls. Supports layer switching between structure (barriers,
/// spawn, terminals) and tile layers (floor, objects).
class MapEditorPanel extends StatelessWidget {
  const MapEditorPanel({
    required this.state,
    required this.onClose,
    this.referenceMap,
    this.playerPosition,
    this.onSave,
    this.canEdit = true,
    super.key,
  });

  final MapEditorState state;
  final Future<void> Function() onClose;

  /// Optional game map to render as a faint reference layer under the grid.
  final GameMap? referenceMap;

  /// Current player position in grid coordinates, shown as a marker on the grid.
  final ValueListenable<Point<int>>? playerPosition;

  /// Called when the user taps the Save button. Null hides the button.
  final Future<void> Function()? onSave;

  /// Whether the current user can edit (owner or editor). Controls paint tools.
  final bool canEdit;

  static const _headerBg = Color(0xFF2D2D2D);
  static const _panelBg = Color(0xFF1E1E1E);
  static const _border = Color(0xFF3D3D3D);

  @override
  Widget build(BuildContext context) {
    return Container(
      color: _panelBg,
      child: ListenableBuilder(
        listenable: state,
        builder: (context, _) {
          return Column(
            children: [
              _buildHeader(),
              _LayerTabs(state: state),
              _MapToolbar(state: state),
              Expanded(
                child: state.activeLayer == ActiveLayer.structure
                    ? _buildGridArea()
                    : _buildTileLayerEditor(),
              ),
              _buildFooter(context),
            ],
          );
        },
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
  // Grid area (structure layer) — with reference image overlay
  // ---------------------------------------------------------------------------

  Widget _buildGridArea() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final cellSize = constraints.maxWidth / gridSize;
        final imageScale = cellSize / gridSquareSizeDouble;
        return Stack(
          clipBehavior: Clip.hardEdge,
          children: [
            _buildGrid(),
            if (state.backgroundImage != null)
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
                        'assets/images/${state.backgroundImage}',
                      ),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  // ---------------------------------------------------------------------------
  // Tile layer editor — grid + tile palette side by side
  // ---------------------------------------------------------------------------

  Widget _buildTileLayerEditor() {
    return Column(
      children: [
        // Paintable grid (for tile layers)
        Expanded(child: _buildGrid()),
        // Tile palette at the bottom
        Container(
          height: 160,
          decoration: const BoxDecoration(
            border: Border(top: BorderSide(color: _border)),
          ),
          child: TilePalette(state: state),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Paintable grid
  // ---------------------------------------------------------------------------

  Widget _buildGrid() {
    final listenable = playerPosition != null
        ? Listenable.merge([state, playerPosition!])
        : state as Listenable;
    return ListenableBuilder(
      listenable: listenable,
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
                  playerPosition: playerPosition?.value,
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

    if (state.activeLayer == ActiveLayer.structure) {
      state.paintTile(x, y);
    } else {
      state.paintTileRef(x, y);
    }
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
          // Save to Firestore
          if (onSave != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _SaveButton(onSave: onSave!, roomId: state.roomId),
            ),
          // Generate procedural map
          _GenerateSection(state: state),
          const SizedBox(height: 8),
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
// Layer tabs — switch between Structure, Floor, Objects
// ---------------------------------------------------------------------------

class _LayerTabs extends StatelessWidget {
  const _LayerTabs({required this.state});

  final MapEditorState state;

  static const _headerBg = Color(0xFF2D2D2D);
  static const _border = Color(0xFF3D3D3D);
  static const _selectedColor = Color(0xFF4FC3F7);

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: _headerBg,
        border: Border(bottom: BorderSide(color: _border)),
      ),
      child: Row(
        children: [
          _tab('Structure', ActiveLayer.structure, Icons.grid_on),
          _tab('Floor', ActiveLayer.floor, Icons.layers),
          _tab('Objects', ActiveLayer.objects, Icons.category),
        ],
      ),
    );
  }

  Widget _tab(String label, ActiveLayer layer, IconData icon) {
    final isSelected = state.activeLayer == layer;
    return Expanded(
      child: InkWell(
        onTap: () => state.setActiveLayer(layer),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: isSelected ? _selectedColor : Colors.transparent,
                width: 2,
              ),
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 14,
                color: isSelected ? _selectedColor : Colors.grey,
              ),
              const SizedBox(height: 2),
              Text(
                label,
                style: TextStyle(
                  color: isSelected ? _selectedColor : Colors.grey,
                  fontSize: 10,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                ),
              ),
            ],
          ),
        ),
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
    final isStructureLayer =
        widget.state.activeLayer == ActiveLayer.structure;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: const BoxDecoration(
        color: _headerBg,
        border: Border(bottom: BorderSide(color: _border)),
      ),
      child: Column(
        children: [
          // Tool buttons — only shown for structure layer
          if (isStructureLayer)
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
                _toolButton(EditorTool.eraser, Icons.cleaning_services,
                    'Eraser', Colors.grey),
                const Spacer(),
                IconButton(
                  onPressed: widget.state.clearGrid,
                  icon: const Icon(Icons.delete_sweep, size: 18),
                  color: Colors.redAccent,
                  tooltip: 'Clear grid',
                  iconSize: 18,
                  constraints:
                      const BoxConstraints(minWidth: 32, minHeight: 32),
                  padding: EdgeInsets.zero,
                ),
              ],
            ),
          // Tile brush info — shown for tile layers
          if (!isStructureLayer)
            _buildTileBrushInfo(),
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
          const SizedBox(height: 6),
          // Background image selector
          _buildBackgroundDropdown(),
        ],
      ),
    );
  }

  Widget _buildBackgroundDropdown() {
    return Row(
      children: [
        Text(
          'BG',
          style: TextStyle(color: Colors.grey.shade500, fontSize: 11),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              isExpanded: true,
              value: widget.state.backgroundImage,
              dropdownColor: _headerBg,
              iconEnabledColor: Colors.grey,
              iconSize: 16,
              isDense: true,
              style: const TextStyle(color: Colors.white, fontSize: 12),
              items: [
                const DropdownMenuItem<String>(
                  child:
                      Text('None', style: TextStyle(color: Colors.grey)),
                ),
                for (final bg in availableBackgrounds)
                  DropdownMenuItem<String>(
                    value: bg.filename,
                    child: Text(bg.label),
                  ),
              ],
              onChanged: (value) =>
                  widget.state.setBackgroundImage(value),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTileBrushInfo() {
    final brush = widget.state.currentBrush;
    final layerName = widget.state.activeLayer == ActiveLayer.floor
        ? 'Floor'
        : 'Objects';

    String label;
    if (brush == null) {
      label = '$layerName — Eraser';
    } else if (brush.isMultiTile) {
      label = '$layerName — ${brush.tilesetId} [${brush.width}×${brush.height}]';
    } else {
      final index = brush.startRow * brush.columns + brush.startCol;
      label = '$layerName — ${brush.tilesetId}[$index]';
    }

    return Row(
      children: [
        Icon(
          brush == null ? Icons.cleaning_services : Icons.brush,
          size: 14,
          color: Colors.grey.shade400,
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: TextStyle(
            color: Colors.grey.shade300,
            fontSize: 11,
          ),
        ),
      ],
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
// Save button — saves to Firestore with loading/success feedback
// ---------------------------------------------------------------------------

class _SaveButton extends StatefulWidget {
  const _SaveButton({required this.onSave, this.roomId});

  final Future<void> Function() onSave;
  final String? roomId;

  @override
  State<_SaveButton> createState() => _SaveButtonState();
}

class _SaveButtonState extends State<_SaveButton> {
  bool _saving = false;

  Future<void> _handleSave() async {
    setState(() => _saving = true);
    try {
      await widget.onSave();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Room saved'),
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Save failed: $e'),
            backgroundColor: Colors.red.shade700,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final label = widget.roomId != null ? 'Save Room' : 'Save as New Room';
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: _saving ? null : _handleSave,
        icon: _saving
            ? const SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.save, size: 14),
        label: Text(label, style: const TextStyle(fontSize: 12)),
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF4CAF50),
          foregroundColor: Colors.white,
          disabledBackgroundColor: const Color(0xFF4CAF50).withValues(alpha: 0.5),
          padding: const EdgeInsets.symmetric(vertical: 10),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Generate section — pick algorithm + generate button
// ---------------------------------------------------------------------------

class _GenerateSection extends StatefulWidget {
  const _GenerateSection({required this.state});

  final MapEditorState state;

  @override
  State<_GenerateSection> createState() => _GenerateSectionState();
}

class _GenerateSectionState extends State<_GenerateSection> {
  MapAlgorithm _selected = MapAlgorithm.dungeon;
  int? _lastSeed;

  void _generate() {
    final seed = Random().nextInt(1 << 32);
    final map = generateMap(
      algorithm: _selected,
      config: GeneratorConfig(seed: seed),
    );
    widget.state.loadFromGameMap(map);
    setState(() => _lastSeed = seed);
  }

  void _regenerateWithSeed(int seed) {
    final map = generateMap(
      algorithm: _selected,
      config: GeneratorConfig(seed: seed),
    );
    widget.state.loadFromGameMap(map);
    setState(() => _lastSeed = seed);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: DropdownButtonHideUnderline(
                child: DropdownButton<MapAlgorithm>(
                  isExpanded: true,
                  value: _selected,
                  dropdownColor: const Color(0xFF2D2D2D),
                  iconEnabledColor: Colors.grey,
                  style: const TextStyle(color: Colors.white, fontSize: 13),
                  items: [
                    for (final algo in MapAlgorithm.values)
                      DropdownMenuItem(
                        value: algo,
                        child: Text(algo.displayName),
                      ),
                  ],
                  onChanged: (algo) {
                    if (algo != null) setState(() => _selected = algo);
                  },
                ),
              ),
            ),
            const SizedBox(width: 8),
            ElevatedButton.icon(
              onPressed: _generate,
              icon: const Icon(Icons.casino, size: 14),
              label: const Text('Generate', style: TextStyle(fontSize: 12)),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange.shade700,
                foregroundColor: Colors.white,
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              ),
            ),
          ],
        ),
        if (_lastSeed != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Row(
              children: [
                Text(
                  'Seed: $_lastSeed',
                  style: TextStyle(color: Colors.grey.shade500, fontSize: 10),
                ),
                const SizedBox(width: 4),
                InkWell(
                  onTap: () {
                    Clipboard.setData(
                        ClipboardData(text: _lastSeed.toString()));
                  },
                  child: Icon(Icons.copy, size: 12, color: Colors.grey.shade500),
                ),
                const SizedBox(width: 4),
                InkWell(
                  onTap: () => _regenerateWithSeed(_lastSeed!),
                  child: Icon(Icons.refresh, size: 12,
                      color: Colors.grey.shade500),
                ),
              ],
            ),
          ),
      ],
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
    this.playerPosition,
  });

  final MapEditorState state;
  final double cellSize;
  final GameMap? referenceMap;
  final Point<int>? playerPosition;

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

    final activeLayer = state.activeLayer;

    // Draw reference map as underlay, then editable grid on top.
    for (var y = 0; y < gridSize; y++) {
      for (var x = 0; x < gridSize; x++) {
        final rect =
            Rect.fromLTWH(x * cellSize, y * cellSize, cellSize, cellSize);

        // Reference layer — draw every cell so the full map shape is visible.
        if (referenceMap != null && activeLayer == ActiveLayer.structure) {
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

        if (activeLayer == ActiveLayer.structure) {
          // Editable structure grid on top.
          final tile = state.tileAt(x, y);
          if (tile != TileType.open) {
            paint.color = _colorForTile(tile);
            canvas.drawRect(rect, paint);
          }
        } else {
          // Tile layer view — show colored cells for placed tiles.
          final layerData = activeLayer == ActiveLayer.floor
              ? state.floorLayerData
              : state.objectLayerData;
          final ref = layerData.tileAt(x, y);
          if (ref != null) {
            // Use a deterministic color from the tile index.
            final hue = (ref.tileIndex * 22.5) % 360;
            paint.color =
                HSLColor.fromAHSL(0.7, hue, 0.6, 0.5).toColor();
            canvas.drawRect(rect, paint);
          }

          // Show structure as a dim overlay on tile layers.
          final structTile = state.tileAt(x, y);
          if (structTile != TileType.open) {
            paint.color = _colorForTile(structTile).withValues(alpha: 0.3);
            canvas.drawRect(rect, paint);
          }
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

    // Player position marker
    if (playerPosition != null) {
      final px = playerPosition!.x;
      final py = playerPosition!.y;
      if (px >= 0 && px < gridSize && py >= 0 && py < gridSize) {
        final center = Offset(
          (px + 0.5) * cellSize,
          (py + 0.5) * cellSize,
        );
        paint
          ..color = const Color(0xFFFFFFFF)
          ..style = PaintingStyle.fill;
        canvas.drawCircle(center, cellSize * 0.4, paint);
        paint
          ..color = const Color(0xFF4FC3F7)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5;
        canvas.drawCircle(center, cellSize * 0.4, paint);
        paint.style = PaintingStyle.fill;
      }
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
