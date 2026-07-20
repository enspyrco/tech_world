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

  // Squared RGB distance (0–255 space). We compare RELATIVELY — "is this pixel
  // closer to the wall or to the player?" — rather than against an absolute
  // tolerance. The occlusion regression is a full colour swap (green↔brown,
  // ~150+ per channel), so relative distance discriminates it unambiguously
  // AND is immune to any uniform cross-platform rasterisation drift, so there
  // is no arbitrary tolerance to tune.
  double dist2(Color a, Color b) {
    final dr = (a.r - b.r) * 255, dg = (a.g - b.g) * 255, db = (a.b - b.b) * 255;
    return dr * dr + dg * dg + db * db;
  }

  bool closerToWall(Color c) => dist2(c, _wallColor) < dist2(c, _playerColor);
  bool closerToPlayer(Color c) => dist2(c, _playerColor) < dist2(c, _wallColor);

  testWidgets('wall top occludes the player behind it (rendered pixels)',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 600));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final game = _PixelGame();
    late final ByteData data;
    late final int imgW;

    // ALL of it runs inside runAsync — the mock sprite images are produced via
    // `picture.toImage()` (a real engine round-trip); outside runAsync those
    // stay pending in the fake-async zone, so on the headless CI rasteriser the
    // sprites render blank and the sanity check below trips. This mirrors
    // flame_test's own `testGolden`, which wraps setup + render identically.
    await tester.runAsync(() async {
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
      await tester.pump();
      await game.ready();

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
        position:
            Vector2(playerCol * gridSquareSizeDouble, capRow * gridSquareSizeDouble),
        id: 'p',
        displayName: 'P',
      );
      await game.world.add(player);
      await game.ready();
      game.update(0); // compute the per-frame priorities
      await tester.pump();

      final boundary = tester
          .renderObject<RenderRepaintBoundary>(find.byKey(const Key('scene')));
      final image = await boundary.toImage(pixelRatio: 1);
      data = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
      imgW = image.width;
    });

    Color at(int x, int y) {
      final o = (y * imgW + x) * 4;
      return Color.fromARGB(
        data.getUint8(o + 3),
        data.getUint8(o),
        data.getUint8(o + 1),
        data.getUint8(o + 2),
      );
    }

    final overlapPixel = at(sampleX, overlapY);
    final headPixel = at(sampleX, headY);

    // Sanity: the exposed head above the wall must read as the player, not the
    // wall — which also guards against a blank render, since a black/empty
    // background is closer to brown than to green and would fail this.
    expect(
      closerToPlayer(headPixel),
      isTrue,
      reason: 'Player head above the wall should be visible (green); got '
          '$headPixel — scene did not render as expected, oracle invalid.',
    );

    // The invariant: behind the wall top, the wall occludes the player, so the
    // overlap pixel must read as wall, not player. (Head sanity above already
    // proved the scene rendered, so this pixel is a real wall-or-player sample.)
    expect(
      closerToWall(overlapPixel),
      isTrue,
      reason: 'Player standing behind the wall top must be OCCLUDED — the '
          'overlap pixel should read as wall, got $overlapPixel. If it reads '
          'as player-green, occlusion has regressed (this is PR #510 broken).',
    );
  });
}
