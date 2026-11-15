import 'dart:convert';

import 'package:flutter/foundation.dart';

/// Protocol version stamped on every outgoing JSON data-channel message.
/// Bump when a wire-format change requires receivers to upgrade.
const kProtocolVersion = 1;

/// A message received on the LiveKit data channel.
class DataChannelMessage {
  DataChannelMessage({
    required this.senderId,
    required this.topic,
    required this.data,
  });

  /// Transport-verified identity of the sender, or null if sent from the
  /// server API. A peer cannot forge this; it can forge anything in [data].
  final String? senderId;

  /// Optional topic categorizing the message.
  final String? topic;

  /// Raw bytes of the message payload.
  final List<int> data;

  /// Decode data as UTF-8 JSON.
  Map<String, dynamic>? get json {
    try {
      return jsonDecode(utf8.decode(data)) as Map<String, dynamic>;
    } catch (e) {
      final preview = utf8.decode(data, allowMalformed: true);
      debugPrint(
        'DataChannelMessage: JSON parse failed '
        '(topic: $topic, error: $e, '
        'data: ${preview.length > 200 ? preview.substring(0, 200) : preview})',
      );
      return null;
    }
  }

  /// Decode data as UTF-8 string.
  String get text => utf8.decode(data);

  @override
  String toString() =>
      'DataChannelMessage(senderId: $senderId, topic: $topic, data: ${data.length} bytes)';
}

/// A data-channel topic, identified on the wire by [wireName].
abstract interface class Topic {
  String get wireName;
}

/// How one kind of outgoing message becomes bytes.
abstract interface class TopicEncoder<T> implements Topic {
  bool get reliable;
  List<int> encode(T value);
}

/// How one kind of incoming message is read back.
///
/// Takes the whole [DataChannelMessage], not just its JSON, so a decoder can
/// attribute a message to its transport-verified [DataChannelMessage.senderId]
/// and can read non-JSON payloads. Return null to drop the message.
abstract interface class TopicDecoder<T> implements Topic {
  T? decode(DataChannelMessage message);
}

/// A topic whose sent and received values have the same shape.
abstract interface class TopicCodec<T>
    implements TopicEncoder<T>, TopicDecoder<T> {}

/// Encodes a JSON map, stamped with [kProtocolVersion] under `'v'`.
mixin JsonEncoding<T> implements TopicEncoder<T> {
  Map<String, dynamic> toJson(T value);

  @override
  List<int> encode(T value) =>
      utf8.encode(jsonEncode({'v': kProtocolVersion, ...toJson(value)}));
}

/// Messages in [source] on [topic], decoded; rejected messages are dropped.
///
/// A decoder that throws is caught per message and reported to [onError].
/// Without the catch a `listen` subscription would survive (it only cancels on
/// error when asked to; an `await for` loop would end), but every malformed
/// packet would reach the zone as an uncaught error, so one hostile peer could flood the crash reporter, and the
/// report would not say which topic. [TopicDecoder] is an open interface, so
/// this is the one place a decoder we didn't write is contained.
Stream<T> decodeTopic<T>(
  Stream<DataChannelMessage> source,
  TopicDecoder<T> topic, {
  void Function(Object error, StackTrace stack)? onError,
}) =>
    source.where((msg) => msg.topic == topic.wireName).expand((msg) {
      try {
        final value = topic.decode(msg);
        return value == null ? <T>[] : <T>[value];
      } catch (e, st) {
        onError?.call(e, st);
        return <T>[];
      }
    });

/// Decodes a JSON map, dropping messages whose payload isn't a JSON object.
mixin JsonDecoding<T> implements TopicDecoder<T> {
  T? fromJson(Map<String, dynamic> json, DataChannelMessage message);

  @override
  T? decode(DataChannelMessage message) {
    final json = message.json;
    return json == null ? null : fromJson(json, message);
  }
}
