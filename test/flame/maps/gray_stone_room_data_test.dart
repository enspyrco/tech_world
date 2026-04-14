import 'package:flutter_test/flutter_test.dart';
import 'package:tech_world/flame/maps/gray_stone_room_data.dart';
import 'package:tech_world/flame/maps/game_map.dart';

void main() {
  group('buildGrayStoneRoom', () {
    late GameMap room;

    setUpAll(() {
      room = buildGrayStoneRoom();
    });

    test('has correct identity', () {
      expect(room.id, 'l_room');
      expect(room.name, 'Imagination Center');
    });

    test('has no predefined barriers', () {
      expect(room.barriers, isEmpty);
    });

    test('has default spawn point', () {
      expect(room.spawnPoint.x, 25);
      expect(room.spawnPoint.y, 25);
    });

    test('has no predefined terminals', () {
      expect(room.terminals, isEmpty);
    });

    test('uses room_builder_office tileset', () {
      expect(room.tilesetIds, contains('room_builder_office'));
    });

    test('has non-empty floor layer', () {
      expect(room.floorLayer, isNotNull);
      expect(room.floorLayer!.isEmpty, isFalse);
    });

    test('floor layer references room_builder_office', () {
      expect(
        room.floorLayer!.referencedTilesetIds,
        equals({'room_builder_office'}),
      );
    });

    test('has no pre-built object layer', () {
      // Object layer is built at runtime from Firestore barriers.
      expect(room.objectLayer, isNull);
    });
  });
}
