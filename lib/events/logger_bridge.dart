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
  // Below-INFO levels (FINEST 300, FINER 400, FINE 500, CONFIG 700)
  // are dropped entirely. The `if` is the load-bearing PII gate —
  // never weaken to `<=` or remove without re-running the cage-match.
  if (record.level < Level.INFO) return null;

  // [Level.OFF] (value 2000) is a *threshold* sentinel, never a real
  // record level — `logger.log(Level.OFF, msg)` is nonsensical and
  // shouldn't generate a sink event. Drop it explicitly so it doesn't
  // get swept into the `info` default below.
  if (record.level == Level.OFF) return null;

  // Above-INFO mapping: explicit arms only, no wildcard. INFO and
  // CONFIG-the-value-itself (700, dropped above) are NOT in the
  // pattern, so any future Level value added to package:logging would
  // be a compile error here — a deliberate choice. Adding the new
  // level would require explicit thought about which bucket it lands
  // in.
  final severity = switch (record.level) {
    Level.INFO => LogSeverity.info,
    Level.WARNING => LogSeverity.warning,
    Level.SEVERE || Level.SHOUT => LogSeverity.severe,
    _ => LogSeverity.info, // safety net for non-canonical Level values
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
