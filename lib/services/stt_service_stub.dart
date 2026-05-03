// Stub implementation of STT service for non-web platforms.

import 'package:flutter/foundation.dart' show ValueNotifier;
import 'package:tech_world/services/stt_result.dart';

export 'package:tech_world/services/stt_result.dart' show SttResult;

/// Stub STT service that does nothing.
class SttService {
  bool get isSupported => false;
  final ValueNotifier<bool> listening = ValueNotifier(false);

  Future<SttResult> listen() async => const SttResult.empty();
  void stop() {}
  void dispose() {
    listening.dispose();
  }
}
