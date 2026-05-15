import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';
import 'package:tech_world/events/dispatch.dart';
import 'package:tech_world/events/logger_bridge.dart';
import 'package:tech_world/events/types.dart';

/// Defensive level filter at the Logger→AppLogRecord bridge.
///
/// FINE-level records carry raw STT transcripts (`stt_service_web.dart`)
/// and oracle replies (`oracle_service.dart`) — strings that contain
/// player PII. `main.dart` sets `Logger.root.level = Level.INFO` so FINE
/// records are dropped before reaching the bridge in practice. But the
/// implicit level is a configuration claim, not a guarantee: a future
/// `Logger.root.level = Level.ALL` (or a misconfigured test harness)
/// would silently re-introduce the regression.
///
/// The bridge MUST drop anything below `Level.INFO` itself. Belt-and-
/// braces — the level on the root logger AND the bridge agree.
void main() {
  group('mapLogRecord (level filter)', () {
    test('returns null for FINE — never reaches AppLogRecord', () {
      final record = LogRecord(Level.FINE, 'raw stt transcript', 'STT');
      expect(mapLogRecord(record), isNull);
    });

    test('returns null for FINER', () {
      final record = LogRecord(Level.FINER, 'tracing', 'X');
      expect(mapLogRecord(record), isNull);
    });

    test('returns null for FINEST', () {
      final record = LogRecord(Level.FINEST, 'tracing', 'X');
      expect(mapLogRecord(record), isNull);
    });

    test('returns null for CONFIG (still < INFO)', () {
      final record = LogRecord(Level.CONFIG, 'config', 'X');
      expect(mapLogRecord(record), isNull);
    });

    test('returns AppLogRecord(info) for INFO', () {
      final record = LogRecord(Level.INFO, 'operational', 'X');
      final mapped = mapLogRecord(record);
      expect(mapped, isNotNull);
      expect(mapped!.severity, LogSeverity.info);
      expect(mapped.message, 'operational');
      expect(mapped.loggerName, 'X');
    });

    test('returns AppLogRecord(warning) for WARNING', () {
      final record = LogRecord(Level.WARNING, 'recoverable', 'X');
      expect(mapLogRecord(record)!.severity, LogSeverity.warning);
    });

    test('returns AppLogRecord(severe) for SEVERE', () {
      final record = LogRecord(Level.SEVERE, 'error', 'X');
      expect(mapLogRecord(record)!.severity, LogSeverity.severe);
    });

    test('returns AppLogRecord(severe) for SHOUT', () {
      final record = LogRecord(Level.SHOUT, 'fatal', 'X');
      expect(mapLogRecord(record)!.severity, LogSeverity.severe);
    });
  });

  group('mapLogRecord + dispatch integration', () {
    setUp(clearSinks);
    tearDown(clearSinks);

    test('FINE record routed through bridge dispatches NO event to sinks', () {
      final received = <AppEvent>[];
      registerSink(received.add);

      final record = LogRecord(Level.FINE, 'raw stt: hello world', 'STT');
      final mapped = mapLogRecord(record);
      if (mapped != null) dispatch([mapped]);

      expect(received, isEmpty, reason: 'FINE must never reach any sink');
    });

    test('INFO record routed through bridge dispatches to sinks', () {
      final received = <AppEvent>[];
      registerSink(received.add);

      final record = LogRecord(Level.INFO, 'connected', 'LiveKit');
      final mapped = mapLogRecord(record);
      if (mapped != null) dispatch([mapped]);

      expect(received, hasLength(1));
      expect(received.single, isA<AppLogRecord>());
    });
  });
}
