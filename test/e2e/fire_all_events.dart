/// Fire all 34 event types and print each as JSONL to stdout.
///
/// Run with: flutter test test/e2e/fire_all_events.dart
///
/// This is both a smoke test and a CLI — it verifies every event type
/// serializes correctly and outputs the JSONL that would appear in
/// events.log. Pipe to jq for pretty-printing:
///
///   flutter test test/e2e/fire_all_events.dart 2>/dev/null | grep '^{' | jq .
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:tech_world/events/dispatch.dart';
import 'package:tech_world/events/types.dart';

import 'event_pipeline_test.dart' show allSampleEvents;

void main() {
  test('fire all 34 events and print JSONL', () {
    final captured = <AppEvent>[];
    registerSink(captured.add);

    dispatch(allSampleEvents());

    // Print each event as a JSONL line — this is the CLI output.
    for (final event in captured) {
      // ignore: avoid_print
      print(jsonEncode(event.toJson()));
    }

    expect(captured.length, 34);
    clearSinks();
  });
}
