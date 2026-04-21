import 'dart:math';

import 'package:collection/collection.dart';

/// Data model for a door in the game world.
///
/// Doors are barriers that can be unlocked by completing specific challenges.
/// When locked, they block movement like any other barrier. When unlocked,
/// they become passable.
class DoorData {
  DoorData({
    required this.position,
    this.requiredChallengeIds = const [],
    this.isUnlocked = false,
  });

  /// Grid position of the door.
  final Point<int> position;

  /// IDs of challenges that must be completed to unlock this door.
  ///
  /// An empty list means the door can be unlocked without solving anything
  /// (e.g. via a switch or event trigger).
  final List<String> requiredChallengeIds;

  /// Whether the door is currently unlocked (passable).
  bool isUnlocked;

  /// Serialize to JSON.
  Map<String, dynamic> toJson() => {
        'x': position.x,
        'y': position.y,
        if (requiredChallengeIds.isNotEmpty) 'challenges': requiredChallengeIds,
      };

  /// Deserialize from JSON.
  factory DoorData.fromJson(Map<String, dynamic> json) => DoorData(
        position: Point(json['x'] as int, json['y'] as int),
        requiredChallengeIds: (json['challenges'] as List<dynamic>?)
                ?.cast<String>()
                .toList() ??
            const [],
      );

  static const _listEquality = ListEquality<String>();

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DoorData &&
          position == other.position &&
          _listEquality.equals(requiredChallengeIds,
              other.requiredChallengeIds) &&
          isUnlocked == other.isUnlocked;

  @override
  int get hashCode => Object.hash(
        position,
        _listEquality.hash(requiredChallengeIds),
        isUnlocked,
      );
}
