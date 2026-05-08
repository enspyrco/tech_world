import 'package:tech_world/events/types.dart';

typedef Sink = void Function(AppEvent event);
typedef AsyncSink = Future<void> Function(AppEvent event);

final List<Sink> _syncSinks = [];
final List<AsyncSink> _asyncSinks = [];

/// Register a synchronous sink. Called once at app startup or in tests.
void registerSink(Sink sink) => _syncSinks.add(sink);

/// Register an asynchronous sink. Called once at app startup or in tests.
void registerAsyncSink(AsyncSink sink) => _asyncSinks.add(sink);

/// Fan [events] to all registered sinks. Synchronous sinks run first,
/// then async sinks in registration order.
///
/// Safe to call with an empty list or when no sinks are registered.
Future<void> dispatch(List<AppEvent> events) async {
  for (final event in events) {
    for (final sink in _syncSinks) {
      sink(event);
    }
    for (final sink in _asyncSinks) {
      await sink(event);
    }
  }
}

/// Remove all registered sinks. Intended for test teardown only.
void clearSinks() {
  _syncSinks.clear();
  _asyncSinks.clear();
}
