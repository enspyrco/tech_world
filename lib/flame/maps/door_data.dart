import 'dart:math';

import 'package:collection/collection.dart';
import 'package:logging/logging.dart';
import 'package:tech_world/prompt/prompt_challenge.dart';

final _log = Logger('DoorData');

/// Data model for a door in the game world.
///
/// Doors are barriers that can be unlocked by completing specific
/// prompt-engineering challenges (the spellbook 18). When locked, they
/// block movement like any other barrier. When unlocked, they become
/// passable.
class DoorData {
  DoorData({
    required this.position,
    this.requiredChallengeIds = const [],
    this.isUnlocked = false,
  });

  /// Grid position of the door.
  final Point<int> position;

  /// Prompt challenges that must all be completed to unlock this door.
  ///
  /// An empty list means the door can be unlocked without solving anything
  /// (e.g. via a switch or event trigger).
  final List<PromptChallengeId> requiredChallengeIds;

  /// Whether the door is currently unlocked (passable).
  bool isUnlocked;

  /// Serialize to JSON. Each challenge is stored as its
  /// [PromptChallengeId.wireName] (snake_case), preserving the existing
  /// on-disk format so older saves keep loading.
  Map<String, dynamic> toJson() => {
        'x': position.x,
        'y': position.y,
        if (requiredChallengeIds.isNotEmpty)
          'challenges': [
            for (final id in requiredChallengeIds) id.wireName,
          ],
      };

  /// Deserialize from JSON. Unknown challenge wire forms are logged and
  /// skipped — older clients can still load saves that name challenges
  /// they don't recognise yet (forward-compat).
  factory DoorData.fromJson(Map<String, dynamic> json) {
    final raw = json['challenges'] as List<dynamic>?;
    final ids = <PromptChallengeId>[];
    if (raw != null) {
      for (final wire in raw) {
        final parsed = PromptChallengeId.parse(wire as String);
        if (parsed == null) {
          _log.warning(
              'DoorData.fromJson: unknown challenge wire form "$wire"; '
              'skipping');
          continue;
        }
        ids.add(parsed);
      }
    }
    return DoorData(
      position: Point(json['x'] as int, json['y'] as int),
      requiredChallengeIds: ids,
    );
  }

  static const _listEquality = ListEquality<PromptChallengeId>();

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
