import 'package:tech_world/flame/tiles/tile_ref.dart';
import 'package:tech_world/map_editor/map_editor_state.dart';

/// A condition that must be satisfied for an automap rule to apply.
///
/// Checks the cell at ([dx], [dy]) offset from the current cell being
/// evaluated. At least one of [structureType] or [isEmpty] should be provided.
class AutomapCondition {
  /// Creates a condition checking a neighbor cell at the given offset.
  const AutomapCondition({
    required this.dx,
    required this.dy,
    this.structureType,
    this.isEmpty,
  });

  /// Horizontal offset from the current cell.
  final int dx;

  /// Vertical offset from the current cell.
  final int dy;

  /// If set, the structure grid cell at this offset must match this type.
  final TileType? structureType;

  /// If set, checks whether the object layer at this offset is empty (`true`)
  /// or occupied (`false`).
  final bool? isEmpty;

  /// Deserialize from a JSON map.
  factory AutomapCondition.fromJson(Map<String, dynamic> json) {
    return AutomapCondition(
      dx: json['dx'] as int,
      dy: json['dy'] as int,
      structureType: json['structureType'] != null
          ? TileType.values.byName(json['structureType'] as String)
          : null,
      isEmpty: json['isEmpty'] as bool?,
    );
  }

  /// Serialize to a JSON map. Null fields are omitted.
  Map<String, dynamic> toJson() => {
        'dx': dx,
        'dy': dy,
        if (structureType != null) 'structureType': structureType!.name,
        if (isEmpty != null) 'isEmpty': isEmpty,
      };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AutomapCondition &&
          dx == other.dx &&
          dy == other.dy &&
          structureType == other.structureType &&
          isEmpty == other.isEmpty;

  @override
  int get hashCode => Object.hash(dx, dy, structureType, isEmpty);
}

/// What to place when an automap rule matches.
class AutomapOutput {
  /// Creates an output specifying which tile to place on which layer.
  const AutomapOutput({
    required this.targetLayer,
    required this.tile,
  });

  /// The layer to place the tile on (currently only `'object'` is supported).
  final String targetLayer;

  /// The tile to place.
  final TileRef tile;

  /// Deserialize from a JSON map.
  factory AutomapOutput.fromJson(Map<String, dynamic> json) {
    return AutomapOutput(
      targetLayer: json['targetLayer'] as String,
      tile: TileRef.fromJson(json['tile'] as Map<String, dynamic>),
    );
  }

  /// Serialize to a JSON map.
  Map<String, dynamic> toJson() => {
        'targetLayer': targetLayer,
        'tile': tile.toJson(),
      };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AutomapOutput &&
          targetLayer == other.targetLayer &&
          tile == other.tile;

  @override
  int get hashCode => Object.hash(targetLayer, tile);
}

/// A pattern-based rule for automatic tile placement.
///
/// When all [conditions] match for a given cell, the [output] tile is placed.
/// Rules with higher [priority] are evaluated first; the first match wins
/// per cell.
class AutomapRule {
  /// Creates an automap rule.
  const AutomapRule({
    required this.id,
    required this.name,
    required this.conditions,
    required this.output,
    required this.priority,
  });

  /// Unique identifier for this rule.
  final String id;

  /// Human-readable name.
  final String name;

  /// All conditions that must be true for this rule to match a cell.
  final List<AutomapCondition> conditions;

  /// What to place when the rule matches.
  final AutomapOutput output;

  /// Higher priority rules are evaluated first. First match wins per cell.
  final int priority;

  /// Deserialize from a JSON map.
  factory AutomapRule.fromJson(Map<String, dynamic> json) {
    return AutomapRule(
      id: json['id'] as String,
      name: json['name'] as String,
      conditions: (json['conditions'] as List)
          .map((c) => AutomapCondition.fromJson(c as Map<String, dynamic>))
          .toList(),
      output: AutomapOutput.fromJson(json['output'] as Map<String, dynamic>),
      priority: json['priority'] as int,
    );
  }

  /// Serialize to a JSON map.
  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'conditions': conditions.map((c) => c.toJson()).toList(),
        'output': output.toJson(),
        'priority': priority,
      };

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is AutomapRule && id == other.id;

  @override
  int get hashCode => id.hashCode;
}
