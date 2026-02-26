import 'dart:math';

import 'package:tech_world/flame/maps/game_map.dart';
import 'package:tech_world/flame/maps/generators/cave_generator.dart';
import 'package:tech_world/flame/maps/generators/dungeon_generator.dart';
import 'package:tech_world/flame/maps/generators/maze_generator.dart';

/// Available procedural map generation algorithms.
enum MapAlgorithm {
  /// BSP rooms connected by corridors.
  dungeon('Dungeon', 'Random rooms connected by corridors'),

  /// Recursive backtracker maze.
  maze('Maze', 'Twisting passages with optional dead-end removal'),

  /// Cellular automata cave.
  cave('Cave', 'Organic cavern shapes via cellular automata');

  const MapAlgorithm(this.displayName, this.description);

  /// Human-readable name shown in UI.
  final String displayName;

  /// Short description of what the algorithm produces.
  final String description;
}

/// Optional configuration for map generation.
///
/// If [seed] is null a random seed is chosen. Algorithm-specific defaults are
/// used when optional fields are left null.
class GeneratorConfig {
  const GeneratorConfig({
    this.seed,
    this.dungeonMinRoomSize = 5,
    this.dungeonMaxRoomSize = 12,
    this.dungeonMaxRooms = 8,
    this.mazeDeadEndRemovalChance = 0.3,
    this.caveFillChance = 0.45,
    this.caveSmoothingIterations = 5,
  });

  /// RNG seed for reproducible maps. If null, a random seed is used.
  final int? seed;

  // -- Dungeon --
  /// Minimum room width/height (inclusive).
  final int dungeonMinRoomSize;

  /// Maximum room width/height (inclusive).
  final int dungeonMaxRoomSize;

  /// Maximum number of rooms to attempt placing.
  final int dungeonMaxRooms;

  // -- Maze --
  /// Probability (0.0 - 1.0) of removing each dead end.
  final double mazeDeadEndRemovalChance;

  // -- Cave --
  /// Initial probability of a cell being a wall (0.0 - 1.0).
  final double caveFillChance;

  /// Number of cellular automata smoothing passes.
  final int caveSmoothingIterations;
}

/// Generates a procedural [GameMap] using the given [algorithm].
///
/// Pass a [config] to control the seed and algorithm-specific parameters.
/// The returned map has no terminals — add those via the map editor.
GameMap generateMap({
  required MapAlgorithm algorithm,
  GeneratorConfig config = const GeneratorConfig(),
}) {
  final seed = config.seed ?? Random().nextInt(1 << 32);

  switch (algorithm) {
    case MapAlgorithm.dungeon:
      return generateDungeon(seed: seed, config: config);
    case MapAlgorithm.maze:
      return generateMaze(seed: seed, config: config);
    case MapAlgorithm.cave:
      return generateCave(seed: seed, config: config);
  }
}
