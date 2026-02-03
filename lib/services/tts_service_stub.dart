// Stub implementation of TTS service for non-web platforms.
//
// This is a no-op implementation used when running on platforms
// that don't support browser speechSynthesis.

/// Stub TTS service that does nothing.
class TtsService {
  bool get isReady => false;

  Future<void> speak(String text) async {
    // No-op on non-web platforms
  }

  void stop() {}
  void setRate(double rate) {}
  void setPitch(double pitch) {}
  void dispose() {}
}
