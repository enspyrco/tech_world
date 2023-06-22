import 'package:flutter_test/flutter_test.dart';
import 'package:tech_world/game/background/barriers.dart';

void main() {
  group('Barriers', () {
    test('should go to json and back and be equal', () {
      var barriers = const Barriers();
      var json = barriers.toJson();
      var barriers2 = Barriers.fromJson(json as Map<String, dynamic>);

      expect(barriers, equals(barriers2));
    });
  });
}
