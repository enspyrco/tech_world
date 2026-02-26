import 'package:flutter_test/flutter_test.dart';
import 'package:tech_world/flame/tiles/tile_animations.dart';

void main() {
  group('tileAnimations', () {
    test('contains entries for ext_terrains tileset', () {
      expect(tileAnimations, contains('ext_terrains'));
      expect(tileAnimations['ext_terrains'], isNotEmpty);
    });

    test('every animation has at least 2 frames', () {
      for (final entry in tileAnimations.entries) {
        for (final anim in entry.value) {
          expect(
            anim.frameCount,
            greaterThanOrEqualTo(2),
            reason:
                '${entry.key} animation at base index ${anim.baseTileIndex} '
                'should have at least 2 frames',
          );
        }
      }
    });

    test('every animation has baseTileIndex in its frameIndices', () {
      for (final entry in tileAnimations.entries) {
        for (final anim in entry.value) {
          expect(
            anim.frameIndices,
            contains(anim.baseTileIndex),
            reason:
                '${entry.key} animation baseTileIndex ${anim.baseTileIndex} '
                'should be in frameIndices',
          );
        }
      }
    });

    test('no duplicate frame indices across animations in the same tileset',
        () {
      for (final entry in tileAnimations.entries) {
        final allIndices = <int>{};
        for (final anim in entry.value) {
          for (final index in anim.frameIndices) {
            expect(
              allIndices.add(index),
              isTrue,
              reason: '${entry.key} has duplicate frame index $index',
            );
          }
        }
      }
    });

    test('stepTime is positive for all animations', () {
      for (final entry in tileAnimations.entries) {
        for (final anim in entry.value) {
          expect(
            anim.stepTime,
            greaterThan(0),
            reason:
                '${entry.key} animation at base index ${anim.baseTileIndex} '
                'should have positive stepTime',
          );
        }
      }
    });
  });

  group('lookupAnimationForTile', () {
    test('returns animation when tile index is any frame', () {
      final animations = tileAnimations['ext_terrains']!;
      final firstAnim = animations.first;

      for (final frameIndex in firstAnim.frameIndices) {
        final found = lookupAnimationForTile('ext_terrains', frameIndex);
        expect(found, isNotNull,
            reason: 'Frame index $frameIndex should find its animation');
        expect(found!.baseTileIndex, firstAnim.baseTileIndex);
      }
    });

    test('returns null for non-animated tile index', () {
      // Index 0 should not be part of any waterfall animation.
      final found = lookupAnimationForTile('ext_terrains', 0);
      expect(found, isNull);
    });

    test('returns null for unknown tileset', () {
      final found = lookupAnimationForTile('nonexistent', 100);
      expect(found, isNull);
    });
  });
}
