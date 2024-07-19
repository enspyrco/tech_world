import 'package:web_socket_channel/web_socket_channel.dart';

class FakeWebSocketSink implements WebSocketSink {
  FakeWebSocketSink(this._sink);

  final Sink _sink;

  @override
  void add(data) {
    _sink.add(data);
  }

  @override
  void addError(Object error, [StackTrace? stackTrace]) {}

  @override
  Future addStream(Stream stream) {
    throw UnimplementedError();
  }

  @override
  Future close([int? closeCode, String? closeReason]) {
    throw UnimplementedError();
  }

  @override
  Future get done => throw UnimplementedError();
}
