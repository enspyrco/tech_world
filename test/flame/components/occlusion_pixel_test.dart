@Tags(['pixel'])
library;

import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flame/components.dart';
import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tech_world/flame/components/player_component.dart';
import 'package:tech_world/flame/components/tile_object_layer_component.dart';
import 'package:tech_world/flame/shared/constants.dart';
import 'package:tech_world/flame/tech_world_game.dart';
import 'package:tech_world/flame/tiles/tile_layer_data.dart';
import 'package:tech_world/flame/tiles/tile_ref.dart';
import 'package:tech_world/flame/tiles/tileset.dart';
import 'package:tech_world/flame/tiles/tileset_registry.dart';

/// Pixel-oracle visual-regression test for occlusion.
///
/// Where [y_occlusion_test] asserts the priority *numbers*, this renders the
/// real Flame world to actual pixels and asserts the *semantic* invariant:
/// where a player stands behind a wall top, the sampled pixel is wall-coloured,
/// not player-coloured. It reads pixels back with [RenderRepaintBoundary.toImage]
/// and samples cell centres — so it asserts occlusion *happened* rather than
/// byte-matching a golden.
///
/// ## Why colour-sampling, not `matchesGoldenFile`
///
/// Flutter goldens are byte-identity comparisons; rasterisation (fonts, AA,
/// GPU vs software) differs between a dev Mac and the CI Linux runner, so a
/// committed golden PNG is flaky-by-construction and needs a pinned-environment
/// baseline. Solid-colour fills, sampled at cell centres away from edges,
/// rasterise identically on every platform — so this runs in the normal `test`
/// job with no golden baseline and no new CI workflow. It is the seed of the
/// visual-regression gate: the render→sample pattern generalises to any
/// "does X render over Y" question (bubbles, speech, editor overlays).
///
/// This is the automated eye that would have caught the ~3-month occlusion
/// regression (PR #510) and the ~4-month speech-animation regression the same
/// day they shipped, instead of a human noticing post-hoc.

// Vivid, opaque, unambiguous fills so a sampled centre pixel is one or the other.
const _playerColor = Color(0xFF33DD44); // green
const _wallColor = Color(0xFF7A4B22); // brown

Future<ui.Image> _solid(int w, int h, Color c) {
  final recorder = ui.PictureRecorder();
  ui.Canvas(recorder)
      .drawRect(Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()), Paint()..color = c);
  return recorder.endRecording().toImage(w, h);
}

/// A [TechWorldGame] with mock images + a world→screen identity camera so a
/// world pixel `(wx, wy)` lands at screen pixel `(wx, wy)` (anchor top-left,
/// zero position, zoom 1). That makes pixel sampling coordinate-trivial.
class _PixelGame extends TechWorldGame {
  _PixelGame() : super(world: World());

  late final TilesetRegistry registry;

  @override
  Future<void> onLoad() async {
    images.add('NPC11.png', await _solid(384, 256, _playerColor));
    registry = TilesetRegistry(images: images);
    registry.loadFromImage(
      const Tileset(
        id: 'w',
        name: 'wall',
        imagePath: 'w.png',
        tileSize: gridSquareSize,
        columns: 1,
        rows: 1,
      ),
      await _solid(gridSquareSize, gridSquareSize, _wallColor),
    );
    camera.viewfinder
      ..anchor = Anchor.topLeft
      ..position = Vector2.zero()
      ..zoom = 1;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const barrierRow = 10; // wall face
  const capRow = barrierRow - 1; // wall top (occludes a player above)
  const playerCol = 6; // sits within the wall span, straddling the cap row

  // Sample points (world == screen). The player sprite is 32×64 anchored
  // centre-left at (playerCol*32, capRow*32) → spans x[192,224], y[256,320].
  // The wall cap covers y[288,320]. So:
  //  - a point in the overlap band must be WALL-coloured (occluded), and
  //  - a point on the exposed head above the cap must be PLAYER-coloured.
  const sampleX = playerCol * gridSquareSize + gridSquareSize ~/ 2; // 208
  const overlapY = capRow * gridSquareSize + gridSquareSize ~/ 2; // 304 (behind cap)
  const headY = capRow * gridSquareSize - gridSquareSize ~/ 2; // 272 (above cap)

  bool near(Color a, Color b, [int tol = 30]) =>
      (a.r * 255 - b.r * 255).abs() <= tol &&
      (a.g * 255 - b.g * 255).abs() <= tol &&
      (a.b * 255 - b.b * 255).abs() <= tol;

  testWidgets('wall top occludes the player behind it (rendered pixels)',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 600));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final game = _PixelGame();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          backgroundColor: Colors.black,
          body: RepaintBoundary(
            key: const Key('scene'),
            child: GameWidget(game: game),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 50));

    // Horizontal wall (cap row + face row) across cols 4..8, cap tiles bumped
    // to the barrier row so they sort with the wall face.
    final layer = TileLayerData();
    final overrides = <(int, int), int>{};
    for (var x = 4; x <= 8; x++) {
      layer.setTile(x, capRow, const TileRef(tilesetId: 'w', tileIndex: 0));
      layer.setTile(x, barrierRow, const TileRef(tilesetId: 'w', tileIndex: 0));
      overrides[(x, capRow)] = barrierRow;
    }
    await game.world.add(TileObjectLayerComponent(
      layerData: layer,
      registry: game.registry,
      priorityOverrides: overrides,
    ));

    final player = PlayerComponent(
      position: Vector2(playerCol * gridSquareSizeDouble, capRow * gridSquareSizeDouble),
      id: 'p',
      displayName: 'P',
    );
    await game.world.add(player);
    game.update(0);
    await tester.pump(const Duration(milliseconds: 50));

    // Read the rendered pixels back. toImage() needs a real engine round-trip
    // to composite + encode the layer; inside testWidgets' fake-async zone that
    // callback never fires and the await deadlocks — so escape via runAsync.
    final boundary =
        tester.renderObject<RenderRepaintBoundary>(find.byKey(const Key('scene')));
    late final ui.Image image;
    late final ByteData data;
    await tester.runAsync(() async {
      image = await boundary.toImage(pixelRatio: 1);
      data = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
    });

    Color at(int x, int y) {
      final o = (y * image.width + x) * 4;
      return Color.fromARGB(
        data.getUint8(o + 3),
        data.getUint8(o),
        data.getUint8(o + 1),
        data.getUint8(o + 2),
      );
    }

    final overlapPixel = at(sampleX, overlapY);
    final headPixel = at(sampleX, headY);

    // Sanity: the exposed head above the wall must be the player's colour, or
    // the scene isn't laid out the way this oracle assumes (guards against a
    // silently-empty render masquerading as a pass).
    expect(
      near(headPixel, _playerColor),
      isTrue,
      reason: 'Player head above the wall should be visible (green); got '
          '$headPixel — scene layout/render is wrong, oracle invalid.',
    );

    // The invariant: behind the wall top, the wall (brown) occludes the player.
    expect(
      near(overlapPixel, _wallColor),
      isTrue,
      reason: 'Player standing behind the wall top must be OCCLUDED — the '
          'overlap pixel should be wall-brown, got $overlapPixel. If it is '
          'player-green, occlusion has regressed (this is PR #510 broken).',
    );
  });
}
