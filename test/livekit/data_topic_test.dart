import 'package:flutter_test/flutter_test.dart';
import 'package:tech_world/livekit/data_topic.dart';

void main() {
  group('DataTopic.parse', () {
    group('round-trips all values', () {
      for (final topic in DataTopic.values) {
        test('round-trips ${topic.name}', () {
          expect(DataTopic.parse(topic.wireName), equals(topic));
        });
      }
    });

    test('returns null for unknown wire name', () {
      expect(DataTopic.parse('unknown'), isNull);
    });

    test('returns null for empty string', () {
      expect(DataTopic.parse(''), isNull);
    });

    test('returns null for null input', () {
      expect(DataTopic.parse(null), isNull);
    });
  });
}
