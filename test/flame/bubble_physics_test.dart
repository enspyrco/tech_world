import 'package:flame/components.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tech_world/flame/bubble_physics.dart';

/// Minimal stand-in: physics only reads `center` and writes `position`.
class _Bubble extends PositionComponent {
  _Bubble(double x, double y) {
    size = Vector2.all(BubblePhysics.bubbleDiameter);
    position = Vector2(x, y);
  }
}

void main() {
  const dia = BubblePhysics.bubbleDiameter;

  Map<String, PositionComponent> world(Map<String, (double, double)> spec) =>
      {for (final e in spec.entries) e.key: _Bubble(e.value.$1, e.value.$2)};

  group('BubblePhysics — no-op cases', () {
    test('a single bubble is never displaced', () {
      final bubbles = world({'a': (0, 0)});
      final before = bubbles['a']!.position.clone();

      BubblePhysics().apply(bubbles, 0.016);

      expect(bubbles['a']!.position, equals(before));
    });

    test('bubbles further apart than a diameter do not push', () {
      final bubbles = world({'a': (0, 0), 'b': (dia * 3, 0)});
      final before = bubbles['a']!.position.clone();

      BubblePhysics().apply(bubbles, 0.016);

      expect(bubbles['a']!.position, equals(before));
    });
  });

  group('BubblePhysics — repulsion', () {
    test('overlapping bubbles push apart, symmetrically', () {
      // Centres 10px apart on x — well inside a diameter.
      final bubbles = world({'a': (0, 0), 'b': (10, 0)});
      final physics = BubblePhysics()..apply(bubbles, 0.016);

      final da = physics.displacementOf('a');
      final db = physics.displacementOf('b');

      expect(da.x, lessThan(0), reason: 'a is left, pushed further left');
      expect(db.x, greaterThan(0), reason: 'b is right, pushed further right');
      // Equal and opposite: no net drift injected into the pair.
      expect(da.x + db.x, closeTo(0, 1e-9));
      expect(da.y + db.y, closeTo(0, 1e-9));
    });

    test('near-co-located bubbles are not pushed at all (jitter guard)', () {
      // Below the 0.01 separation the push DIRECTION is numerically arbitrary
      // while `overlap` is at its maximum, so an unguarded solver fires a
      // full-strength shove along an axis that flips frame to frame.
      //
      // Asserting "no NaN" here would be vacuous: Vector2.normalized() already
      // returns zero for a zero vector, so that test passes with the guard
      // deleted. Verified by deliberately removing it.
      final bubbles = world({'a': (0, 0), 'b': (0.005, 0)});
      final physics = BubblePhysics()..apply(bubbles, 0.016);

      expect(physics.displacementOf('a'), equals(Vector2.zero()));
      expect(physics.displacementOf('b'), equals(Vector2.zero()));
    });
  });

  group('BubblePhysics — the tether cap', () {
    test('displacement never exceeds maxTetherDistance, however long it runs',
        () {
      // Heavily overlapped, driven for far longer than any real crowd.
      final bubbles = world({'a': (0, 0), 'b': (1, 0)});
      final physics = BubblePhysics();

      for (var i = 0; i < 500; i++) {
        // Re-anchor each frame, as BubbleManager does: physics adds an offset
        // to the anchor rather than integrating position freely.
        bubbles['a']!.position = Vector2(0, 0);
        bubbles['b']!.position = Vector2(1, 0);
        physics.apply(bubbles, 0.016);
      }

      expect(
        physics.displacementOf('a').length,
        lessThanOrEqualTo(BubblePhysics.maxTetherDistance + 1e-9),
      );
    });

    test('a huge frame is clamped before it is capped', () {
      // A BARELY overlapping pair, which is what makes this test load-bearing:
      // with a heavily overlapped pair both the clamped and unclamped force
      // blow past the tether, the cap flattens them to the same value, and the
      // test passes with the clamp deleted. Verified — that was this test's
      // first form, and removing `min(dt, maxIntegrationStep)` left it green.
      //
      // Overlap of 1px: clamped push is ~1.6px, unclamped at dt=100 is ~3125px
      // and saturates the 24px tether. The two are distinguishable.
      final bubbles =
          world({'a': (0, 0), 'b': (BubblePhysics.bubbleDiameter - 1, 0)});
      final physics = BubblePhysics()..apply(bubbles, 100.0);

      expect(
        physics.displacementOf('a').length,
        lessThan(BubblePhysics.maxTetherDistance),
        reason: 'unclamped dt would saturate the tether instead',
      );
    });
  });

  group('BubblePhysics — damping', () {
    test('displacement decays once the crowd disperses', () {
      final crowded = world({'a': (0, 0), 'b': (10, 0)});
      final physics = BubblePhysics();
      for (var i = 0; i < 20; i++) {
        crowded['a']!.position = Vector2(0, 0);
        crowded['b']!.position = Vector2(10, 0);
        physics.apply(crowded, 0.016);
      }
      final crowdedDisp = physics.displacementOf('a').length;
      expect(crowdedDisp, greaterThan(0));

      // Same keys, now far apart: no new force, damping only.
      final apart = world({'a': (0, 0), 'b': (dia * 10, 0)});
      for (var i = 0; i < 20; i++) {
        physics.apply(apart, 0.016);
      }

      expect(physics.displacementOf('a').length, lessThan(crowdedDisp * 0.1));
    });
  });

  group('BubblePhysics — bookkeeping', () {
    test('clear forgets accumulated displacement', () {
      final bubbles = world({'a': (0, 0), 'b': (10, 0)});
      final physics = BubblePhysics()..apply(bubbles, 0.016);
      expect(physics.displacementOf('a').length, greaterThan(0));

      physics.clear();

      expect(physics.displacementOf('a'), equals(Vector2.zero()));
    });

    test('departed bubbles are swept on the next crowded frame', () {
      final bubbles = world({'a': (0, 0), 'b': (10, 0), 'c': (20, 0)});
      final physics = BubblePhysics()..apply(bubbles, 0.016);
      expect(physics.displacementOf('c').length, greaterThan(0));

      bubbles.remove('c');
      physics.apply(bubbles, 0.016);

      expect(physics.displacementOf('c'), equals(Vector2.zero()));
    });
  });
}
