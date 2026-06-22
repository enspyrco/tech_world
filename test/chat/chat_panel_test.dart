import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:livekit_client/livekit_client.dart' show RemoteParticipant;
import 'package:tech_world/chat/chat_panel.dart';
import 'package:tech_world/chat/chat_service.dart';
import 'package:tech_world/flame/components/bot_status.dart';
import 'package:tech_world/livekit/livekit_service.dart';

/// Minimal LiveKitService fake for driving [ChatPanel] under test.
class _FakeLiveKit implements LiveKitService {
  final _data = StreamController<DataChannelMessage>.broadcast();
  final _joined = StreamController<RemoteParticipant>.broadcast();
  final _left = StreamController<RemoteParticipant>.broadcast();

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
  group('ChatPanel group quote-reply', () {
    late _FakeLiveKit fakeLiveKit;
    late ChatService chatService;

    setUp(() {
      fakeLiveKit = _FakeLiveKit();
      chatService = ChatService(liveKitService: fakeLiveKit);
      chatService.setBotStatusForTest(BotStatus.idle);
    });

    tearDown(() => chatService.dispose());

    Future<void> pumpPanel(WidgetTester tester) async {
      // Seed an inbound GROUP message from another user so the Group tab has a
      // message to reply to. (From another user, so it isn't skipped as a
      // self-echo.)
      fakeLiveKit._data.add(DataChannelMessage(
        senderId: 'peer',
        topic: 'chat',
        data: _utf8Json({
          'text': 'Original question',
          'id': 'group-1',
          'senderName': 'Peer',
        }),
      ));
      await tester.pump();

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          // Tall enough that the group ListView builds every row (a short
          // viewport clips off-screen items, so off-screen text isn't found).
          body: SizedBox(
            height: 1200,
            child: ChatPanel(
              chatService: chatService,
              liveKitService: fakeLiveKit,
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();
    }

    testWidgets('tapping Reply shows the composing banner', (tester) async {
      await pumpPanel(tester);

      // The group tab shows the inbound message + a Reply affordance.
      expect(find.text('Original question'), findsOneWidget);
      expect(find.text('Reply'), findsWidgets);

      await tester.tap(find.text('Reply').first);
      await tester.pumpAndSettle();

      // Composing banner appears.
      expect(find.text('Replying to Peer'), findsOneWidget);
    });

    testWidgets('sending a reply publishes reply fields on the wire',
        (tester) async {
      await pumpPanel(tester);

      await tester.tap(find.text('Reply').first);
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'I agree');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      // Note: group sendMessage opens a 30s response-timeout timer, so we
      // pump a fixed duration rather than pumpAndSettle (which would flag the
      // pending timer). The publish + setState we assert on happen synchronously
      // before the await on the completer.
      await tester.pump();

      // The group publish carries the reply fields derived from the quoted msg.
      final groupPublish = fakeLiveKit.published.lastWhere(
        (p) => (p['payload'] as Map)['text'] == 'I agree',
      );
      final payload = groupPublish['payload'] as Map<String, dynamic>;
      expect(payload['replyToText'], equals('Original question'));
      expect(payload['replyToSenderName'], equals('Peer'));
      expect(payload['replyToMessageId'], isNotNull);

      // Banner is dismissed after sending.
      expect(find.text('Replying to Peer'), findsNothing);

      // Let the pending response-timeout fire so no timer leaks past the test.
      await tester.pump(const Duration(seconds: 31));
    });

    testWidgets('cancel button dismisses the composing banner',
        (tester) async {
      await pumpPanel(tester);

      await tester.tap(find.text('Reply').first);
      await tester.pumpAndSettle();
      expect(find.text('Replying to Peer'), findsOneWidget);

      await tester.tap(find.byTooltip('Cancel reply'));
      await tester.pumpAndSettle();
      expect(find.text('Replying to Peer'), findsNothing);
    });

    testWidgets('an inbound group reply renders its quoted snippet',
        (tester) async {
      // Seed BOTH the original message and an inbound reply that quotes it
      // BEFORE mounting, so the StreamBuilder renders them from initialData /
      // currentMessages. (A broadcast stream doesn't buffer, so emitting after
      // mount races the StreamBuilder's subscription in widget-test timing.)
      fakeLiveKit._data.add(DataChannelMessage(
        senderId: 'peer',
        topic: 'chat',
        data: _utf8Json({
          'text': 'Original question',
          'id': 'group-1',
          'senderName': 'Peer',
        }),
      ));
      fakeLiveKit._data.add(DataChannelMessage(
        senderId: 'peer2',
        topic: 'chat',
        data: _utf8Json({
          'text': 'Here is my answer',
          'id': 'group-2',
          'senderName': 'Peer Two',
          'replyToMessageId': 'peer:123',
          'replyToText': 'Original question',
          'replyToSenderName': 'Peer',
        }),
      ));
      await tester.pump();

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SizedBox(
            height: 1200,
            child: ChatPanel(
              chatService: chatService,
              liveKitService: fakeLiveKit,
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();

      // The reply bubble shows its own text.
      expect(find.text('Here is my answer'), findsOneWidget);
      // The quoted snippet re-renders the original text, so 'Original question'
      // appears twice: as the standalone first message AND inside the quote
      // above the reply. (One occurrence would mean the quote didn't render.)
      expect(find.text('Original question'), findsNWidgets(2));
    });
  });
}

List<int> _utf8Json(Map<String, dynamic> map) => utf8.encode(jsonEncode(map));
