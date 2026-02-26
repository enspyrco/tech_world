import 'package:flutter/material.dart';
import 'package:tech_world/flame/maps/game_map.dart';
import 'package:tech_world/flame/maps/generators/map_generator.dart';
import 'package:tech_world/flame/maps/predefined_maps.dart';
import 'package:tech_world/flame/tech_world.dart';

/// Dropdown for switching the active game map at runtime.
class MapSelector extends StatelessWidget {
  const MapSelector({super.key, required this.techWorld});

  final TechWorld techWorld;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<GameMap>(
      valueListenable: techWorld.currentMap,
      builder: (context, activeMap, _) {
        return PopupMenuButton<GameMap>(
          offset: const Offset(0, 48),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          onSelected: (map) => techWorld.loadMap(map),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.black54,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.map, color: Colors.white70, size: 18),
                const SizedBox(width: 6),
                Text(
                  activeMap.name,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(width: 4),
                const Icon(Icons.arrow_drop_down,
                    color: Colors.white70, size: 18),
              ],
            ),
          ),
          itemBuilder: (context) => [
            for (final map in allMaps)
              PopupMenuItem<GameMap>(
                value: map,
                child: Row(
                  children: [
                    if (map.id == activeMap.id)
                      const Icon(Icons.check, size: 16, color: Colors.blue)
                    else
                      const SizedBox(width: 16),
                    const SizedBox(width: 8),
                    Text(map.name),
                  ],
                ),
              ),
            const PopupMenuDivider(),
            for (final algo in MapAlgorithm.values)
              PopupMenuItem<GameMap>(
                // value is null — onTap handles generation instead.
                onTap: () {
                  final map = generateMap(algorithm: algo);
                  techWorld.loadMap(map);
                },
                child: Row(
                  children: [
                    const Icon(Icons.casino, size: 16, color: Colors.orange),
                    const SizedBox(width: 8),
                    Text('Generate ${algo.displayName}'),
                  ],
                ),
              ),
          ],
        );
      },
    );
  }
}
