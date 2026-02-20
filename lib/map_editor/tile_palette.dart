import 'package:flutter/material.dart';
import 'package:tech_world/flame/tiles/predefined_tilesets.dart';
import 'package:tech_world/flame/tiles/tile_ref.dart';
import 'package:tech_world/flame/tiles/tileset.dart';
import 'package:tech_world/map_editor/map_editor_state.dart';

/// Scrollable tile picker showing available tiles from loaded tilesets.
///
/// Tiles are grouped by tileset name. Selecting a tile sets the
/// [MapEditorState.currentTileBrush]. A special "eraser" entry at the top
/// clears the brush (paints null).
class TilePalette extends StatelessWidget {
  const TilePalette({required this.state, super.key});

  final MapEditorState state;

  static const _headerBg = Color(0xFF2D2D2D);
  static const _border = Color(0xFF3D3D3D);
  static const _selectedColor = Color(0xFF4FC3F7);

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: state,
      builder: (context, _) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Eraser button
            _buildEraserButton(),
            const Divider(height: 1, color: _border),
            // Tileset sections
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(8),
                children: [
                  for (final tileset in allTilesets)
                    _buildTilesetSection(tileset),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildEraserButton() {
    final isSelected = state.currentTileBrush == null;
    return InkWell(
      onTap: () => state.setTileBrush(null),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        color: isSelected ? _selectedColor.withValues(alpha: 0.2) : _headerBg,
        child: Row(
          children: [
            Icon(
              Icons.cleaning_services,
              color: isSelected ? _selectedColor : Colors.grey,
              size: 16,
            ),
            const SizedBox(width: 8),
            Text(
              'Eraser',
              style: TextStyle(
                color: isSelected ? _selectedColor : Colors.grey.shade300,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTilesetSection(Tileset tileset) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 4, top: 8),
          child: Text(
            tileset.name,
            style: TextStyle(
              color: Colors.grey.shade400,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        Wrap(
          spacing: 2,
          runSpacing: 2,
          children: [
            for (var i = 0; i < tileset.tileCount; i++)
              _buildTileButton(tileset, i),
          ],
        ),
      ],
    );
  }

  Widget _buildTileButton(Tileset tileset, int index) {
    final ref = TileRef(tilesetId: tileset.id, tileIndex: index);
    final isSelected = state.currentTileBrush == ref;

    return GestureDetector(
      onTap: () => state.setTileBrush(ref),
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          border: Border.all(
            color: isSelected ? _selectedColor : Colors.grey.shade700,
            width: isSelected ? 2 : 1,
          ),
          borderRadius: BorderRadius.circular(4),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(3),
          child: CustomPaint(
            painter: _TilePreviewPainter(
              tileset: tileset,
              tileIndex: index,
            ),
          ),
        ),
      ),
    );
  }
}

/// Paints a single tile from a tileset as a colored rectangle.
///
/// Uses a color derived from the tile index as a placeholder. When real tileset
/// images are available, this should render the actual sprite sub-region.
class _TilePreviewPainter extends CustomPainter {
  _TilePreviewPainter({required this.tileset, required this.tileIndex});

  final Tileset tileset;
  final int tileIndex;

  @override
  void paint(Canvas canvas, Size size) {
    // Generate a deterministic color from the tile index for the test tileset.
    final hue = (tileIndex * 22.5) % 360;
    final color = HSLColor.fromAHSL(1.0, hue, 0.6, 0.5).toColor();

    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Paint()..color = color,
    );

    // Draw index label for identification.
    final textPainter = TextPainter(
      text: TextSpan(
        text: '$tileIndex',
        style: const TextStyle(
          color: Colors.white,
          fontSize: 9,
          fontWeight: FontWeight.bold,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    textPainter.paint(
      canvas,
      Offset(
        (size.width - textPainter.width) / 2,
        (size.height - textPainter.height) / 2,
      ),
    );
  }

  @override
  bool shouldRepaint(_TilePreviewPainter oldDelegate) =>
      tileIndex != oldDelegate.tileIndex ||
      tileset.id != oldDelegate.tileset.id;
}
