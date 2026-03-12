import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:tech_world/flame/maps/game_map.dart';
import 'package:tech_world/flame/maps/map_parser.dart';
import 'package:tech_world/flame/maps/predefined_maps.dart';
import 'package:tech_world/flame/shared/constants.dart';

void main() {
  group('parseAsciiMap', () {
    group('basic parsing', () {
      test('parses a minimal valid map', () {
        // 50x50 grid with one spawn point, rest open.
        final rows = List.generate(50, (y) {
          if (y == 25) {
            return '${'.' * 25}S${'.' * 24}';
          }
          return '.' * 50;
        });
        final ascii = rows.join('\n');

        final map = parseAsciiMap(id: 'test', name: 'Test', ascii: ascii);

        expect(map.id, equals('test'));
        expect(map.name, equals('Test'));
        expect(map.spawnPoint, equals(const Point(25, 25)));
        expect(map.barriers, isEmpty);
        expect(map.terminals, isEmpty);
      });

      test('parses barriers correctly', () {
        final rows = List.generate(50, (y) {
          if (y == 0) return '${'#' * 10}${'.' * 40}';
          if (y == 5) return '${'.' * 10}S${'.' * 39}';
          return '.' * 50;
        });
        final ascii = rows.join('\n');

        final map = parseAsciiMap(id: 'test', name: 'Test', ascii: ascii);

        expect(map.barriers.length, equals(10));
        for (var x = 0; x < 10; x++) {
          expect(map.barriers.contains(Point(x, 0)), isTrue,
              reason: 'Barrier at ($x, 0) should exist');
        }
      });

      test('parses spawn point correctly', () {
        final rows = List.generate(50, (y) {
          if (y == 10) return '${'.' * 30}S${'.' * 19}';
          return '.' * 50;
        });
        final ascii = rows.join('\n');

        final map = parseAsciiMap(id: 'test', name: 'Test', ascii: ascii);

        expect(map.spawnPoint, equals(const Point(30, 10)));
      });

      test('parses terminal stations correctly', () {
        final rows = List.generate(50, (y) {
          if (y == 5) return '${'.' * 10}T${'.' * 20}T${'.' * 18}';
          if (y == 25) return '${'.' * 25}S${'.' * 24}';
          return '.' * 50;
        });
        final ascii = rows.join('\n');

        final map = parseAsciiMap(id: 'test', name: 'Test', ascii: ascii);

        expect(map.terminals.length, equals(2));
        expect(map.terminals, contains(const Point(10, 5)));
        expect(map.terminals, contains(const Point(31, 5)));
      });

      test('spawn point is not a barrier', () {
        final rows = List.generate(50, (y) {
          if (y == 0) return 'S${'.' * 49}';
          return '.' * 50;
        });
        final ascii = rows.join('\n');

        final map = parseAsciiMap(id: 'test', name: 'Test', ascii: ascii);

        expect(map.barriers.contains(map.spawnPoint), isFalse);
      });

      test('terminal stations are not barriers', () {
        final rows = List.generate(50, (y) {
          if (y == 0) return 'S${'.' * 49}';
          if (y == 10) return 'T${'.' * 49}';
          return '.' * 50;
        });
        final ascii = rows.join('\n');

        final map = parseAsciiMap(id: 'test', name: 'Test', ascii: ascii);

        expect(map.barriers.contains(const Point(0, 10)), isFalse);
      });

      test('handles leading and trailing blank lines', () {
        final rows = <String>['', ''];
        rows.addAll(List.generate(50, (y) {
          if (y == 25) return '${'.' * 25}S${'.' * 24}';
          return '.' * 50;
        }));
        rows.addAll(['', '']);
        final ascii = rows.join('\n');

        final map = parseAsciiMap(id: 'test', name: 'Test', ascii: ascii);

        expect(map.spawnPoint, equals(const Point(25, 25)));
      });
    });

    group('error handling', () {
      test('throws on missing spawn point', () {
        final ascii = List.generate(50, (_) => '.' * 50).join('\n');

        expect(
          () => parseAsciiMap(id: 'test', name: 'Test', ascii: ascii),
          throwsA(isA<FormatException>().having(
            (e) => e.message,
            'message',
            contains('no spawn point'),
          )),
        );
      });

      test('throws on multiple spawn points', () {
        final rows = List.generate(50, (y) {
          if (y == 0) return 'S${'.' * 49}';
          if (y == 1) return 'S${'.' * 49}';
          return '.' * 50;
        });
        final ascii = rows.join('\n');

        expect(
          () => parseAsciiMap(id: 'test', name: 'Test', ascii: ascii),
          throwsA(isA<FormatException>().having(
            (e) => e.message,
            'message',
            contains('multiple spawn points'),
          )),
        );
      });

      test('throws on invalid character', () {
        final rows = List.generate(50, (y) {
          if (y == 0) return 'X${'.' * 49}';
          if (y == 25) return '${'.' * 25}S${'.' * 24}';
          return '.' * 50;
        });
        final ascii = rows.join('\n');

        expect(
          () => parseAsciiMap(id: 'test', name: 'Test', ascii: ascii),
          throwsA(isA<FormatException>().having(
            (e) => e.message,
            'message',
            contains('invalid character'),
          )),
        );
      });

      test('throws on wrong number of rows', () {
        final ascii = List.generate(49, (_) => '.' * 50).join('\n');

        expect(
          () => parseAsciiMap(id: 'test', name: 'Bad Rows', ascii: ascii),
          throwsA(isA<FormatException>().having(
            (e) => e.message,
            'message',
            contains('49 rows'),
          )),
        );
      });

      test('throws on wrong number of columns', () {
        final rows = List.generate(50, (y) {
          if (y == 0) return '.' * 48; // Too short
          return '.' * 50;
        });
        final ascii = rows.join('\n');

        expect(
          () => parseAsciiMap(id: 'test', name: 'Bad Cols', ascii: ascii),
          throwsA(isA<FormatException>().having(
            (e) => e.message,
            'message',
            contains('48 columns'),
          )),
        );
      });
    });
  });

  group('theLibrary (ASCII art map)', () {
    test('has correct id', () {
      expect(theLibrary.id, equals('the_library'));
    });

    test('has correct name', () {
      expect(theLibrary.name, equals('The Library'));
    });

    test('has no predefined barriers', () {
      expect(theLibrary.barriers, isEmpty);
    });

    test('has terminals', () {
      expect(theLibrary.terminals, isNotEmpty);
      expect(theLibrary.terminals.length, equals(4));
    });

    test('has spawn point', () {
      expect(theLibrary.spawnPoint, isNotNull);
    });
  });

  group('theWorkshop (ASCII art map)', () {
    test('has correct id', () {
      expect(theWorkshop.id, equals('the_workshop'));
    });

    test('has correct name', () {
      expect(theWorkshop.name, equals('The Workshop'));
    });

    test('has no predefined barriers', () {
      expect(theWorkshop.barriers, isEmpty);
    });

    test('has terminals', () {
      expect(theWorkshop.terminals, isNotEmpty);
      expect(theWorkshop.terminals.length, equals(2));
    });

    test('has spawn point', () {
      expect(theWorkshop.spawnPoint, isNotNull);
    });
  });

  group('reachability', () {
    /// BFS flood fill from spawn point to verify all terminals are reachable.
    Set<Point<int>> floodFill(GameMap map) {
      final barrierSet = map.barriers.toSet();
      final visited = <Point<int>>{};
      final queue = <Point<int>>[map.spawnPoint];
      visited.add(map.spawnPoint);

      while (queue.isNotEmpty) {
        final current = queue.removeAt(0);
        for (final dir in [
          const Point(0, -1),
          const Point(0, 1),
          const Point(-1, 0),
          const Point(1, 0),
        ]) {
          final next = Point(current.x + dir.x, current.y + dir.y);
          if (next.x >= 0 &&
              next.x < gridSize &&
              next.y >= 0 &&
              next.y < gridSize &&
              !barrierSet.contains(next) &&
              !visited.contains(next)) {
            visited.add(next);
            queue.add(next);
          }
        }
      }
      return visited;
    }

    test('all terminals in theLibrary are reachable from spawn', () {
      final reachable = floodFill(theLibrary);
      for (final terminal in theLibrary.terminals) {
        expect(reachable.contains(terminal), isTrue,
            reason:
                'Terminal at (${terminal.x}, ${terminal.y}) should be reachable from spawn');
      }
    });

    test('all terminals in theWorkshop are reachable from spawn', () {
      final reachable = floodFill(theWorkshop);
      for (final terminal in theWorkshop.terminals) {
        expect(reachable.contains(terminal), isTrue,
            reason:
                'Terminal at (${terminal.x}, ${terminal.y}) should be reachable from spawn');
      }
    });

    test('all maps have terminals reachable from spawn', () {
      for (final map in allMaps) {
        if (map.terminals.isEmpty) continue;
        final reachable = floodFill(map);
        for (final terminal in map.terminals) {
          expect(reachable.contains(terminal), isTrue,
              reason: '${map.name}: terminal at (${terminal.x}, ${terminal.y}) '
                  'should be reachable from spawn');
        }
      }
    });
  });
}
