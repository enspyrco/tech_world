// Merge membership is decided from bubble ANCHORS, not from the positions
// BubblePhysics has displaced.
//
// Observed live 2026-09-11 14:35-14:36: walking two players past each other
// produced bursts of merge/unmerge transitions 8-17ms apart. Every burst sat
// between two player_moved events, i.e. during locomotion.
//
// Mechanism: repulsion switches off above BubblePhysics.bubbleDiameter, but the
// accumulated displacement only decays at repulsionDamping (0.85) per frame.
// While the anchors separate, displacement decays FASTER than the anchors move
// apart, so the rendered separation overshoots the merge threshold, dips back
// under it, and rises again — three crossings where the players crossed once.
//
// Anchors carry no such transient, so grouping on them needs no hysteresis
// band and no tuned constant.
import 'dart:math';

import 'package:flame/components.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tech_world/flame/bubble_merge_renderer.dart';
import 'package:tech_world/flame/bubble_physics.dart';

/// Whether the simulation feeds [BubbleMergeRenderer.findMergeGroup] the
/// pre-physics anchors (production behaviour) or the displaced centres (the
/// pre-fix behaviour, kept only as this suite's must-fail control).
enum _Source { anchors, displacedCentres }

const _dt = 1 / 60;
const _grid = 32.0;

/// Walks bubble `b` away from bubble `a` at [speedPxPerSec], driving the REAL
/// [BubblePhysics], and counts how many times merge membership flips.
///
/// One flip is correct: the players cross the threshold once.
int _membershipFlips({
  required _Source source,
  required double speedPxPerSec,
  bool withBot = false,
}) {
  final physics = BubblePhysics();
  final a = PositionComponent(size: Vector2.all(64));
  final b = PositionComponent(size: Vector2.all(64));
  final bot = PositionComponent(size: Vector2.all(64));

  var anchorX = _grid; // start one square apart, comfortably merged
  var flips = 0;
  bool? merged;

  for (var frame = 0; frame < 1200 && anchorX < _grid * 6; frame++) {
    a.position = Vector2.zero();
    b.position = Vector2(anchorX, 0);
    if (withBot) {
      // A bot wandering beside the pair, as bot-claude and bot-gremlin were.
      // It must move SMOOTHLY: a bot that teleports between squares changes
      // the connected component discontinuously, which is a real membership
      // change and not the transient this test is about.
      final bobble = _grid * (1 + 0.5 * (1 + sin(frame * 0.05)));
      bot.position = Vector2(anchorX / 2, bobble);
    }

    // Anchors are read BEFORE apply(), exactly as BubbleManager snapshots them.
    final anchorCentres = {
      'a': a.center.clone(),
      'b': b.center.clone(),
      if (withBot) 'bot': bot.center.clone(),
    };

    physics.apply(
      withBot ? {'a': a, 'b': b, 'bot': bot} : {'a': a, 'b': b},
      _dt,
    );

    final forGrouping = switch (source) {
      _Source.anchors => anchorCentres,
      _Source.displacedCentres => {
          'a': a.center.clone(),
          'b': b.center.clone(),
          if (withBot) 'bot': bot.center.clone(),
        },
    };

    final group = BubbleMergeRenderer.findMergeGroup(forGrouping);
    final nowMerged = group.contains('a') && group.contains('b');
    if (merged != null && nowMerged != merged) flips++;
    merged = nowMerged;

    anchorX += speedPxPerSec * _dt;
  }
  return flips;
}

void main() {
  // Slow walks are the worst case: the displacement has longer to decay
  // relative to the anchors' separation, so the dip below the threshold is
  // deeper (measured max 26.2px at 20px/s).
  const speeds = [20.0, 30.0, 40.0, 60.0, 90.0, 120.0, 160.0];

  group('merge membership is stable across one threshold crossing', () {
    for (final speed in speeds) {
      test('${speed.toStringAsFixed(0)}px/s — pair alone', () {
        expect(
          _membershipFlips(source: _Source.anchors, speedPxPerSec: speed),
          1,
          reason: 'walking past the merge threshold once must produce exactly '
              'one membership change, not a burst',
        );
      });

      test('${speed.toStringAsFixed(0)}px/s — with a bot in the huddle', () {
        expect(
          _membershipFlips(
              source: _Source.anchors, speedPxPerSec: speed, withBot: true),
          1,
        );
      });
    }
  });

  group('control: the harness can actually see the defect', () {
    // Without this the suite above could pass vacuously — a simulation that
    // never crosses the threshold would also report "1", and a simulation that
    // never moved would report 0 and fail loudly. These arms prove the probe
    // responds to the thing it claims to measure.
    test('grouping on displaced centres DOES flap — the pre-fix behaviour', () {
      final flips = speeds
          .map((s) => _membershipFlips(
              source: _Source.displacedCentres, speedPxPerSec: s))
          .toList();

      expect(
        flips.any((f) => f > 1),
        isTrue,
        reason: 'if this passes with all-1 the simulation is no longer '
            'reproducing the bug, and the suite above proves nothing',
      );
      expect(flips.every((f) => f >= 1), isTrue,
          reason: 'every speed must cross the threshold at least once');
    });

    test('a pair that never separates produces ZERO flips', () {
      // Null arm: no crossing, no transition. Distinguishes "stable" from
      // "the counter is stuck".
      expect(
        _membershipFlips(source: _Source.anchors, speedPxPerSec: 0),
        0,
      );
    });
  });
}
