@TestOn('vm')
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tech_world/events/sinks/rotating_file_sink.dart';
import 'package:tech_world/events/types.dart';

/// Reuses the sealed `AppLogRecord` with the `message` field as a
/// sequence-number carrier — `AppEvent` is sealed and can't be extended
/// from outside its library.
AppEvent _seq(int n) => AppLogRecord(
      loggerName: 'test',
      severity: LogSeverity.info,
      message: 'seq:$n',
    );

Future<List<int>> _readSeqs(File file) async {
  if (!file.existsSync()) return const <int>[];
  final lines = await file.readAsLines();
  return lines
      .map((l) => jsonDecode(l)['message'] as String)
      .map((m) => int.parse(m.substring('seq:'.length)))
      .toList();
}

void main() {
  late Directory tmp;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('rotating_sink_test_');
  });

  tearDown(() async {
    if (tmp.existsSync()) await tmp.delete(recursive: true);
  });

  group('RotatingFileSink', () {
    test(
        'writes are flushed in submission order — no records dropped or interleaved',
        () async {
      final sink = RotatingFileSink(
        logFile: File('${tmp.path}/events.log'),
        // Large enough that no rotation triggers in this test.
        maxBytes: 10 * 1024 * 1024,
        checkInterval: 50,
      );

      for (var i = 0; i < 200; i++) {
        sink(_seq(i));
      }
      await sink.flushed();

      final seqs = await _readSeqs(File('${tmp.path}/events.log'));
      expect(seqs.length, 200);
      // Strict in-order — would catch any write-skew under the rotation race.
      expect(seqs, equals(List<int>.generate(200, (i) => i)));
    });

    test(
        'rotation preserves order: every line in .N predates every line in .{N-1}',
        () async {
      // Small maxBytes so rotation triggers within the test. Each line is
      // `{"seq":N}\n` ≈ 12-15 bytes; 256 bytes guarantees several rotations.
      final sink = RotatingFileSink(
        logFile: File('${tmp.path}/events.log'),
        maxBytes: 256,
        maxRotations: 3,
        checkInterval: 5,
      );

      for (var i = 0; i < 200; i++) {
        sink(_seq(i));
      }
      await sink.flushed();

      // Collect every persisted seq across current + rotation files.
      // Rotation discards the oldest generation by design once we exceed
      // `maxRotations`; we expect a contiguous *tail* of the input, not all 200.
      final allSeqs = <int>[];
      for (final candidate in [
        File('${tmp.path}/events.log.3'),
        File('${tmp.path}/events.log.2'),
        File('${tmp.path}/events.log.1'),
        File('${tmp.path}/events.log'),
      ]) {
        allSeqs.addAll(await _readSeqs(candidate));
      }
      // What survives must be a contiguous suffix of the input — no gaps,
      // strictly increasing, ending at 199. Gaps would indicate writes
      // landing in a rotated-out file or being lost mid-rotation.
      expect(allSeqs, isNotEmpty);
      expect(allSeqs.last, 199, reason: 'Most recent write reaches current');
      for (var i = 1; i < allSeqs.length; i++) {
        expect(allSeqs[i], allSeqs[i - 1] + 1,
            reason: 'Persisted seqs must be contiguous; gap at index $i');
      }

      // Ordering: max(seq in .K) < min(seq in .{K-1}) for K in 1..maxRotations.
      // Older generations have older sequence numbers.
      Future<List<int>> seqs(String suffix) =>
          _readSeqs(File('${tmp.path}/events.log$suffix'));
      final current = await seqs('');
      final r1 = await seqs('.1');
      final r2 = await seqs('.2');
      final r3 = await seqs('.3');

      if (r3.isNotEmpty && r2.isNotEmpty) {
        expect(r3.last, lessThan(r2.first),
            reason: '.3 must predate .2 entirely');
      }
      if (r2.isNotEmpty && r1.isNotEmpty) {
        expect(r2.last, lessThan(r1.first),
            reason: '.2 must predate .1 entirely');
      }
      if (r1.isNotEmpty && current.isNotEmpty) {
        expect(r1.last, lessThan(current.first),
            reason: '.1 must predate current entirely');
      }
    });

    test('no truncated lines at rotation boundaries', () async {
      final sink = RotatingFileSink(
        logFile: File('${tmp.path}/events.log'),
        maxBytes: 256,
        maxRotations: 3,
        checkInterval: 5,
      );
      for (var i = 0; i < 100; i++) {
        sink(_seq(i));
      }
      await sink.flushed();

      for (final candidate in [
        File('${tmp.path}/events.log'),
        File('${tmp.path}/events.log.1'),
        File('${tmp.path}/events.log.2'),
        File('${tmp.path}/events.log.3'),
      ]) {
        if (!candidate.existsSync()) continue;
        final lines = await candidate.readAsLines();
        for (final line in lines) {
          // Every line must be valid JSON terminated by `}`.
          expect(() => jsonDecode(line), returnsNormally,
              reason: 'Truncated/malformed line in ${candidate.path}: $line');
        }
      }
    });

    test('enabledCheck false → no writes', () async {
      final sink = RotatingFileSink(
        logFile: File('${tmp.path}/events.log'),
        enabledCheck: () => false,
      );
      for (var i = 0; i < 10; i++) {
        sink(_seq(i));
      }
      await sink.flushed();
      expect(File('${tmp.path}/events.log').existsSync(), isFalse);
    });

    test(
        'backpressure: pending stays bounded when writes are slow; '
        'excess events dropped and summarized once', () async {
      // A blocked writer — every write awaits a Completer we control.
      // Until we release the gate, all enqueued writes pile up on `_chain`.
      var gate = Completer<void>();
      var writeAttempts = 0;
      Future<void> blockedWriter(String line) async {
        writeAttempts++;
        await gate.future;
      }

      const threshold = 50;
      final sink = RotatingFileSink(
        logFile: File('${tmp.path}/events.log'),
        maxPending: threshold,
        writer: blockedWriter,
      );

      // Enqueue many more than the threshold while I/O is stalled.
      const enqueued = 500;
      for (var i = 0; i < enqueued; i++) {
        sink(_seq(i));
      }

      // Yield once so the chain has a chance to schedule its first
      // continuation (it would block on `gate.future` immediately).
      await Future<void>.delayed(Duration.zero);

      // Pending must stay at or below the threshold; the rest dropped.
      expect(sink.pending, lessThanOrEqualTo(threshold),
          reason: 'in-flight writes must be bounded by maxPending');
      expect(sink.droppedSinceLastReport, equals(enqueued - threshold),
          reason:
              'every enqueue beyond the threshold should increment the drop counter');

      // Release the gate so queued writes resolve, then drain.
      gate.complete();
      await sink.flushed();

      // After full drain: pending back to zero, the summary fired (counter reset).
      expect(sink.pending, equals(0));
      expect(sink.droppedSinceLastReport, equals(0),
          reason: 'breach summary should reset the drop counter on drain');
      // Sanity: only `threshold` writes ever reached the writer — the rest
      // were dropped at the gate.
      expect(writeAttempts, equals(threshold));
    });

    test('filter excludes non-matching events', () async {
      final sink = RotatingFileSink(
        logFile: File('${tmp.path}/events.log'),
        filter: (e) => e is AppLogRecord && int.parse(e.message.substring(4)).isEven,
      );
      for (var i = 0; i < 10; i++) {
        sink(_seq(i));
      }
      await sink.flushed();
      final seqs = await _readSeqs(File('${tmp.path}/events.log'));
      expect(seqs, equals([0, 2, 4, 6, 8]));
    });
  });
}
