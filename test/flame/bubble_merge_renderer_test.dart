import 'package:flame/components.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tech_world/events/types.dart';
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

  group('mergeTransitions — transition-only emission', () {
    // The merge pass runs EVERY FRAME. An event per frame would be a
    // self-inflicted denial of service against our own logs — the same
    // hazard capture_latch_state_machine.dart already calls out. So these
    // tests assert WHEN events are emitted, not merely how many exist in
    // total. A count-only assertion is what let a hysteresis pair collapse
    // unnoticed for two months elsewhere in this file's own subsystem.

    test('no group before, no group after — silent', () {
      expect(BubbleMergeRenderer.mergeTransitions([], []), isEmpty);
    });

    test('a group forming emits exactly one BubblesMerged', () {
      final events = BubbleMergeRenderer.mergeTransitions([], ['a', 'b']);
      expect(events, hasLength(1));
      expect(events.single, isA<BubblesMerged>());
      expect((events.single as BubblesMerged).participantIds, ['a', 'b']);
    });

    test('an UNCHANGED group across frames emits NOTHING', () {
      // The load-bearing assertion. If this ever goes green-by-emitting,
      // the log fills at frame rate and the instrument destroys itself.
      expect(
        BubbleMergeRenderer.mergeTransitions(['a', 'b'], ['a', 'b']),
        isEmpty,
      );
    });

    test('member order alone is not a change', () {
      expect(
        BubbleMergeRenderer.mergeTransitions(['a', 'b'], ['b', 'a']),
        isEmpty,
      );
    });

    test('a group breaking emits exactly one BubblesUnmerged, naming who '
        'had been merged', () {
      final events = BubbleMergeRenderer.mergeTransitions(['a', 'b'], []);
      expect(events, hasLength(1));
      expect(events.single, isA<BubblesUnmerged>());
      expect((events.single as BubblesUnmerged).participantIds, ['a', 'b']);
    });

    test('a member joining an existing group re-emits the new membership', () {
      final events =
          BubbleMergeRenderer.mergeTransitions(['a', 'b'], ['a', 'b', 'c']);
      expect(events, hasLength(1));
      expect((events.single as BubblesMerged).participantIds,
          ['a', 'b', 'c']);
    });

    test('a member leaving a group that survives re-emits, not unmerges', () {
      final events =
          BubbleMergeRenderer.mergeTransitions(['a', 'b', 'c'], ['a', 'b']);
      expect(events, hasLength(1));
      expect(events.single, isA<BubblesMerged>(),
          reason: 'the group still exists, so this is a membership change '
              'rather than a teardown');
    });

    test('a wholesale swap of members emits one BubblesMerged', () {
      final events =
          BubbleMergeRenderer.mergeTransitions(['a', 'b'], ['c', 'd']);
      expect(events, hasLength(1));
      expect((events.single as BubblesMerged).participantIds, ['c', 'd']);
    });
  });
}
