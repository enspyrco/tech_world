import 'dart:async' show unawaited;

import 'package:tech_world/events/types.dart';

typedef Sink = void Function(AppEvent event);
typedef AsyncSink = Future<void> Function(AppEvent event);

final List<Sink> _syncSinks = [];
final List<AsyncSink> _asyncSinks = [];

/// Register a synchronous sink. Called once at app startup or in tests.
void registerSink(Sink sink) => _syncSinks.add(sink);

/// Register an asynchronous sink. Called once at app startup or in tests.
void registerAsyncSink(AsyncSink sink) => _asyncSinks.add(sink);

/// Whether any sinks have been registered. Used to guard against
/// duplicate registration on hot restart.
bool get sinksRegistered => _syncSinks.isNotEmpty || _asyncSinks.isNotEmpty;

/// Fan [events] to all registered sinks. Synchronous sinks run first,
/// then async sinks in registration order.
///
/// Safe to call with an empty list or when no sinks are registered.
/// Safe to not await — all call sites are fire-and-forget.
///
/// Snapshots the sink lists before iterating so that a sink calling
/// [registerSink] or [clearSinks] during dispatch does not corrupt
/// the iteration.
void dispatch(List<AppEvent> events) {
  if (events.isEmpty) return;
  final syncs = List.of(_syncSinks);
  final asyncs = List.of(_asyncSinks);
  for (final event in events) {
    for (final sink in syncs) {
      sink(event);
    }
    for (final sink in asyncs) {
      unawaited(sink(event));
    }
  }
}

/// Remove all registered sinks. Intended for test teardown only.
void clearSinks() {
  _syncSinks.clear();
  _asyncSinks.clear();
}
