import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';
import 'package:tech_world/events/logger_bridge_init.dart';
import 'package:tech_world/events/types.dart';

/// Wiring-level test for [initLoggerBridge].
///
/// The pure mapping function `mapLogRecord` is unit-tested in
/// `logger_bridge_test.dart`. This test covers the *wiring*: the
/// `listen` subscription on the supplied logger, the FINE-level
/// filter behaviour in-situ, and the dispatch fan-out.
///
/// DI seams:
///   * `logger:` — inject a non-root [Logger] so tests don't fight
///     the global `Logger.root` state.
///   * `dispatchFn:` — inject a capture function so we can assert
///     on what would have reached the event pipeline.
void main() {
  group('initLoggerBridge', () {
    late Logger testLogger;
    late List<AppEvent> captured;
    late void Function() teardownFn;

    setUp(() {
      // Use a hierarchical-disabled child logger so emissions don't
      // leak to Logger.root and our test runner.
      hierarchicalLoggingEnabled = true;
      testLogger = Logger.detached('LoggerBridgeInitTest')
        ..level = Level.ALL;
      captured = [];
      teardownFn = initLoggerBridge(
        logger: testLogger,
        dispatchFn: (events) => captured.addAll(events),
      );
    });

    tearDown(() {
      teardownFn();
    });

    test('dispatches INFO records as AppLogRecord(severity: info)', () {
      testLogger.info('hello info');

      expect(captured, hasLength(1));
      final record = captured.single;
      expect(record, isA<AppLogRecord>());
      final logRecord = record as AppLogRecord;
      expect(logRecord.severity, LogSeverity.info);
      expect(logRecord.message, 'hello info');
    });

    test('dispatches WARNING records as AppLogRecord(severity: warning)', () {
      testLogger.warning('careful');

      expect(captured, hasLength(1));
      expect((captured.single as AppLogRecord).severity, LogSeverity.warning);
    });

    test('dispatches SEVERE records as AppLogRecord(severity: severe)', () {
      testLogger.severe('boom');

      expect(captured, hasLength(1));
      expect((captured.single as AppLogRecord).severity, LogSeverity.severe);
    });

    test('drops FINE records — filter applies in the wiring', () {
      testLogger.fine('raw stt transcript with PII');

      expect(captured, isEmpty,
          reason: 'FINE-level records must be dropped before dispatch');
    });

    test('drops FINER and FINEST records too', () {
      testLogger.finer('tracing');
      testLogger.finest('verbose');

      expect(captured, isEmpty);
    });

    test('teardown cancels the subscription — no further dispatches', () {
      teardownFn();
      // Make tearDown a no-op since we already cancelled.
      teardownFn = () {};

      testLogger.info('after teardown');

      expect(captured, isEmpty);
    });
  });
}
