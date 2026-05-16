import 'dart:async';
import 'dart:developer' as developer;

import 'package:logging/logging.dart';
import 'package:tech_world/events/dispatch.dart' as default_dispatch;
import 'package:tech_world/events/logger_bridge.dart';
import 'package:tech_world/events/types.dart';

/// Wires a [Logger]'s `onRecord` stream to the event-sink pipeline via
/// the pure [mapLogRecord] function.
///
/// Production entrypoint: `main.dart` calls `initLoggerBridge()` once
/// at startup with no arguments — defaults bind to [Logger.root] and
/// the real [default_dispatch.dispatch].
///
/// Tests inject:
///   * `logger:` — a detached [Logger] to avoid mutating global state.
///   * `dispatchFn:` — a capture closure to assert on dispatched events.
///
/// Each record is *also* forwarded to [developer.log] so DevTools shows
/// everything (DevTools is local-only; no PII leaves the device through
/// this path). The [mapLogRecord] filter only applies to the dispatch
/// fan-out — see the `CLAUDE.md` note on `developer.log` bypassing the
/// bridge filter.
///
/// Returns a teardown closure that cancels the underlying
/// [StreamSubscription]. Callers that need to re-init (hot restart in
/// `main.dart`) should invoke the returned closure first. In production
/// `main.dart` manages this via a module-level [StreamSubscription]
/// field for hot-restart safety.
void Function() initLoggerBridge({
  Logger? logger,
  void Function(List<AppEvent>)? dispatchFn,
}) {
  final boundLogger = logger ?? Logger.root;
  final boundDispatch = dispatchFn ?? default_dispatch.dispatch;

  final subscription = boundLogger.onRecord.listen((record) {
    // DevTools / debug console (existing behaviour). Note: this path
    // is NOT filtered — see CLAUDE.md "`developer.log` bypasses the
    // logger bridge".
    developer.log(
      record.message,
      time: record.time,
      level: record.level.value,
      name: record.loggerName,
      error: record.error,
      stackTrace: record.stackTrace,
    );

    // Bridge to event-sink pipeline. [mapLogRecord] is the PII gate —
    // FINE-level records (raw STT transcripts, oracle replies) return
    // null and are dropped before any [AppLogRecord] is constructed.
    final appRecord = mapLogRecord(record);
    if (appRecord != null) boundDispatch([appRecord]);
  });

  return () {
    subscription.cancel();
  };
}
