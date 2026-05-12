import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:logging/logging.dart';
import 'package:meta/meta.dart' show useResult;
import 'package:tech_world/bots/bot_config.dart';
import 'package:tech_world/events/dispatch.dart';
import 'package:tech_world/events/types.dart';
import 'package:tech_world/flame/components/barriers_component.dart';
import 'package:tech_world/flame/components/path_component.dart';
import 'package:tech_world/flame/maps/door_data.dart';
import 'package:tech_world/flame/maps/game_map.dart';
import 'package:tech_world/livekit/data_topic.dart';
import 'package:tech_world/livekit/livekit_service.dart';
import 'package:tech_world/progress/progress_service.dart';
import 'package:tech_world/prompt/prompt_challenge.dart';

final _log = Logger('DoorManager');

/// Manages door state: unlock checks, proximity detection, and LiveKit
/// broadcasting.
///
/// Extracted from [TechWorld] to give door-related concerns a single owner
/// with an explicit dependency surface.
class DoorManager {
  DoorManager({
    required ValueNotifier<GameMap> currentMap,
    required Point<int> Function() getPlayerGrid,
    required LiveKitService? Function() getLiveKit,
    required ProgressService? Function() getProgress,
    required BarriersComponent Function() getBarriers,
    required PathComponent? Function() getPathComponent,
  })  : _currentMap = currentMap,
        _getPlayerGrid = getPlayerGrid,
        _getLiveKit = getLiveKit,
        _getProgress = getProgress,
        _getBarriers = getBarriers,
        _getPathComponent = getPathComponent;

  final ValueNotifier<GameMap> _currentMap;
  final Point<int> Function() _getPlayerGrid;
  final LiveKitService? Function() _getLiveKit;
  final ProgressService? Function() _getProgress;
  final BarriersComponent Function() _getBarriers;
  final PathComponent? Function() _getPathComponent;

  /// Closest still-locked door within [_doorProximityThreshold] grid
  /// squares (Chebyshev) of the player, or `null` if none. Drives the
  /// voice-cast mic FAB — the UI shows the cast affordance only when
  /// the player is near a door they could plausibly try to open.
  final ValueNotifier<DoorData?> nearbyLockedDoor = ValueNotifier(null);

  /// Chebyshev radius for the door-proximity affordance.
  static const int _doorProximityThreshold = 2;

  /// Try to unlock a door and update its visual state.
  ///
  /// Returns `true` if the door actually unlocked, `false` if some required
  /// challenges are still incomplete.
  @useResult
  bool unlockDoor(DoorData door) {
    if (door.requiredChallengeIds.isNotEmpty) {
      final progress = _getProgress();
      if (progress == null) {
        _log.warning('ProgressService not available — door check skipped');
        return false;
      }
      for (final challengeId in door.requiredChallengeIds) {
        if (!progress.isChallengeCompleted(challengeId.wireName)) {
          _log.info(
            'Door at (${door.position.x}, ${door.position.y}) not unlocked: '
            'challenge ${challengeId.wireName} still incomplete',
          );
          return false;
        }
      }
    }

    door.isUnlocked = true;
    _getBarriers().removeBarrierAt(door.position);
    _getPathComponent()?.invalidateGrid();
    recomputeNearbyLockedDoor();

    _getLiveKit()?.publishJson(
      {
        'type': DataTopic.doorUnlock.wireName,
        'doorX': door.position.x,
        'doorY': door.position.y,
      },
      topic: DataTopic.doorUnlock.wireName,
    );

    _log.info('Door unlocked at (${door.position.x}, ${door.position.y})');
    dispatch([DoorUnlocked(doorX: door.position.x, doorY: door.position.y)]);
    return true;
  }

  /// Handle a door-unlock message from another player.
  ///
  /// **Sender verification**: only messages from known human participants
  /// (present in [LiveKitService.remoteParticipants] and not a bot) are
  /// accepted. This prevents arbitrary actors from broadcasting a
  /// `door-unlock` and unlocking doors for all players without completing
  /// the required challenge (originally PR #431).
  void handleRemoteDoorUnlock(DataChannelMessage msg) {
    final senderId = msg.senderId;

    // Reject messages with no sender identity (e.g. server-API injections).
    if (senderId == null) {
      _log.warning('door-unlock ignored: no sender identity');
      return;
    }

    // Reject messages from bots — bots do not complete player challenges.
    if (isBotIdentity(senderId)) {
      _log.warning('door-unlock ignored: sender "$senderId" is a bot');
      return;
    }

    // Reject messages from identities not currently in the room.
    final knownParticipant =
        _getLiveKit()?.remoteParticipants.containsKey(senderId) ?? false;
    if (!knownParticipant) {
      _log.warning(
          'door-unlock ignored: sender "$senderId" is not a known participant');
      return;
    }

    final json = msg.json;
    if (json == null) return;

    final doorX = json['doorX'] as int?;
    final doorY = json['doorY'] as int?;
    if (doorX == null || doorY == null) return;

    final target = Point(doorX, doorY);
    DoorData? door;
    for (final d in _currentMap.value.doors) {
      if (d.position == target) {
        door = d;
        break;
      }
    }
    if (door == null || door.isUnlocked) return;

    door.isUnlocked = true;
    _getBarriers().removeBarrierAt(door.position);
    _getPathComponent()?.invalidateGrid();
    recomputeNearbyLockedDoor();
    _log.info('Remote door unlock at ($doorX, $doorY)');
    dispatch([RemoteDoorUnlocked(doorX: doorX, doorY: doorY)]);
  }

  /// Recompute [nearbyLockedDoor] given the current player position.
  void recomputeNearbyLockedDoor() {
    final playerGrid = _getPlayerGrid();
    DoorData? closest;
    int closestDistance = _doorProximityThreshold + 1;
    for (final door in _currentMap.value.doors) {
      if (door.isUnlocked) continue;
      final d = max(
        (door.position.x - playerGrid.x).abs(),
        (door.position.y - playerGrid.y).abs(),
      );
      if (d <= _doorProximityThreshold && d < closestDistance) {
        closestDistance = d;
        closest = door;
      }
    }
    if (!identical(nearbyLockedDoor.value, closest)) {
      nearbyLockedDoor.value = closest;
    }
  }

  /// Find all doors that require a specific prompt challenge to be completed.
  List<DoorData> doorsForChallenge(PromptChallengeId challengeId) {
    return _currentMap.value.doors
        .where(
            (d) => d.requiredChallengeIds.contains(challengeId) && !d.isUnlocked)
        .toList();
  }
}
