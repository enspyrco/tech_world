import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:tech_world/events/sinks/rotating_file_sink.dart';
import 'package:tech_world/events/types.dart';

/// Directory shared by all JSONL sinks. Created once, reused by
/// [createFileSink], [createAvPipelineSink], and [createErrorSink].
Future<Directory> logDirectory() async {
  final appDir = await getApplicationDocumentsDirectory();
  final logDir = Directory('${appDir.path}/tech_world_logs');
  await logDir.create(recursive: true);
  return logDir;
}

/// Creates the general-purpose JSONL event sink (all events).
///
/// **Not available on web** — use conditional import with
/// `file_sink_stub.dart`.
Future<void Function(AppEvent)> createFileSink() async {
  final logDir = await logDirectory();
  final sink = RotatingFileSink(logFile: File('${logDir.path}/events.log'));
  return sink.call;
}

/// Creates the AV pipeline diagnostic sink (Av* events only).
///
/// Writes to `av-pipeline.jsonl`. The [enabledCheck] callback is evaluated
/// on every event so the toggle can be flipped at runtime without restart.
Future<void Function(AppEvent)> createAvPipelineSink({
  required bool Function() enabledCheck,
}) async {
  final logDir = await logDirectory();
  final sink = RotatingFileSink(
    logFile: File('${logDir.path}/av-pipeline.jsonl'),
    filter: _isAvEvent,
    enabledCheck: enabledCheck,
  );
  return sink.call;
}

/// Creates the error sink (warning-or-above severity events).
///
/// Writes to `errors.jsonl`. AV errors also land here (duplicated with
/// the AV pipeline sink) — that's intentional for the "something's broken,
/// not sure what" reading mode.
Future<void Function(AppEvent)> createErrorSink({
  required bool Function() enabledCheck,
}) async {
  final logDir = await logDirectory();
  final sink = RotatingFileSink(
    logFile: File('${logDir.path}/errors.jsonl'),
    filter: _isErrorEvent,
    enabledCheck: enabledCheck,
  );
  return sink.call;
}

bool _isAvEvent(AppEvent event) => switch (event) {
      AvPipelineSnapshot() => true,
      AvTrackSubscribed() => true,
      AvTrackUnsubscribed() => true,
      AvCaptureInitialized() => true,
      AvCaptureInitFailed() => true,
      AvBubbleCreated() => true,
      AvBubbleRemoved() => true,
      AvAudioGateChanged() => true,
      AvFrameDecodeError() => true,
      AvSpeakingChanged() => true,
      _ => false,
    };

bool _isErrorEvent(AppEvent event) => switch (event) {
      // AV errors (always included in error log)
      AvCaptureInitFailed() => true,
      AvFrameDecodeError() => true,
      // Log bridge records at warning or above
      AppLogRecord(:final severity) => switch (severity) {
          LogSeverity.warning => true,
          LogSeverity.severe => true,
          LogSeverity.info => false,
        },
      // LiveKit disconnect is operationally significant
      LiveKitDisconnected() => true,
      _ => false,
    };
