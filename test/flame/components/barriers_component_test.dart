import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:tech_world/flame/components/barriers_component.dart';
import 'package:tech_world/flame/shared/constants.dart';

void main() {
  group('BarriersComponent', () {
    group('with barriers', () {
      late BarriersComponent barriers;

      setUp(() {
        barriers = BarriersComponent(barriers: [
          const Point(4, 7),
          const Point(4, 8),
          const Point(5, 7),
          const Point(10, 10),
        ]);
      });

      group('tuples', () {
        test('returns list of barrier positions as tuples', () {
          final tuples = barriers.tuples;
          expect(tuples, isNotEmpty);
          expect(tuples, isA<List<(int, int)>>());
          expect(tuples.length, equals(4));
        });

        test('contains expected positions', () {
          final tuples = barriers.tuples;
          expect(tuples.contains((4, 7)), isTrue);
          expect(tuples.contains((4, 8)), isTrue);
          expect(tuples.contains((5, 7)), isTrue);
          expect(tuples.contains((10, 10)), isTrue);
        });

        test('all tuples have valid coordinates', () {
          final tuples = barriers.tuples;
          for (final (x, y) in tuples) {
            expect(x, greaterThanOrEqualTo(0));
            expect(y, greaterThanOrEqualTo(0));
            expect(x, lessThan(gridSize));
            expect(y, lessThan(gridSize));
          }
        });
      });

      group('createGrid', () {
        test('creates a pathfinding grid', () {
          final grid = barriers.createGrid();
          expect(grid, isNotNull);
        });

        test('grid has correct dimensions', () {
          final grid = barriers.createGrid();
          expect(grid.width, equals(gridSize));
          expect(grid.height, equals(gridSize));
        });

        test('barrier positions are marked as unwalkable', () {
          final grid = barriers.createGrid();
          expect(grid.isWalkableAt(4, 7), isFalse);
          expect(grid.isWalkableAt(4, 8), isFalse);
          expect(grid.isWalkableAt(10, 10), isFalse);
        });

        test('non-barrier positions are walkable', () {
          final grid = barriers.createGrid();
          expect(grid.isWalkableAt(0, 0), isTrue);
          expect(grid.isWalkableAt(25, 25), isTrue);
          expect(grid.isWalkableAt(49, 49), isTrue);
        });

        test('grid can be cloned for pathfinding', () {
          final grid = barriers.createGrid();
          final clone = grid.clone();

          expect(clone, isNotNull);
          expect(clone.width, equals(grid.width));
          expect(clone.height, equals(grid.height));
          expect(clone.isWalkableAt(4, 7), isFalse);
          expect(clone.isWalkableAt(25, 25), isTrue);
        });

        test('returns same grid instance when called multiple times', () {
          final grid1 = barriers.createGrid();
          final grid2 = barriers.createGrid();

          for (int x = 0; x < gridSize; x++) {
            for (int y = 0; y < gridSize; y++) {
              expect(
                grid1.isWalkableAt(x, y),
                equals(grid2.isWalkableAt(x, y)),
                reason: 'Grids should have same walkability at ($x, $y)',
              );
            }
          }
        });
      });

      group('coordinate conversion', () {
        test('tuples match Point representation', () {
          final tuples = barriers.tuples;
          expect(tuples[0].$1, equals(4));
          expect(tuples[0].$2, equals(7));
        });
      });
    });

    group('empty barriers', () {
      late BarriersComponent barriers;

      setUp(() {
        barriers = BarriersComponent(barriers: []);
      });

      test('tuples is empty', () {
        expect(barriers.tuples, isEmpty);
      });

      test('createGrid has all cells walkable', () {
        final grid = barriers.createGrid();
        expect(grid.isWalkableAt(0, 0), isTrue);
        expect(grid.isWalkableAt(25, 25), isTrue);
      });
    });
  });
}
