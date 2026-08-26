import 'package:flame/components.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tech_world/flame/bubble_merge_renderer.dart';
import 'package:tech_world/flame/components/merged_video_bubble_component.dart';

void main() {
  // The merge/glow layer had NO test before this file: nothing in the suite
  // referenced findMergeGroup, hiddenForMerge, BubbleFieldComponent or
  // MergedVideoBubbleComponent. It was unreachable while it sat as three
  // private methods on a 1300-line class.

  const t = BubbleMergeRenderer.mergeThreshold; // 96.0

  Map<String, Vector2> centres(Map<String, (double, double)> spec) =>
      {for (final e in spec.entries) e.key: Vector2(e.value.$1, e.value.$2)};

  group('findMergeGroup — degenerate inputs', () {
    test('empty returns empty', () {
      expect(BubbleMergeRenderer.findMergeGroup({}), isEmpty);
    });

    test('a single bubble never merges with itself', () {
      expect(
        BubbleMergeRenderer.findMergeGroup(centres({'a': (0, 0)})),
        isEmpty,
      );
    });

    test('two bubbles beyond the threshold do not merge', () {
      expect(
        BubbleMergeRenderer.findMergeGroup(
            centres({'a': (0, 0), 'b': (t + 1, 0)})),
        isEmpty,
      );
    });
  });

  group('findMergeGroup — the threshold boundary', () {
    test('just inside merges', () {
      expect(
        BubbleMergeRenderer.findMergeGroup(
            centres({'a': (0, 0), 'b': (t - 0.5, 0)})),
        unorderedEquals(['a', 'b']),
      );
    });

    test('exactly at the threshold does NOT merge (strict <)', () {
      // Pins the comparison direction. A flip to <= would leave this green
      // if the test used a distance strictly inside.
      expect(
        BubbleMergeRenderer.findMergeGroup(
            centres({'a': (0, 0), 'b': (t, 0)})),
        isEmpty,
      );
    });
  });

  group('findMergeGroup — connectivity', () {
    test('merges transitively: a-b-c chained, a and c out of range', () {
      // a..b = 60, b..c = 60, a..c = 120 (> threshold). Connectivity is
      // through b, so all three belong to one group.
      final group = BubbleMergeRenderer.findMergeGroup(
          centres({'a': (0, 0), 'b': (60, 0), 'c': (120, 0)}));
      expect(group, unorderedEquals(['a', 'b', 'c']));
    });

    test('picks the LARGEST cluster, not the first one found', () {
      // 'pair' comes first in insertion order but the trio is bigger. A
      // first-found implementation returns the pair and this goes red.
      final group = BubbleMergeRenderer.findMergeGroup(centres({
        'pair1': (0, 0),
        'pair2': (10, 0),
        'trio1': (1000, 0),
        'trio2': (1010, 0),
        'trio3': (1020, 0),
      }));
      expect(group, unorderedEquals(['trio1', 'trio2', 'trio3']));
    });

    test('two isolated singletons produce no group', () {
      expect(
        BubbleMergeRenderer.findMergeGroup(
            centres({'a': (0, 0), 'b': (5000, 0), 'c': (10000, 0)})),
        isEmpty,
      );
    });
  });

  group('findMergeGroup — shader source cap', () {
    test('caps at maxMergedBubbles even when more are in range', () {
      // The merged-video shader samples a fixed number of sources; handing it
      // more would silently drop the tail inside the component instead.
      final spec = <String, (double, double)>{
        for (var i = 0; i < maxMergedBubbles + 3; i++) 'b$i': (i * 10.0, 0),
      };
      final group = BubbleMergeRenderer.findMergeGroup(centres(spec));
      expect(group.length, equals(maxMergedBubbles));
      expect(group.toSet().length, equals(maxMergedBubbles),
          reason: 'cap must not duplicate entries');
    });
  });

  group('BubbleMergeRenderer lifecycle', () {
    test('does nothing without shaders, and never adds a component', () {
      // Shaders can fail to load (the loader warns rather than throwing), so
      // the renderer must degrade to a no-op rather than dereferencing null.
      final added = <Component>[];
      final renderer = BubbleMergeRenderer(
        bubbles: {},
        addComponent: added.add,
        reduceMotion: () => false,
      );

      renderer.update([Vector2.zero(), Vector2(10, 0)], 0);

      expect(added, isEmpty);
      expect(renderer.bubbleField, isNull);
      expect(renderer.mergedBubble, isNull);
    });

    test('clearSurfaces and dispose are safe with nothing attached', () {
      final renderer = BubbleMergeRenderer(
        bubbles: {},
        addComponent: (_) {},
        reduceMotion: () => false,
      );
      expect(renderer.clearSurfaces, returnsNormally);
      expect(renderer.dispose, returnsNormally);
      expect(renderer.dispose, returnsNormally, reason: 'idempotent');
    });
  });
}
