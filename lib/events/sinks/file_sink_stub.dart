import 'package:tech_world/events/types.dart';

/// Web stub for file sink — no filesystem available on web.
///
/// Returns a no-op so that platform-conditional registration compiles
/// cleanly on all platforms.
Future<void Function(AppEvent)> createFileSink() async {
  return (_) {};
}

/// Web stub — AV pipeline sink is a no-op on web.
Future<void Function(AppEvent)> createAvPipelineSink({
  required bool Function() enabledCheck,
}) async {
  return (_) {};
}

/// Web stub — error sink is a no-op on web.
Future<void Function(AppEvent)> createErrorSink({
  required bool Function() enabledCheck,
}) async {
  return (_) {};
}
