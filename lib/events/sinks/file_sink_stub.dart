import 'package:tech_world/events/types.dart';

/// Web stub for file sink — no filesystem available on web.
///
/// Returns a no-op so that platform-conditional registration compiles
/// cleanly on all platforms.
Future<void Function(AppEvent)> createFileSink() async {
  return (_) {};
}
