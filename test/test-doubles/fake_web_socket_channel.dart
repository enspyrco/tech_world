import 'dart:async';

import 'package:stream_channel/stream_channel.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'fake_web_socket_sink.dart';

class FakeWebSocketChannel extends StreamChannelMixin
    implements WebSocketChannel {
  FakeWebSocketChannel(this._stream, this._sink) {
    _fakeWebSocketSink = FakeWebSocketSink(_sink);
  }

  final Stream _stream;
  final Sink _sink;
  late FakeWebSocketSink _fakeWebSocketSink;

  @override
  int? get closeCode => throw UnimplementedError();

  @override
  String? get closeReason => throw UnimplementedError();

  @override
  String? get protocol => throw UnimplementedError();

  @override
  Future<void> get ready => throw UnimplementedError();

  @override
  WebSocketSink get sink => _fakeWebSocketSink;

  @override
  Stream get stream => _stream;
}
