import 'package:flutter_test/flutter_test.dart';
import 'package:tech_world/flame/tiles/tile_ref.dart';

void main() {
  group('TileRef', () {
    test('stores tilesetId and tileIndex', () {
      const ref = TileRef(tilesetId: 'test', tileIndex: 5);
      expect(ref.tilesetId, 'test');
      expect(ref.tileIndex, 5);
    });

    test('toJson produces expected map', () {
      const ref = TileRef(tilesetId: 'modern_interior', tileIndex: 42);
      expect(ref.toJson(), {'tilesetId': 'modern_interior', 'tileIndex': 42});
    });

    test('fromJson round-trips correctly', () {
      const original = TileRef(tilesetId: 'test', tileIndex: 7);
      final json = original.toJson();
      final restored = TileRef.fromJson(json);
      expect(restored, original);
    });

    test('equality compares tilesetId and tileIndex', () {
      const a = TileRef(tilesetId: 'test', tileIndex: 3);
      const b = TileRef(tilesetId: 'test', tileIndex: 3);
      const c = TileRef(tilesetId: 'test', tileIndex: 4);
      const d = TileRef(tilesetId: 'other', tileIndex: 3);

      expect(a, b);
      expect(a, isNot(c));
      expect(a, isNot(d));
    });

    test('hashCode is consistent with equality', () {
      const a = TileRef(tilesetId: 'test', tileIndex: 3);
      const b = TileRef(tilesetId: 'test', tileIndex: 3);
      expect(a.hashCode, b.hashCode);
    });

    test('toString includes tilesetId and tileIndex', () {
      const ref = TileRef(tilesetId: 'test', tileIndex: 5);
      expect(ref.toString(), 'TileRef(test, 5)');
    });
  });
}
