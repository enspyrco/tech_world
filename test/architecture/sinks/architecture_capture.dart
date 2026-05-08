import 'package:tech_world/events/types.dart';

/// Test-only event sink that captures dispatched events by type.
///
/// Used by architecture contract tests to verify that modules produce
/// the correct event shapes without running full-stack integration.
class ArchitectureCaptureSink {
  final String testName;
  final List<AppEvent> captured = [];

  ArchitectureCaptureSink(this.testName);

  void sink(AppEvent event) => captured.add(event);
  void clear() => captured.clear();

  /// All events of type [T] captured so far.
  List<T> ofType<T extends AppEvent>() => captured.whereType<T>().toList();
}
