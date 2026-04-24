// Stub implementation for non-web platforms.

import '../native/frame_source.dart';
import 'livekit_service.dart';

/// No-op bridge on non-web platforms. The 3D avatar requires a browser.
class DreamfinderAvatarBridge {
  DreamfinderAvatarBridge({required LiveKitService liveKitService});

  /// Always null on non-web platforms.
  FrameSource? get canvasCapture => null;

  /// Always false.
  bool get isReady => false;

  /// Always null.
  int? get avatarLoadProgress => null;

  /// No-op.
  Future<void> initialize() async {}

  /// No-op.
  void dispose() {}
}
