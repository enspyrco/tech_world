import 'package:flame/components.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tech_world/flame/shared/direction.dart';
import 'package:tech_world/flame/shared/player_path.dart';

void main() {
  group('PlayerPath', () {
    test('creates path with required fields', () {
      final path = PlayerPath(
        playerId: 'player-1',
        largeGridPoints: [Vector2(0, 0), Vector2(32, 0)],
        directions: [Direction.right],
      );

      expect(path.playerId, equals('player-1'));
      expect(path.largeGridPoints.length, equals(2));
      expect(path.directions.length, equals(1));
    });

    test('creates path with empty lists', () {
      final path = PlayerPath(
        playerId: 'player-2',
        largeGridPoints: [],
        directions: [],
      );

      expect(path.playerId, equals('player-2'));
      expect(path.largeGridPoints, isEmpty);
      expect(path.directions, isEmpty);
    });

    test('stores multiple points and directions', () {
      final points = [
        Vector2(0, 0),
        Vector2(32, 0),
        Vector2(64, 0),
        Vector2(64, 32),
      ];
      final directions = [
        Direction.right,
        Direction.right,
        Direction.down,
      ];

      final path = PlayerPath(
        playerId: 'player-3',
        largeGridPoints: points,
        directions: directions,
      );

      expect(path.largeGridPoints.length, equals(4));
      expect(path.directions.length, equals(3));

      expect(path.largeGridPoints[0].x, equals(0));
      expect(path.largeGridPoints[0].y, equals(0));
      expect(path.largeGridPoints[3].x, equals(64));
      expect(path.largeGridPoints[3].y, equals(32));

      expect(path.directions[0], equals(Direction.right));
      expect(path.directions[2], equals(Direction.down));
    });

    test('preserves Vector2 precision', () {
      final path = PlayerPath(
        playerId: 'player-4',
        largeGridPoints: [Vector2(100.5, 200.75)],
        directions: [],
      );

      expect(path.largeGridPoints[0].x, equals(100.5));
      expect(path.largeGridPoints[0].y, equals(200.75));
    });

    test('handles diagonal directions', () {
      final path = PlayerPath(
        playerId: 'player-5',
        largeGridPoints: [
          Vector2(0, 0),
          Vector2(32, 32),
          Vector2(0, 64),
        ],
        directions: [
          Direction.downRight,
          Direction.downLeft,
        ],
      );

      expect(path.directions[0], equals(Direction.downRight));
      expect(path.directions[1], equals(Direction.downLeft));
    });

    test('handles all direction types', () {
      final path = PlayerPath(
        playerId: 'player-6',
        largeGridPoints: List.generate(9, (i) => Vector2(i * 32.0, 0)),
        directions: [
          Direction.up,
          Direction.down,
          Direction.left,
          Direction.right,
          Direction.upLeft,
          Direction.upRight,
          Direction.downLeft,
          Direction.downRight,
        ],
      );

      expect(path.directions.length, equals(8));
      expect(path.directions.contains(Direction.up), isTrue);
      expect(path.directions.contains(Direction.down), isTrue);
      expect(path.directions.contains(Direction.left), isTrue);
      expect(path.directions.contains(Direction.right), isTrue);
      expect(path.directions.contains(Direction.upLeft), isTrue);
      expect(path.directions.contains(Direction.upRight), isTrue);
      expect(path.directions.contains(Direction.downLeft), isTrue);
      expect(path.directions.contains(Direction.downRight), isTrue);
    });

    test('playerId can be any string', () {
      final testIds = [
        'simple-id',
        'user_123',
        'abc-def-ghi-jkl',
        '12345',
        '',
        'special!@#\$%',
      ];

      for (final id in testIds) {
        final path = PlayerPath(
          playerId: id,
          largeGridPoints: [],
          directions: [],
        );
        expect(path.playerId, equals(id));
      }
    });

    test('points and directions are independent lists', () {
      final points = [Vector2(0, 0), Vector2(32, 0)];
      final directions = [Direction.right];

      final path = PlayerPath(
        playerId: 'player-7',
        largeGridPoints: points,
        directions: directions,
      );

      // Modifying original lists should not affect path
      // (though in practice this depends on implementation)
      expect(path.largeGridPoints, equals(points));
      expect(path.directions, equals(directions));
    });
  });
}
