import 'package:flame/components.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tech_world/flame/components/mention_arc_component.dart';
import 'package:tech_world/flame/components/mention_beacon_component.dart';
import 'package:tech_world/flame/mention/mention_pulse_controller.dart';
import 'package:tech_world/flame/mention/mention_world_controller.dart';

/// A stand-in avatar — any PositionComponent works since the controller only
/// needs a parent to attach the beacon to and a position to sample.
class _FakeAvatar extends PositionComponent {
  _FakeAvatar(Vector2 pos) {
    position = pos;
  }
}

void main() {
  group('MentionWorldController', () {
    late DateTime now;
    late MentionPulseController pulse;
    late List<Component> added; // components added to the "world"
    late List<String> acks;
    late Map<String, _FakeAvatar> avatars;
    late bool chatOpen;
    late MentionWorldController controller;

    setUp(() {
      now = DateTime(2026, 6, 22, 12);
      pulse = MentionPulseController(clock: () => now);
      added = [];
      acks = [];
      chatOpen = false;
      avatars = {
        'me': _FakeAvatar(Vector2(0, 0)),
        'alice': _FakeAvatar(Vector2(100, 0)),
        'bob': _FakeAvatar(Vector2(200, 0)),
      };
      controller = MentionWorldController(
        pulseController: pulse,
        localUid: 'me',
        avatarLookup: (uid) => avatars[uid],
        addToWorld: added.add,
        publishAck: acks.add,
        reduceMotion: false,
        isLocalChatOpen: () => chatOpen,
      );
    });

    test('a mention of a present player attaches a beacon to that avatar', () {
      controller.onPlayersMentioned(
        mentionedUids: ['bob'],
        mentionerUid: 'alice',
        messageId: 'm1',
      );

      final beacon = avatars['bob']!.children.whereType<MentionBeaconComponent>();
      expect(beacon, hasLength(1));
      expect(beacon.single.mentionedUid, equals('bob'));
      expect(pulse.isPulsing('bob'), isTrue);
    });

    test('an arc is spawned from mentioner to named when both are present', () {
      controller.onPlayersMentioned(
        mentionedUids: ['bob'],
        mentionerUid: 'alice',
        messageId: 'm1',
      );

      expect(added.whereType<MentionArcComponent>(), hasLength(1));
    });

    test('a mention of an absent player still pulses but skips the beacon/arc',
        () {
      controller.onPlayersMentioned(
        mentionedUids: ['ghost'],
        mentionerUid: 'alice',
        messageId: 'm1',
      );

      // State still tracks the pulse (other clients may render it once the
      // avatar spawns), but nothing is attached locally.
      expect(pulse.isPulsing('ghost'), isTrue);
      expect(added.whereType<MentionArcComponent>(), isEmpty);
    });

    test('an absent mentioner degrades: bloom present, arc skipped', () {
      controller.onPlayersMentioned(
        mentionedUids: ['bob'],
        mentionerUid: 'ghost-sender',
        messageId: 'm1',
      );

      expect(avatars['bob']!.children.whereType<MentionBeaconComponent>(),
          hasLength(1));
      expect(added.whereType<MentionArcComponent>(), isEmpty,
          reason: 'no arc when the mentioner avatar is not present locally');
    });

    test('does NOT self-pulse: the local user opening chat is not a mention',
        () {
      // Mentioning myself is allowed to bloom (others see it), but it must not
      // broadcast an ack on its own — ack is a separate, deliberate signal.
      controller.onPlayersMentioned(
        mentionedUids: ['me'],
        mentionerUid: 'alice',
        messageId: 'm1',
      );
      expect(acks, isEmpty);
      expect(pulse.isPulsing('me'), isTrue);
    });

    test('opening chat acks every pulse currently naming the local user', () {
      controller.onPlayersMentioned(
        mentionedUids: ['me'],
        mentionerUid: 'alice',
        messageId: 'm-self',
      );
      // A pulse naming someone else must not be acked by me opening chat.
      controller.onPlayersMentioned(
        mentionedUids: ['bob'],
        mentionerUid: 'alice',
        messageId: 'm-bob',
      );

      controller.onLocalChatOpened();

      expect(acks, equals(['m-self']));
    });

    test('receiving a matching ack stops the local pulse', () {
      controller.onPlayersMentioned(
        mentionedUids: ['bob'],
        mentionerUid: 'alice',
        messageId: 'm1',
      );
      expect(pulse.isPulsing('bob'), isTrue);

      controller.onMentionAck(
        ackerUid: 'bob',
        messageId: 'm1',
      );

      expect(pulse.isPulsing('bob'), isFalse);
    });

    test('an ack from the WRONG sender for a victim is ignored (trust)', () {
      controller.onPlayersMentioned(
        mentionedUids: ['bob'],
        mentionerUid: 'alice',
        messageId: 'm1',
      );

      // attacker tries to ack bob's pulse by claiming bob's uid in the payload,
      // but onMentionAck is fed the TRANSPORT senderId by the bridge — which is
      // 'attacker', not 'bob'. So it targets attacker's (nonexistent) pulse.
      controller.onMentionAck(
        ackerUid: 'attacker',
        messageId: 'm1',
      );

      expect(pulse.isPulsing('bob'), isTrue,
          reason: 'only the named player (transport identity) can ack');
    });

    test('tick drives auto-timeout', () {
      controller.onPlayersMentioned(
        mentionedUids: ['bob'],
        mentionerUid: 'alice',
        messageId: 'm1',
      );

      now = now.add(MentionPulseController.pulseTimeout +
          const Duration(seconds: 1));
      controller.tick();

      expect(pulse.isPulsing('bob'), isFalse);
    });

    test('a duplicate UID in the list does not create duplicate arcs', () {
      controller.onPlayersMentioned(
        mentionedUids: ['bob', 'bob', 'bob'],
        mentionerUid: 'alice',
        messageId: 'm1',
      );
      expect(added.whereType<MentionArcComponent>(), hasLength(1));
      expect(avatars['bob']!.children.whereType<MentionBeaconComponent>(),
          hasLength(1));
    });

    test('reconcileBeaconFor attaches a beacon to a late-spawning avatar', () {
      // Mention arrives before the avatar exists locally.
      controller.onPlayersMentioned(
        mentionedUids: ['ghost'],
        mentionerUid: 'alice',
        messageId: 'm1',
      );
      expect(pulse.isPulsing('ghost'), isTrue);

      // The avatar spawns later → reconcile attaches the beacon.
      final ghost = _FakeAvatar(Vector2(300, 0));
      controller.reconcileBeaconFor('ghost', ghost);
      expect(ghost.children.whereType<MentionBeaconComponent>(), hasLength(1));
    });

    test('reconcileBeaconFor is a no-op when not pulsing', () {
      final fresh = _FakeAvatar(Vector2(0, 0));
      controller.reconcileBeaconFor('nobody', fresh);
      expect(fresh.children.whereType<MentionBeaconComponent>(), isEmpty);
    });

    test('reconcileBeaconFor does not double-attach if a beacon exists', () {
      controller.onPlayersMentioned(
        mentionedUids: ['bob'],
        mentionerUid: 'alice',
        messageId: 'm1',
      );
      controller.reconcileBeaconFor('bob', avatars['bob']!);
      expect(avatars['bob']!.children.whereType<MentionBeaconComponent>(),
          hasLength(1));
    });

    test('a mention of me while chat is ALREADY open auto-acks immediately',
        () {
      chatOpen = true;
      controller.onPlayersMentioned(
        mentionedUids: ['me'],
        mentionerUid: 'alice',
        messageId: 'm-self',
      );
      expect(acks, equals(['m-self']),
          reason: 'already-open chat should ack without waiting for re-open');
      expect(pulse.isPulsing('me'), isFalse);
    });

    test('a mention of me while chat is CLOSED does not auto-ack', () {
      chatOpen = false;
      controller.onPlayersMentioned(
        mentionedUids: ['me'],
        mentionerUid: 'alice',
        messageId: 'm-self',
      );
      expect(acks, isEmpty);
      expect(pulse.isPulsing('me'), isTrue);
    });
  });
}
