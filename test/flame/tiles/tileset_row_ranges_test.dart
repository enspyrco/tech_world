import 'package:flutter_test/flutter_test.dart';
import 'package:tech_world/flame/tiles/predefined_tilesets.dart';
import 'package:tech_world/flame/tiles/tile_brush.dart';
import 'package:tech_world/flame/tiles/tileset.dart';
import 'package:tech_world/map_editor/map_editor_state.dart';

void main() {
  group('Tileset.rowRangesForLayer', () {
    test('returns configured ranges for roomBuilderOffice', () {
      expect(
        roomBuilderOffice.rowRangesForLayer(ActiveLayer.objects),
        [(0, 5)],
      );
      expect(
        roomBuilderOffice.rowRangesForLayer(ActiveLayer.floor),
        [(5, 14)],
      );
    });

    test('returns configured ranges for extSchool', () {
      expect(
        extSchool.rowRangesForLayer(ActiveLayer.objects),
        [(0, 34), (58, 99)],
      );
      expect(
        extSchool.rowRangesForLayer(ActiveLayer.floor),
        [(34, 58), (99, 116)],
      );
    });

    test('returns full range when no config', () {
      // modernOffice has no layerRowRanges configured.
      expect(
        modernOffice.rowRangesForLayer(ActiveLayer.objects),
        [(0, 53)],
      );
    });

    test('returns full range for unconfigured layer', () {
      // roomBuilderOffice has no structure layer config.
      expect(
        roomBuilderOffice.rowRangesForLayer(ActiveLayer.structure),
        [(0, 14)],
      );
    });
  });

  group('Tileset.isRowVisibleForLayer', () {
    test('roomBuilderOffice: wall rows visible on objects only', () {
      // Row 0 (walls) → objects yes, floor no.
      expect(
        roomBuilderOffice.isRowVisibleForLayer(0, ActiveLayer.objects),
        isTrue,
      );
      expect(
        roomBuilderOffice.isRowVisibleForLayer(0, ActiveLayer.floor),
        isFalse,
      );
      // Row 4 (last wall row) → objects yes, floor no.
      expect(
        roomBuilderOffice.isRowVisibleForLayer(4, ActiveLayer.objects),
        isTrue,
      );
      expect(
        roomBuilderOffice.isRowVisibleForLayer(4, ActiveLayer.floor),
        isFalse,
      );
    });

    test('roomBuilderOffice: floor rows visible on floor only', () {
      // Row 5 (first floor row) → floor yes, objects no.
      expect(
        roomBuilderOffice.isRowVisibleForLayer(5, ActiveLayer.floor),
        isTrue,
      );
      expect(
        roomBuilderOffice.isRowVisibleForLayer(5, ActiveLayer.objects),
        isFalse,
      );
      // Row 13 (last row) → floor yes, objects no.
      expect(
        roomBuilderOffice.isRowVisibleForLayer(13, ActiveLayer.floor),
        isTrue,
      );
      expect(
        roomBuilderOffice.isRowVisibleForLayer(13, ActiveLayer.objects),
        isFalse,
      );
    });

    test('extSchool: multi-range visibility', () {
      // Row 0 (building facade) → objects yes.
      expect(
        extSchool.isRowVisibleForLayer(0, ActiveLayer.objects),
        isTrue,
      );
      // Row 34 (basketball courts) → floor yes, objects no.
      expect(
        extSchool.isRowVisibleForLayer(34, ActiveLayer.floor),
        isTrue,
      );
      expect(
        extSchool.isRowVisibleForLayer(34, ActiveLayer.objects),
        isFalse,
      );
      // Row 58 (furniture/props) → objects yes, floor no.
      expect(
        extSchool.isRowVisibleForLayer(58, ActiveLayer.objects),
        isTrue,
      );
      expect(
        extSchool.isRowVisibleForLayer(58, ActiveLayer.floor),
        isFalse,
      );
      // Row 99 (soccer fields) → floor yes, objects no.
      expect(
        extSchool.isRowVisibleForLayer(99, ActiveLayer.floor),
        isTrue,
      );
      expect(
        extSchool.isRowVisibleForLayer(99, ActiveLayer.objects),
        isFalse,
      );
    });
  });

  group('Tileset.visualRowToActualRow', () {
    test('single range maps directly', () {
      // roomBuilderOffice floor: [(5, 14)]
      final ranges = roomBuilderOffice.rowRangesForLayer(ActiveLayer.floor);
      expect(Tileset.visualRowToActualRow(0, ranges), 5);
      expect(Tileset.visualRowToActualRow(4, ranges), 9);
      expect(Tileset.visualRowToActualRow(8, ranges), 13);
    });

    test('multi-range maps across gaps (extSchool floor)', () {
      // extSchool floor: [(34, 58), (99, 116)]
      // Range 1: 24 rows (34..57), visual rows 0..23
      // Range 2: 17 rows (99..115), visual rows 24..40
      final ranges = extSchool.rowRangesForLayer(ActiveLayer.floor);
      expect(Tileset.visualRowToActualRow(0, ranges), 34);
      expect(Tileset.visualRowToActualRow(23, ranges), 57);
      expect(Tileset.visualRowToActualRow(24, ranges), 99);
      expect(Tileset.visualRowToActualRow(40, ranges), 115);
    });

    test('multi-range maps across gaps (extSchool objects)', () {
      // extSchool objects: [(0, 34), (58, 99)]
      // Range 1: 34 rows (0..33), visual rows 0..33
      // Range 2: 41 rows (58..98), visual rows 34..74
      final ranges = extSchool.rowRangesForLayer(ActiveLayer.objects);
      expect(Tileset.visualRowToActualRow(0, ranges), 0);
      expect(Tileset.visualRowToActualRow(33, ranges), 33);
      expect(Tileset.visualRowToActualRow(34, ranges), 58);
      expect(Tileset.visualRowToActualRow(74, ranges), 98);
    });

    test('clamps to last visible row when visual row exceeds total', () {
      final ranges = roomBuilderOffice.rowRangesForLayer(ActiveLayer.objects);
      // Only 5 visible rows (0..4), visual row 10 → clamp to 4.
      expect(Tileset.visualRowToActualRow(10, ranges), 4);
    });
  });

  group('Tileset.actualRowToVisualRow', () {
    test('single range maps inversely', () {
      final ranges = roomBuilderOffice.rowRangesForLayer(ActiveLayer.floor);
      expect(Tileset.actualRowToVisualRow(5, ranges), 0);
      expect(Tileset.actualRowToVisualRow(9, ranges), 4);
      expect(Tileset.actualRowToVisualRow(13, ranges), 8);
    });

    test('returns null for hidden rows', () {
      // Row 0 is not visible on the floor layer of roomBuilderOffice.
      final ranges = roomBuilderOffice.rowRangesForLayer(ActiveLayer.floor);
      expect(Tileset.actualRowToVisualRow(0, ranges), isNull);
      expect(Tileset.actualRowToVisualRow(4, ranges), isNull);
    });

    test('multi-range inverse (extSchool floor)', () {
      final ranges = extSchool.rowRangesForLayer(ActiveLayer.floor);
      // Row 34 → visual 0, row 57 → visual 23
      expect(Tileset.actualRowToVisualRow(34, ranges), 0);
      expect(Tileset.actualRowToVisualRow(57, ranges), 23);
      // Row 99 → visual 24, row 115 → visual 40
      expect(Tileset.actualRowToVisualRow(99, ranges), 24);
      expect(Tileset.actualRowToVisualRow(115, ranges), 40);
      // Row 58 (furniture — hidden on floor) → null
      expect(Tileset.actualRowToVisualRow(58, ranges), isNull);
    });
  });

  group('Tileset.clampSelectionToRange', () {
    test('no clamping when both rows in same range', () {
      // extSchool objects: [(0, 34), (58, 99)]
      // Visual rows 0–33 map to actual 0–33 (first range).
      final ranges = extSchool.rowRangesForLayer(ActiveLayer.objects);
      final (start, end) = Tileset.clampSelectionToRange(5, 10, ranges);
      expect(start, 5);
      expect(end, 10);
    });

    test('clamps drag across range boundary to start range', () {
      // extSchool objects: [(0, 34), (58, 99)]
      // Visual 0–33 = actual 0–33, visual 34–74 = actual 58–98.
      // Drag from visual 30 (actual 30, range 1) to visual 40 (actual 64, range 2).
      final ranges = extSchool.rowRangesForLayer(ActiveLayer.objects);
      final (start, end) = Tileset.clampSelectionToRange(30, 40, ranges);
      // Clamped to range 1: visual 0–33.
      expect(start, 30);
      expect(end, 33);
    });

    test('clamps reverse drag across range boundary', () {
      // Drag from visual 40 (range 2) to visual 30 (range 1).
      final ranges = extSchool.rowRangesForLayer(ActiveLayer.objects);
      final (start, end) = Tileset.clampSelectionToRange(40, 30, ranges);
      // Clamped to range 2: visual 34–74.
      expect(start, 34);
      expect(end, 40);
    });

    test('single range never clamps', () {
      // roomBuilderOffice floor: [(5, 14)] → 9 visible rows, visual 0–8.
      final ranges = roomBuilderOffice.rowRangesForLayer(ActiveLayer.floor);
      final (start, end) = Tileset.clampSelectionToRange(0, 8, ranges);
      expect(start, 0);
      expect(end, 8);
    });
  });

  group('MapEditorState.setActiveLayer brush clearing', () {
    test('clears brush when rows not visible on new layer', () {
      final state = MapEditorState();
      // Select a wall tile (row 2) on objects layer.
      state.setActiveLayer(ActiveLayer.objects);
      state.setBrush(const TileBrush(
        tilesetId: 'room_builder_office',
        startCol: 0,
        startRow: 2,
        columns: 16,
      ));
      expect(state.currentBrush, isNotNull);

      // Switch to floor — row 2 is wall-only, should clear.
      state.setActiveLayer(ActiveLayer.floor);
      expect(state.currentBrush, isNull);
    });

    test('keeps brush when rows are visible on new layer', () {
      final state = MapEditorState();
      // Select a floor tile (row 7) on floor layer.
      state.setActiveLayer(ActiveLayer.floor);
      state.setBrush(const TileBrush(
        tilesetId: 'room_builder_office',
        startCol: 0,
        startRow: 7,
        columns: 16,
      ));
      expect(state.currentBrush, isNotNull);

      // Stay on floor — should keep.
      state.setActiveLayer(ActiveLayer.floor);
      expect(state.currentBrush, isNotNull);
    });

    test('clears brush when tileset not available on new layer', () {
      final state = MapEditorState();
      // Select a tile from modernOffice (objects-only tileset).
      state.setActiveLayer(ActiveLayer.objects);
      state.setBrush(const TileBrush(
        tilesetId: 'modern_office',
        startCol: 0,
        startRow: 0,
        columns: 16,
      ));
      expect(state.currentBrush, isNotNull);

      // Switch to floor — modernOffice is objects-only, should clear.
      state.setActiveLayer(ActiveLayer.floor);
      expect(state.currentBrush, isNull);
    });

    test('clears multi-tile brush when any row is hidden', () {
      final state = MapEditorState();
      // Select a 1×3 brush spanning rows 3–5 on roomBuilderOffice.
      // Row 3–4 are objects, row 5 is floor — crosses the boundary.
      state.setActiveLayer(ActiveLayer.objects);
      state.setBrush(const TileBrush(
        tilesetId: 'room_builder_office',
        startCol: 0,
        startRow: 3,
        columns: 16,
        height: 3,
      ));
      expect(state.currentBrush, isNotNull);

      // Stay on objects — row 5 is not visible, should clear.
      state.setActiveLayer(ActiveLayer.objects);
      expect(state.currentBrush, isNull);
    });
  });
}
