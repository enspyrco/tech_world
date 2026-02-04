// Stub implementation of STT service for non-web platforms.

import 'package:flutter/foundation.dart' show ValueNotifier;

/// Stub STT service that does nothing.
class SttService {
  bool get isSupported => false;
  final ValueNotifier<bool> listening = ValueNotifier(false);

  Future<String?> listen() async => null;
  void stop() {}
  void dispose() {
    listening.dispose();
  }
}
