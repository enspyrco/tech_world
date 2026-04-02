import 'package:flutter_test/flutter_test.dart';
import 'package:tech_world/flame/maps/barrier_occlusion.dart'
    show WallBitmask, faceForBitmask, capForBitmask, wallTilesetId;
import 'package:tech_world/map_editor/map_editor_state.dart';

void main() {
  late MapEditorState state;

  setUp(() {
    state = MapEditorState();
  });

  group('Wall brush selection', () {
    test('starts with wall brush inactive', () {
      expect(state.wallBrushActive, isFalse);
    });

    test('setWallBrush(true) activates and notifies', () {
      var notified = false;
      state.addListener(() => notified = true);

      state.setWallBrush(true);

      expect(state.wallBrushActive, isTrue);
      expect(notified, isTrue);
    });

    test('setWallBrush(false) deactivates wall brush', () {
      state.setWallBrush(true);
      state.setWallBrush(false);
      expect(state.wallBrushActive, isFalse);
    });
  });

  group('paintWall', () {
    setUp(() {
      state.setWallBrush(true);
    });

    test('creates barrier on structure grid', () {
      state.paintWall(10, 10);
      expect(state.tileAt(10, 10), TileType.barrier);
    });

    test('places face tile on object layer at barrier position', () {
      state.paintWall(10, 10);

      final face = state.objectLayerData.tileAt(10, 10);
      expect(face, isNotNull);
      expect(face!.tilesetId, wallTilesetId);
      // Isolated wall (bitmask 0) → face tile index from lookup.
      expect(face.tileIndex, faceForBitmask(0));
    });

    test('places cap tile on object layer at y-1 (north-facing)', () {
      state.paintWall(10, 10);

      final cap = state.objectLayerData.tileAt(10, 9);
      expect(cap, isNotNull);
      expect(cap!.tilesetId, wallTilesetId);
      // Isolated wall → cap bitmask 0.
      expect(cap.tileIndex, capForBitmask(0));
    });

    test('does NOT place cap if wall exists above (not north-facing)', () {
      state.paintWall(10, 10);
      state.paintWall(10, 9); // Wall above

      // The cap at y-1 of the BOTTOM wall (10, 9) is now the wall above's
      // face position. Cap should belong to the top wall, not the bottom.
      // The bottom wall (10, 10) no longer owns a cap at (10, 9).
      // Cap should appear at (10, 8) instead — from the top wall.
      final capAboveTop = state.objectLayerData.tileAt(10, 8);
      expect(capAboveTop, isNotNull, reason: 'Top wall should have cap at y-1');
    });

    test('two horizontal walls update each other via bitmask', () {
      state.paintWall(10, 10);
      state.paintWall(11, 10); // East neighbor

      // Left wall (10,10) now has E neighbor.
      final leftFace = state.objectLayerData.tileAt(10, 10);
      expect(
        leftFace!.tileIndex,
        faceForBitmask(WallBitmask.e),
        reason: 'Left wall should see E neighbor',
      );

      // Right wall (11,10) has W neighbor.
      final rightFace = state.objectLayerData.tileAt(11, 10);
      expect(
        rightFace!.tileIndex,
        faceForBitmask(WallBitmask.w),
        reason: 'Right wall should see W neighbor',
      );
    });

    test('both horizontal walls get caps (both north-facing)', () {
      state.paintWall(10, 10);
      state.paintWall(11, 10);

      expect(state.objectLayerData.tileAt(10, 9), isNotNull,
          reason: 'Left wall cap');
      expect(state.objectLayerData.tileAt(11, 9), isNotNull,
          reason: 'Right wall cap');
    });

    test('out-of-bounds paint is silently ignored', () {
      state.paintWall(-1, 5);
      state.paintWall(5, -1);
      state.paintWall(50, 5);
      state.paintWall(5, 50);
      // No crash.
    });

    test('cap at y=0 wall still works (cap at y=-1 is out of bounds)', () {
      state.paintWall(10, 0);

      // Face at (10, 0) should be placed.
      expect(state.objectLayerData.tileAt(10, 0), isNotNull);
      // Cap at (10, -1) is out of bounds — no crash, no tile.
      // (TileLayerData.setTile silently ignores out-of-bounds.)
    });
  });

  group('eraseWall', () {
    setUp(() {
      state.setWallBrush(true);
    });

    test('removes barrier from structure grid', () {
      state.paintWall(10, 10);
      state.eraseWall(10, 10);
      expect(state.tileAt(10, 10), TileType.open);
    });

    test('removes face tile from object layer', () {
      state.paintWall(10, 10);
      state.eraseWall(10, 10);
      expect(state.objectLayerData.tileAt(10, 10), isNull);
    });

    test('removes cap tile from object layer', () {
      state.paintWall(10, 10);
      state.eraseWall(10, 10);
      expect(state.objectLayerData.tileAt(10, 9), isNull);
    });

    test('neighbors update when wall is erased', () {
      state.paintWall(10, 10);
      state.paintWall(11, 10);
      state.eraseWall(11, 10);

      // Left wall should revert to isolated (bitmask 0).
      final face = state.objectLayerData.tileAt(10, 10);
      expect(
        face!.tileIndex,
        faceForBitmask(0),
        reason: 'Left wall should revert to isolated after neighbor erased',
      );
    });

    test('erasing wall does not clobber neighbor cap above', () {
      // Two vertical walls.
      state.paintWall(10, 9);
      state.paintWall(10, 10);

      // Erase bottom wall.
      state.eraseWall(10, 10);

      // Top wall at (10, 9) should still have its cap at (10, 8).
      expect(state.objectLayerData.tileAt(10, 8), isNotNull,
          reason: 'Top wall cap should survive');
    });
  });

  group('clearAll resets wall brush', () {
    test('clearAll deactivates wall brush', () {
      state.setWallBrush(true);
      state.paintWall(10, 10);
      state.clearAll();
      expect(state.wallBrushActive, isFalse);
    });
  });
}
