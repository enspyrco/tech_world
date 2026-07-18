import 'package:flutter_test/flutter_test.dart';
import 'package:tech_world/livekit/livekit_service.dart';

/// Tests for the local mic/camera mute state notifiers ([micEnabled] /
/// [cameraEnabled]) that drive the mute toolbar buttons.
///
/// The notifiers must only reflect state AFTER a toggle actually lands on the
/// live `LocalParticipant`. Without a room, [setMicrophoneEnabled] /
/// [setCameraEnabled] return early — so the notifier must stay `false` rather
/// than optimistically flip, otherwise the toolbar would show "live" while
/// nothing is being published.
void main() {
  group('local media mute notifiers', () {
    late LiveKitService service;

    setUp(() {
      service = LiveKitService(userId: 'user-1', displayName: 'User 1');
    });

    tearDown(() async {
      await service.dispose();
    });

    test('mic + camera enabled default to false (nothing published yet)', () {
      expect(service.micEnabled.value, isFalse);
      expect(service.cameraEnabled.value, isFalse);
    });

    test('setMicrophoneEnabled with no room does not flip the notifier',
        () async {
      await service.setMicrophoneEnabled(true);
      expect(service.micEnabled.value, isFalse);
    });

    test('setCameraEnabled with no room does not flip the notifier', () async {
      await service.setCameraEnabled(true);
      expect(service.cameraEnabled.value, isFalse);
    });
  });
}
