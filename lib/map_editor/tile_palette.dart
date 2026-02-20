import 'dart:math';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:tech_world/flame/tiles/predefined_tilesets.dart';
import 'package:tech_world/flame/tiles/tile_brush.dart';
import 'package:tech_world/flame/tiles/tileset.dart';
import 'package:tech_world/map_editor/map_editor_state.dart';

/// Scrollable tile picker showing available tiles from loaded tilesets.
///
/// Each tileset is rendered as a single sprite sheet image scaled to fit the
/// palette width. Tapping a tile selects it as a 1×1 brush. Long-pressing and
/// dragging selects a rectangular multi-tile brush. This avoids conflict with
/// the ListView scroll gesture.
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
                    _TilesetSection(tileset: tileset, state: state),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildEraserButton() {
    final isSelected = state.currentBrush == null;
    return InkWell(
      onTap: () => state.setBrush(null),
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
}

// ---------------------------------------------------------------------------
// Tileset section — StatefulWidget for local drag state
// ---------------------------------------------------------------------------

class _TilesetSection extends StatefulWidget {
  const _TilesetSection({required this.tileset, required this.state});

  final Tileset tileset;
  final MapEditorState state;

  @override
  State<_TilesetSection> createState() => _TilesetSectionState();
}

class _TilesetSectionState extends State<_TilesetSection> {
  static const _selectedColor = Color(0xFF4FC3F7);

  /// Start of the drag selection (col, row in the tileset grid).
  int? _dragStartCol;
  int? _dragStartRow;

  /// Current end of the drag selection.
  int? _dragEndCol;
  int? _dragEndRow;

  /// Whether a long-press drag is active.
  bool _isDragging = false;

  /// Cached tile display size for use in gesture callbacks.
  double _tileDisplaySize = 0;

  Tileset get _tileset => widget.tileset;
  MapEditorState get _state => widget.state;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final availableWidth = constraints.maxWidth;
        _tileDisplaySize = availableWidth / _tileset.columns;
        final sheetHeight = _tileset.rows * _tileDisplaySize;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 4, top: 8),
              child: Text(
                _tileset.name,
                style: TextStyle(
                  color: Colors.grey.shade400,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            RawGestureDetector(
              gestures: <Type, GestureRecognizerFactory>{
                TapGestureRecognizer:
                    GestureRecognizerFactoryWithHandlers<TapGestureRecognizer>(
                  () => TapGestureRecognizer(),
                  (instance) {
                    instance.onTapUp = (details) =>
                        _onTap(details.localPosition, _tileDisplaySize);
                  },
                ),
                LongPressGestureRecognizer:
                    GestureRecognizerFactoryWithHandlers<
                        LongPressGestureRecognizer>(
                  // 150ms hold — much snappier than the default 500ms,
                  // but still long enough to distinguish from scroll intent.
                  () => LongPressGestureRecognizer(
                      duration: const Duration(milliseconds: 150)),
                  (instance) {
                    instance.onLongPressStart = (details) {
                      _onLongPressStart(
                          details.localPosition, _tileDisplaySize);
                    };
                    instance.onLongPressMoveUpdate = (details) {
                      _onLongPressMove(
                          details.localPosition, _tileDisplaySize);
                    };
                    instance.onLongPressEnd = (_) {
                      _onLongPressEnd(_tileDisplaySize);
                    };
                  },
                ),
              },
              child: Stack(
                children: [
                  SizedBox(
                    width: availableWidth,
                    height: sheetHeight,
                    child: Image.asset(
                      'assets/images/${_tileset.imagePath}',
                      fit: BoxFit.fill,
                      filterQuality: FilterQuality.none,
                    ),
                  ),
                  // Selection highlight — during drag or for current brush
                  _buildSelectionHighlight(_tileDisplaySize),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  /// Build the cyan selection rectangle overlay.
  Widget _buildSelectionHighlight(double tileDisplaySize) {
    int? selCol, selRow, selW, selH;

    if (_isDragging &&
        _dragStartCol != null &&
        _dragEndCol != null) {
      // Live drag preview.
      selCol = min(_dragStartCol!, _dragEndCol!);
      selRow = min(_dragStartRow!, _dragEndRow!);
      selW = (_dragStartCol! - _dragEndCol!).abs() + 1;
      selH = (_dragStartRow! - _dragEndRow!).abs() + 1;
    } else {
      // Show the committed brush selection.
      final brush = _state.currentBrush;
      if (brush != null && brush.tilesetId == _tileset.id) {
        selCol = brush.startCol;
        selRow = brush.startRow;
        selW = brush.width;
        selH = brush.height;
      }
    }

    if (selCol == null) return const SizedBox.shrink();

    return Positioned(
      left: selCol * tileDisplaySize,
      top: selRow! * tileDisplaySize,
      child: IgnorePointer(
        child: Container(
          width: selW! * tileDisplaySize,
          height: selH! * tileDisplaySize,
          decoration: BoxDecoration(
            border: Border.all(color: _selectedColor, width: 2),
          ),
        ),
      ),
    );
  }

  // -------------------------------------------------------------------------
  // Gesture handlers
  // -------------------------------------------------------------------------

  /// Tap → single tile (1×1) brush.
  void _onTap(Offset pos, double tileDisplaySize) {
    final col = (pos.dx / tileDisplaySize).floor().clamp(0, _tileset.columns - 1);
    final row = (pos.dy / tileDisplaySize).floor().clamp(0, _tileset.rows - 1);

    _state.setBrush(TileBrush(
      tilesetId: _tileset.id,
      startCol: col,
      startRow: row,
      columns: _tileset.columns,
    ));
  }

  /// Long press start → begin rectangular selection.
  void _onLongPressStart(Offset pos, double tileDisplaySize) {
    final col = (pos.dx / tileDisplaySize).floor().clamp(0, _tileset.columns - 1);
    final row = (pos.dy / tileDisplaySize).floor().clamp(0, _tileset.rows - 1);

    setState(() {
      _isDragging = true;
      _dragStartCol = col;
      _dragStartRow = row;
      _dragEndCol = col;
      _dragEndRow = row;
    });
  }

  /// Long press move → update selection rectangle.
  void _onLongPressMove(Offset pos, double tileDisplaySize) {
    if (!_isDragging) return;

    final col = (pos.dx / tileDisplaySize).floor().clamp(0, _tileset.columns - 1);
    final row = (pos.dy / tileDisplaySize).floor().clamp(0, _tileset.rows - 1);

    if (col != _dragEndCol || row != _dragEndRow) {
      setState(() {
        _dragEndCol = col;
        _dragEndRow = row;
      });
    }
  }

  /// Long press end → commit rectangular brush.
  void _onLongPressEnd(double tileDisplaySize) {
    if (!_isDragging) return;

    final startCol = min(_dragStartCol!, _dragEndCol!);
    final startRow = min(_dragStartRow!, _dragEndRow!);
    final w = (_dragStartCol! - _dragEndCol!).abs() + 1;
    final h = (_dragStartRow! - _dragEndRow!).abs() + 1;

    _state.setBrush(TileBrush(
      tilesetId: _tileset.id,
      startCol: startCol,
      startRow: startRow,
      columns: _tileset.columns,
      width: w,
      height: h,
    ));

    setState(() {
      _isDragging = false;
      _dragStartCol = null;
      _dragStartRow = null;
      _dragEndCol = null;
      _dragEndRow = null;
    });
  }
}
