import 'package:flutter_test/flutter_test.dart';
import 'package:tech_world/flame/mention/mention_pulse_controller.dart';

void main() {
  group('MentionPulseController', () {
    late MentionPulseController controller;
    late DateTime now;

    setUp(() {
      now = DateTime(2026, 6, 22, 12, 0, 0);
      controller = MentionPulseController(clock: () => now);
    });

    void advance(Duration d) => now = now.add(d);

    test('a mention starts a pulse on the named avatar', () {
      controller.onMention(
        mentionedUid: 'bob',
        mentionerUid: 'alice',
        messageId: 'm1',
      );

      expect(controller.isPulsing('bob'), isTrue);
      expect(controller.isPulsing('carol'), isFalse);
    });

    test('a matching ack stops the pulse', () {
      controller.onMention(
        mentionedUid: 'bob',
        mentionerUid: 'alice',
        messageId: 'm1',
      );

      controller.onAck(mentionedUid: 'bob', messageId: 'm1');

      expect(controller.isPulsing('bob'), isFalse);
    });

    test('a non-matching ack (wrong messageId) does NOT stop the pulse', () {
      controller.onMention(
        mentionedUid: 'bob',
        mentionerUid: 'alice',
        messageId: 'm1',
      );

      // Ack carries a stale / different messageId — must not cancel.
      controller.onAck(mentionedUid: 'bob', messageId: 'WRONG');

      expect(controller.isPulsing('bob'), isTrue);
    });

    test('an ack for a different player does NOT stop this pulse', () {
      controller.onMention(
        mentionedUid: 'bob',
        mentionerUid: 'alice',
        messageId: 'm1',
      );

      controller.onAck(mentionedUid: 'carol', messageId: 'm1');

      expect(controller.isPulsing('bob'), isTrue);
    });

    test('the pulse auto-times out after the timeout window', () {
      controller.onMention(
        mentionedUid: 'bob',
        mentionerUid: 'alice',
        messageId: 'm1',
      );

      // Just before the timeout: still pulsing.
      advance(MentionPulseController.pulseTimeout - const Duration(seconds: 1));
      controller.tick();
      expect(controller.isPulsing('bob'), isTrue);

      // Past the timeout: stops everywhere even with no ack.
      advance(const Duration(seconds: 2));
      controller.tick();
      expect(controller.isPulsing('bob'), isFalse);
    });

    test(
        'concurrent mentions of the same player keep the LATEST messageId; '
        'an ack for the stale id does not cancel', () {
      controller.onMention(
        mentionedUid: 'bob',
        mentionerUid: 'alice',
        messageId: 'm1',
      );
      // A second mention of bob arrives (different sender, new message).
      controller.onMention(
        mentionedUid: 'bob',
        mentionerUid: 'carol',
        messageId: 'm2',
      );

      // Ack for the FIRST mention should not silence the live pulse, because
      // bob only acks once and the active mention is now m2.
      controller.onAck(mentionedUid: 'bob', messageId: 'm1');
      expect(controller.isPulsing('bob'), isTrue);

      // Ack for the current mention stops it.
      controller.onAck(mentionedUid: 'bob', messageId: 'm2');
      expect(controller.isPulsing('bob'), isFalse);
    });

    test('a re-mention refreshes the timeout (does not expire on the old clock)',
        () {
      controller.onMention(
        mentionedUid: 'bob',
        mentionerUid: 'alice',
        messageId: 'm1',
      );

      // Almost expire, then a fresh mention lands.
      advance(MentionPulseController.pulseTimeout - const Duration(seconds: 1));
      controller.onMention(
        mentionedUid: 'bob',
        mentionerUid: 'carol',
        messageId: 'm2',
      );

      // Advance past the ORIGINAL deadline but within the refreshed window.
      advance(const Duration(seconds: 2));
      controller.tick();
      expect(controller.isPulsing('bob'), isTrue,
          reason: 'the re-mention should have reset the timeout clock');
    });

    test('notifies listeners on start, ack, and timeout', () {
      var notifications = 0;
      controller.addListener(() => notifications++);

      controller.onMention(
        mentionedUid: 'bob',
        mentionerUid: 'alice',
        messageId: 'm1',
      );
      expect(notifications, 1);

      controller.onAck(mentionedUid: 'bob', messageId: 'm1');
      expect(notifications, 2);

      controller.onMention(
        mentionedUid: 'carol',
        mentionerUid: 'alice',
        messageId: 'm2',
      );
      expect(notifications, 3);

      advance(MentionPulseController.pulseTimeout + const Duration(seconds: 1));
      controller.tick();
      expect(notifications, 4, reason: 'timeout should notify');
    });

    test('tick with no expirations does not notify', () {
      controller.onMention(
        mentionedUid: 'bob',
        mentionerUid: 'alice',
        messageId: 'm1',
      );
      var notifications = 0;
      controller.addListener(() => notifications++);

      advance(const Duration(seconds: 1));
      controller.tick();
      expect(notifications, 0);
    });

    test('the mentioner of an active pulse is recorded for the arc', () {
      controller.onMention(
        mentionedUid: 'bob',
        mentionerUid: 'alice',
        messageId: 'm1',
      );

      expect(controller.mentionerOf('bob'), equals('alice'));
      expect(controller.mentionerOf('nobody'), isNull);
    });
  });
}
