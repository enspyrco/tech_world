import 'package:flutter_test/flutter_test.dart';
import 'package:tech_world/flame/components/tile_floor_component.dart';
import 'package:tech_world/flame/tiles/tile_layer_data.dart';
import 'package:tech_world/flame/tiles/tile_ref.dart';
import 'package:tech_world/flame/tiles/tileset_registry.dart';

void main() {
  group('TileFloorComponent', () {
    late TilesetRegistry registry;

    setUp(() {
      registry = TilesetRegistry.forTesting();
    });

    test('can be constructed with layer data and registry', () {
      final layer = TileLayerData();
      final component = TileFloorComponent(
        layerData: layer,
        registry: registry,
      );

      expect(component.layerData, same(layer));
      expect(component.registry, same(registry));
    });

    test('has priority -2', () {
      final component = TileFloorComponent(
        layerData: TileLayerData(),
        registry: registry,
      );

      expect(component.priority, -2);
    });

    test('animatedTileCount is 0 for empty layer', () {
      final component = TileFloorComponent(
        layerData: TileLayerData(),
        registry: registry,
      );

      expect(component.animatedTileCount, 0);
    });

    test('animatedTileCount is 0 for layer with only static tiles', () {
      final layer = TileLayerData();
      // Tile index 0 of ext_terrains is not animated.
      layer.setTile(5, 5, const TileRef(tilesetId: 'ext_terrains', tileIndex: 0));
      layer.setTile(6, 6, const TileRef(tilesetId: 'ext_terrains', tileIndex: 1));

      final component = TileFloorComponent(
        layerData: layer,
        registry: registry,
      );

      expect(component.animatedTileCount, 0);
    });

    test('animatedTileCount reflects animated tiles in layer', () {
      final layer = TileLayerData();
      // Waterfall body water right: row 50, col 26 = index 1626 (animated)
      layer.setTile(0, 0, const TileRef(tilesetId: 'ext_terrains', tileIndex: 1626));
      // Static tile
      layer.setTile(1, 1, const TileRef(tilesetId: 'ext_terrains', tileIndex: 0));
      // Another animated tile: row 50, col 29 = index 1629 (frame 2 of same)
      // This maps to same animation but placed at different grid position.
      layer.setTile(2, 2, const TileRef(tilesetId: 'ext_terrains', tileIndex: 1629));

      final component = TileFloorComponent(
        layerData: layer,
        registry: registry,
      );

      expect(component.animatedTileCount, 2);
    });

    test('tickerCount reflects unique animations', () {
      final layer = TileLayerData();
      // Two tiles using the SAME animation (row 50, col 26 — indices 1626, 1629)
      layer.setTile(0, 0, const TileRef(tilesetId: 'ext_terrains', tileIndex: 1626));
      layer.setTile(1, 1, const TileRef(tilesetId: 'ext_terrains', tileIndex: 1629));
      // A tile using a DIFFERENT animation (row 49, col 26 — indices 1594, 1597)
      layer.setTile(2, 2, const TileRef(tilesetId: 'ext_terrains', tileIndex: 1594));

      final component = TileFloorComponent(
        layerData: layer,
        registry: registry,
      );

      // Two unique TileAnimations — one for row 50 col 26 and one for row 49 col 26.
      expect(component.tickerCount, 2);
    });

    test('tiles from unknown tilesets are treated as static', () {
      final layer = TileLayerData();
      // Unknown tileset — no animations defined.
      layer.setTile(0, 0, const TileRef(tilesetId: 'unknown', tileIndex: 1626));

      final component = TileFloorComponent(
        layerData: layer,
        registry: registry,
      );

      expect(component.animatedTileCount, 0);
    });
  });
}
