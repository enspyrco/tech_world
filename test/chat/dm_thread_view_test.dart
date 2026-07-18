import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:livekit_client/livekit_client.dart' show RemoteParticipant;
import 'package:tech_world/chat/chat_service.dart';
import 'package:tech_world/chat/conversation.dart';
import 'package:tech_world/chat/dm_thread_view.dart';
import 'package:tech_world/chat/reply_widgets.dart';
import 'package:tech_world/flame/components/bot_status.dart';
import 'package:tech_world/livekit/livekit_service.dart';

/// Minimal LiveKitService fake for driving [DmThreadView] under test.
class _FakeLiveKit implements LiveKitService {
  final _data = StreamController<DataChannelMessage>.broadcast();
  final _joined = StreamController<RemoteParticipant>.broadcast();
  final _left = StreamController<RemoteParticipant>.broadcast();

  /// Captured (peerId, text, replyToMessageId, replyToText) tuples.
  final published = <Map<String, dynamic>>[];

  @override
  bool get isConnected => true;
  @override
  String get userId => 'me';
  @override
  String get displayName => 'Me';
  @override
  String get roomName => 'room';
  @override
  Stream<DataChannelMessage> get dataReceived => _data.stream;
  @override
  Stream<RemoteParticipant> get participantJoined => _joined.stream;
  @override
  Stream<RemoteParticipant> get participantLeft => _left.stream;
  @override
  Map<String, RemoteParticipant> get remoteParticipants => const {};

  @override
  Future<void> publishJson(
    Map<String, dynamic> json, {
    bool reliable = true,
    List<String>? destinationIdentities,
    String? topic,
  }) async {
    published.add({
      'destinationIdentities': destinationIdentities,
      'payload': json,
    });
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  // DmThreadView is not exported as a public widget from the library barrel,
  // so it's imported directly from its file.
  group('DmThreadView quote-reply', () {
    late _FakeLiveKit fakeLiveKit;
    late ChatService chatService;

    setUp(() {
      fakeLiveKit = _FakeLiveKit();
      chatService = ChatService(liveKitService: fakeLiveKit);
      chatService.setBotStatusForTest(BotStatus.idle);
    });

    tearDown(() => chatService.dispose());

    Future<void> pumpThread(WidgetTester tester) async {
      // Seed an inbound DM from the peer so the thread has a message to reply
      // to.
      fakeLiveKit._data.add(DataChannelMessage(
        senderId: 'peer',
        topic: 'dm',
        data: _utf8Json({
          'text': 'Original question',
          'id': 'dm-1',
          'senderName': 'Peer',
          'senderId': 'peer',
        }),
      ));
      await tester.pump();

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: DmThreadView(
            conversation: Conversation(
              id: Conversation.conversationIdFor('me', 'peer'),
              type: ConversationType.dm,
              peerId: 'peer',
              peerDisplayName: 'Peer',
            ),
            chatService: chatService,
            onBack: () {},
          ),
        ),
      ));
      await tester.pumpAndSettle();
    }

    testWidgets('tapping Reply shows the composing banner', (tester) async {
      await pumpThread(tester);

      // The thread shows the original message + a Reply affordance.
      expect(find.text('Original question'), findsOneWidget);
      expect(find.text('Reply'), findsWidgets);

      await tester.tap(find.text('Reply').first);
      await tester.pumpAndSettle();

      // Composing banner appears.
      expect(find.text('Replying to Peer'), findsOneWidget);
    });

    testWidgets('sending a reply publishes reply fields on the wire',
        (tester) async {
      await pumpThread(tester);

      await tester.tap(find.text('Reply').first);
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'I agree');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      // The DM publish carries the reply fields.
      final dmPublish = fakeLiveKit.published.lastWhere(
        (p) => (p['payload'] as Map)['text'] == 'I agree',
      );
      final payload = dmPublish['payload'] as Map<String, dynamic>;
      expect(payload['replyToText'], equals('Original question'));
      expect(payload['replyToSenderName'], equals('Peer'));
      expect(payload['replyToMessageId'], isNotNull);

      // Banner is dismissed after sending.
      expect(find.text('Replying to Peer'), findsNothing);
    });

    testWidgets('cancel button dismisses the composing banner',
        (tester) async {
      await pumpThread(tester);

      await tester.tap(find.text('Reply').first);
      await tester.pumpAndSettle();
      expect(find.text('Replying to Peer'), findsOneWidget);

      await tester.tap(find.byTooltip('Cancel reply'));
      await tester.pumpAndSettle();
      expect(find.text('Replying to Peer'), findsNothing);
    });

    testWidgets('tapping a reply quote highlights the quoted original',
        (tester) async {
      await pumpThread(tester); // seeds inbound original (id 'dm-1')

      // Compose + send a reply to the original.
      await tester.tap(find.text('Reply').first);
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'I agree');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      // The reply renders exactly one tappable quote; nothing is highlighted yet.
      expect(find.byType(QuotedMessage), findsOneWidget);
      expect(find.byKey(const ValueKey('dm-highlight')), findsNothing);

      // Tap the quote → scroll to + flash the original.
      await tester.tap(find.byType(QuotedMessage));
      await tester.pump(); // setState applies highlight
      await tester.pump(const Duration(milliseconds: 250)); // animate flash
      expect(find.byKey(const ValueKey('dm-highlight')), findsOneWidget);

      // The flash clears after its delay (also drains the pending timer).
      await tester.pump(const Duration(milliseconds: 1700));
      expect(find.byKey(const ValueKey('dm-highlight')), findsNothing);
    });
  });

  group('DmThreadView emoji autocomplete', () {
    late _FakeLiveKit fakeLiveKit;
    late ChatService chatService;

    setUp(() {
      fakeLiveKit = _FakeLiveKit();
      chatService = ChatService(liveKitService: fakeLiveKit);
      chatService.setBotStatusForTest(BotStatus.idle);
    });

    tearDown(() => chatService.dispose());

    Future<void> pumpThread(WidgetTester tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: DmThreadView(
            conversation: Conversation(
              id: Conversation.conversationIdFor('me', 'peer'),
              type: ConversationType.dm,
              peerId: 'peer',
              peerDisplayName: 'Peer',
            ),
            chatService: chatService,
            onBack: () {},
          ),
        ),
      ));
      await tester.pumpAndSettle();
    }

    testWidgets('typing :fi opens the picker; tapping inserts the glyph',
        (tester) async {
      await pumpThread(tester);

      await tester.enterText(find.byType(TextField), ':fi');
      await tester.pump();

      expect(find.text(':fire:'), findsOneWidget);

      await tester.tap(find.text(':fire:'));
      await tester.pumpAndSettle();

      expect(find.widgetWithText(TextField, '🔥'), findsOneWidget);
      expect(find.text(':fire:'), findsNothing);
    });
  });
}

List<int> _utf8Json(Map<String, dynamic> map) => utf8.encode(jsonEncode(map));
