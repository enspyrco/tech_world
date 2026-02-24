import 'package:flutter_test/flutter_test.dart';
import 'package:tech_world/flame/tiles/tile_ref.dart';
import 'package:tech_world/map_editor/map_editor_state.dart';
import 'package:tech_world/map_editor/predefined_rules.dart';

void main() {
  late MapEditorState state;

  setUp(() {
    state = MapEditorState();
  });

  group('applyAutomapRules', () {
    test('places shadow tiles below barriers', () {
      state.setTool(EditorTool.barrier);
      state.paintTile(10, 5);

      state.applyAutomapRules(allAutomapRules);

      // Shadow below barrier at (10, 6): cell is open, cell above is barrier.
      final shadow = state.objectLayerData.tileAt(10, 6);
      expect(shadow, isNotNull);
      expect(shadow!.tilesetId, 'room_builder_office');
      expect(shadow.tileIndex, 80);
    });

    test('places trim tiles on top-edge barriers', () {
      state.setTool(EditorTool.barrier);
      state.paintTile(10, 5);

      state.applyAutomapRules(allAutomapRules);

      // Trim on the barrier itself: cell is barrier, cell above is open.
      final trim = state.objectLayerData.tileAt(10, 5);
      expect(trim, isNotNull);
      expect(trim!.tilesetId, 'room_builder_office');
      expect(trim.tileIndex, 53);
    });

    test('vertical wall: only top gets trim, only bottom gets shadow', () {
      state.setTool(EditorTool.barrier);
      state.paintTile(10, 5);
      state.paintTile(10, 6);
      state.paintTile(10, 7);

      state.applyAutomapRules(allAutomapRules);

      // Trim only on top barrier (10, 5) — cell above (10, 4) is open.
      expect(state.objectLayerData.tileAt(10, 5)?.tileIndex, 53);
      // Middle barrier (10, 6) — above is barrier, so no trim.
      expect(state.objectLayerData.tileAt(10, 6), isNull);
      // Bottom barrier (10, 7) — above is barrier, so no trim.
      expect(state.objectLayerData.tileAt(10, 7), isNull);
      // Shadow below bottom barrier (10, 8) — cell is open, above is barrier.
      expect(state.objectLayerData.tileAt(10, 8)?.tileIndex, 80);
    });

    test('clears previous auto-generated tiles on reapply', () {
      state.setTool(EditorTool.barrier);
      state.paintTile(10, 5);

      state.applyAutomapRules(allAutomapRules);
      expect(state.objectLayerData.tileAt(10, 6), isNotNull);

      // Move barrier and reapply.
      state.setTool(EditorTool.eraser);
      state.paintTile(10, 5);
      state.setTool(EditorTool.barrier);
      state.paintTile(20, 10);

      state.applyAutomapRules(allAutomapRules);

      // Old shadow should be gone.
      expect(state.objectLayerData.tileAt(10, 6), isNull);
      // Old trim should be gone.
      expect(state.objectLayerData.tileAt(10, 5), isNull);
      // New shadow should be present.
      expect(state.objectLayerData.tileAt(20, 11), isNotNull);
    });

    test('preserves manually placed object tiles', () {
      // Manually place a tile on object layer.
      state.objectLayerData.setTile(
        10,
        6,
        const TileRef(tilesetId: 'manual', tileIndex: 99),
      );

      // Paint a barrier above it.
      state.setTool(EditorTool.barrier);
      state.paintTile(10, 5);

      state.applyAutomapRules(allAutomapRules);

      // Manual tile should be preserved.
      final tile = state.objectLayerData.tileAt(10, 6);
      expect(tile!.tilesetId, 'manual');
      expect(tile.tileIndex, 99);
    });

    test('notifies listeners once', () {
      var notifyCount = 0;
      state.addListener(() => notifyCount++);

      state.applyAutomapRules(allAutomapRules);

      expect(notifyCount, 1);
    });

    test('works with empty grid (no barriers)', () {
      state.applyAutomapRules(allAutomapRules);

      // No barriers → no shadows or trims.
      expect(state.objectLayerData.isEmpty, isTrue);
    });
  });

  group('clearAutomapTiles', () {
    test('removes only auto-generated tiles', () {
      // Place manual tile.
      state.objectLayerData.setTile(
        5,
        5,
        const TileRef(tilesetId: 'manual', tileIndex: 1),
      );

      // Paint barrier and apply rules.
      state.setTool(EditorTool.barrier);
      state.paintTile(10, 5);
      state.applyAutomapRules(allAutomapRules);

      // Both manual and auto tiles should exist.
      expect(state.objectLayerData.tileAt(5, 5), isNotNull);
      expect(state.objectLayerData.tileAt(10, 6), isNotNull);

      state.clearAutomapTiles();

      // Manual tile preserved, auto tiles removed.
      expect(state.objectLayerData.tileAt(5, 5), isNotNull);
      expect(state.objectLayerData.tileAt(10, 6), isNull);
      expect(state.objectLayerData.tileAt(10, 5), isNull);
    });

    test('notifies listeners', () {
      var notified = false;
      state.addListener(() => notified = true);

      state.clearAutomapTiles();

      expect(notified, isTrue);
    });
  });

  group('clearAll integration', () {
    test('clearAll also clears automapped cells', () {
      state.setTool(EditorTool.barrier);
      state.paintTile(10, 5);
      state.applyAutomapRules(allAutomapRules);

      state.clearAll();

      // Everything should be clean.
      expect(state.objectLayerData.tileAt(10, 6), isNull);
      expect(state.objectLayerData.tileAt(10, 5), isNull);
    });
  });
}
