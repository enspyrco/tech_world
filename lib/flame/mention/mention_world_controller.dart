import 'package:flame/components.dart';
import 'package:tech_world/flame/components/mention_arc_component.dart';
import 'package:tech_world/flame/components/mention_beacon_component.dart';
import 'package:tech_world/flame/mention/mention_pulse_controller.dart';

/// Bridges the `@mention` *state machine* ([MentionPulseController]) to the
/// *world view* (beacons on avatars + the travelling light arc) and to the
/// *ack wire* (broadcasting when the local user sees a mention of themselves).
///
/// This is the seam TechWorld delegates to. It owns no rendering and no wire
/// transport directly — both are injected as callbacks so it is testable
/// without a running game or LiveKit:
///
///  - [avatarLookup] resolves a UID to its on-screen avatar (or null if that
///    player isn't present locally — the graceful-degradation case);
///  - [addToWorld] adds the spanning arc to the World;
///  - [publishAck] broadcasts a `mention-ack` over LiveKit;
///  - [localUid] identifies which mentions are "of me".
///
/// **Trust:** the controller never derives identity from a payload. When a
/// mention arrives, the mentioner UID is the transport-verified chat sender
/// (supplied by the bridge). When an ack arrives, the acker UID is the
/// transport-verified ack sender — so a peer can only ack its OWN mention.
class MentionWorldController {
  MentionWorldController({
    required this.pulseController,
    required this.localUid,
    required this.avatarLookup,
    required this.addToWorld,
    required this.publishAck,
    required this.reduceMotion,
    String Function(String uid)? displayNameLookup,
  }) : displayNameLookup = displayNameLookup ?? ((_) => '');

  /// The shared pulse-state machine (one per client).
  final MentionPulseController pulseController;

  /// UID of the local user — used to detect mentions "of me" and to scope the
  /// ack broadcast.
  final String localUid;

  /// Resolve a player UID to its avatar component, or null if not present
  /// locally (not in room / not yet spawned). Both remote and local.
  final PositionComponent? Function(String uid) avatarLookup;

  /// Add a (world-spanning) component such as the arc to the World.
  final void Function(Component) addToWorld;

  /// Broadcast a `mention-ack` for the local user's [uid] against [messageId].
  final void Function(String uid, String messageId) publishAck;

  /// Accessibility: hold beacon/arc animation still when true.
  final bool reduceMotion;

  /// Resolve a UID to a display name for the beacon's cosmetic label. Defaults
  /// to empty (no label). Avoids reaching into the avatar via dynamic dispatch
  /// (which breaks under WASM).
  final String Function(String uid) displayNameLookup;

  /// Handle an incoming mention (already parsed + trust-checked upstream).
  ///
  /// Starts/refreshes the pulse for every named player, attaches a beacon to
  /// each present avatar, and — when both endpoints are present — spawns the
  /// light arc from the mentioner to the (first) named player. Absent endpoints
  /// degrade gracefully: the pulse state is still recorded, but no local view
  /// is created for an avatar that isn't here.
  void onPlayersMentioned({
    required List<String> mentionedUids,
    required String mentionerUid,
    required String messageId,
  }) {
    final mentionerAvatar = avatarLookup(mentionerUid);

    for (final uid in mentionedUids) {
      pulseController.onMention(
        mentionedUid: uid,
        mentionerUid: mentionerUid,
        messageId: messageId,
      );

      final avatar = avatarLookup(uid);
      if (avatar == null) continue; // not present locally — pulse only.

      // Avoid stacking duplicate beacons if a re-mention lands while one lives;
      // the existing beacon already follows the (refreshed) controller state.
      final hasBeacon =
          avatar.children.whereType<MentionBeaconComponent>().isNotEmpty;
      if (!hasBeacon) {
        avatar.add(MentionBeaconComponent(
          mentionedUid: uid,
          controller: pulseController,
          displayName: displayNameLookup(uid),
          reduceMotion: reduceMotion,
        ));
      }

      // Arc from mentioner → this named avatar, if the mentioner is present.
      if (mentionerAvatar != null && !identical(mentionerAvatar, avatar)) {
        addToWorld(MentionArcComponent(
          from: () => mentionerAvatar.position.clone(),
          to: () => avatar.position.clone(),
        ));
      }
    }
  }

  /// The local user opened the chat panel — acknowledge every live mention that
  /// names them. Broadcasts one `mention-ack` per such pulse (carrying its
  /// messageId) so all clients stop the local user's avatar pulse. Mentions of
  /// OTHER players are untouched — opening my chat only acks mentions of me.
  void onLocalChatOpened() {
    final messageId = pulseController.activeMessageId(localUid);
    if (messageId == null) return;
    publishAck(localUid, messageId);
    // Optimistically stop our own pulse locally too (don't wait for the echo).
    pulseController.onAck(mentionedUid: localUid, messageId: messageId);
  }

  /// Handle an incoming `mention-ack` from the wire. [ackerUid] is the
  /// TRANSPORT-verified sender of the ack — a peer can only ack its own pulse.
  void onMentionAck({required String ackerUid, required String messageId}) {
    pulseController.onAck(mentionedUid: ackerUid, messageId: messageId);
  }

  /// Drive auto-timeout — call each frame from TechWorld.update.
  void tick() => pulseController.tick();

  /// Drop all pulses on room leave.
  void clear() => pulseController.clear();
}
