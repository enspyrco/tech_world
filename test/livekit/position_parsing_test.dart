import 'package:flame/components.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tech_world/flame/shared/direction.dart';
import 'package:tech_world/flame/shared/player_path.dart';

/// Tests for player path JSON parsing logic.
/// This tests the format used for position sync via LiveKit data channels.
void main() {
  group('PlayerPath JSON parsing', () {
    test('parses valid position message', () {
      final json = {
        'playerId': 'player123',
        'points': [
          {'x': 100.0, 'y': 200.0},
          {'x': 150.0, 'y': 200.0},
        ],
        'directions': ['right', 'right'],
      };

      final path = parsePlayerPath(json);

      expect(path, isNotNull);
      expect(path!.playerId, equals('player123'));
      expect(path.largeGridPoints.length, equals(2));
      expect(path.largeGridPoints[0], equals(Vector2(100.0, 200.0)));
      expect(path.largeGridPoints[1], equals(Vector2(150.0, 200.0)));
      expect(path.directions, equals([Direction.right, Direction.right]));
    });

    test('parses integer coordinates as doubles', () {
      final json = {
        'playerId': 'player123',
        'points': [
          {'x': 100, 'y': 200},
        ],
        'directions': ['down'],
      };

      final path = parsePlayerPath(json);

      expect(path, isNotNull);
      expect(path!.largeGridPoints[0], equals(Vector2(100.0, 200.0)));
    });

    test('returns null when playerId is missing', () {
      final json = {
        'points': [
          {'x': 100.0, 'y': 200.0},
        ],
        'directions': ['right'],
      };

      final path = parsePlayerPath(json);
      expect(path, isNull);
    });

    test('returns null when points is missing', () {
      final json = {
        'playerId': 'player123',
        'directions': ['right'],
      };

      final path = parsePlayerPath(json);
      expect(path, isNull);
    });

    test('returns null when directions is missing', () {
      final json = {
        'playerId': 'player123',
        'points': [
          {'x': 100.0, 'y': 200.0},
        ],
      };

      final path = parsePlayerPath(json);
      expect(path, isNull);
    });

    test('handles unknown direction gracefully', () {
      final json = {
        'playerId': 'player123',
        'points': [
          {'x': 100.0, 'y': 200.0},
        ],
        'directions': ['unknown_direction'],
      };

      final path = parsePlayerPath(json);

      expect(path, isNotNull);
      expect(path!.directions, equals([Direction.none]));
    });

    test('handles all valid directions', () {
      final json = {
        'playerId': 'player123',
        'points': List.generate(9, (i) => {'x': i * 10.0, 'y': i * 10.0}),
        'directions': [
          'up',
          'down',
          'left',
          'right',
          'upLeft',
          'upRight',
          'downLeft',
          'downRight',
          'none',
        ],
      };

      final path = parsePlayerPath(json);

      expect(path, isNotNull);
      expect(path!.directions, equals([
        Direction.up,
        Direction.down,
        Direction.left,
        Direction.right,
        Direction.upLeft,
        Direction.upRight,
        Direction.downLeft,
        Direction.downRight,
        Direction.none,
      ]));
    });

    test('handles empty points array', () {
      final json = {
        'playerId': 'player123',
        'points': <Map<String, dynamic>>[],
        'directions': <String>[],
      };

      final path = parsePlayerPath(json);

      expect(path, isNotNull);
      expect(path!.largeGridPoints, isEmpty);
      expect(path.directions, isEmpty);
    });

    test('roundtrip: serialize and deserialize', () {
      final original = PlayerPath(
        playerId: 'test-player',
        largeGridPoints: [Vector2(10, 20), Vector2(30, 40)],
        directions: [Direction.right, Direction.downRight],
      );

      // Serialize (like publishPosition does)
      final json = {
        'playerId': original.playerId,
        'points': original.largeGridPoints
            .map((p) => {'x': p.x, 'y': p.y})
            .toList(),
        'directions': original.directions.map((d) => d.name).toList(),
      };

      // Deserialize
      final parsed = parsePlayerPath(json);

      expect(parsed, isNotNull);
      expect(parsed!.playerId, equals(original.playerId));
      expect(parsed.largeGridPoints.length,
          equals(original.largeGridPoints.length));
      for (var i = 0; i < parsed.largeGridPoints.length; i++) {
        expect(parsed.largeGridPoints[i].x, equals(original.largeGridPoints[i].x));
        expect(parsed.largeGridPoints[i].y, equals(original.largeGridPoints[i].y));
      }
      expect(parsed.directions, equals(original.directions));
    });
  });
}

/// Parse a player path from JSON (mirrors LiveKitService._parsePlayerPath)
PlayerPath? parsePlayerPath(Map<String, dynamic> json) {
  try {
    final playerId = json['playerId'] as String?;
    final pointsJson = json['points'] as List<dynamic>?;
    final directionsJson = json['directions'] as List<dynamic>?;

    if (playerId == null || pointsJson == null || directionsJson == null) {
      return null;
    }

    final points = pointsJson
        .map((p) => Vector2(
              (p['x'] as num).toDouble(),
              (p['y'] as num).toDouble(),
            ))
        .toList();

    final directions = directionsJson
        .map((d) => Direction.values.asNameMap()[d] ?? Direction.none)
        .toList();

    return PlayerPath(
      playerId: playerId,
      largeGridPoints: points,
      directions: directions,
    );
  } catch (e) {
    return null;
  }
}
