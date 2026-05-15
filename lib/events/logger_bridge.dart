import 'package:logging/logging.dart';
import 'package:tech_world/events/types.dart';

/// Maps a `package:logging` [LogRecord] to an [AppLogRecord] for dispatch
/// through the event-sink pipeline, OR returns `null` when the record
/// should be dropped entirely.
///
/// ## Defensive level filter
///
/// Records below [Level.INFO] (FINE / FINER / FINEST / CONFIG) are
/// dropped here, BEFORE any [AppLogRecord] is constructed and dispatched.
///
/// Why a second filter when `Logger.root.level = Level.INFO` already
/// gates the stream? Two reasons:
///
/// 1. **PII safety.** FINE-level call sites carry raw player speech —
///    `stt_service_web.dart` logs raw STT transcripts at FINE, and
///    `oracle_service.dart` logs oracle replies at FINE. These strings
///    are PII. The `AppEvent.containsPii` gate (PR #459) keeps them
///    out of remote sinks, but local file sinks (`file_sink.dart`)
///    still write everything they receive to `events.log` on disk.
/// 2. **Belt-and-braces.** A future maintainer setting
///    `Logger.root.level = Level.ALL` (debugging, a misconfigured
///    test harness, an environment toggle) would silently re-introduce
///    the regression Carnot caught in the PR #436 cage-match. The
///    bridge MUST agree with the root logger; we don't rely on a
///    distant configuration line.
///
/// Returning `null` is the explicit "drop this record" signal — the
/// caller must check before dispatching.
AppLogRecord? mapLogRecord(LogRecord record) {
  if (record.level < Level.INFO) return null;

  final severity = switch (record.level) {
    Level.SEVERE || Level.SHOUT => LogSeverity.severe,
    Level.WARNING => LogSeverity.warning,
    _ => LogSeverity.info,
  };

  return AppLogRecord(
    loggerName: record.loggerName,
    severity: severity,
    message: record.message,
    error: record.error?.toString(),
    stackTrace: record.stackTrace?.toString(),
    timestamp: record.time,
  );
}
