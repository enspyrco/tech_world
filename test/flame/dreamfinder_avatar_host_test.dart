import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:tech_world/native/frame_source.dart';
import 'package:mocktail/mocktail.dart';
import 'package:tech_world/flame/dreamfinder_avatar_host.dart';
import 'package:tech_world/livekit/dreamfinder_avatar_bridge.dart';
import 'package:tech_world/livekit/livekit_service.dart';

class MockLiveKitService extends Mock implements LiveKitService {}

/// A bridge whose readiness and initialize() timing the test controls, so the
/// ready-path is reachable on native (the real native bridge is a stub that
/// reports isReady false forever).
class _FakeBridge implements DreamfinderAvatarBridge {
  _FakeBridge({this.readyWhenDone = true});

  final bool readyWhenDone;
  final _gate = Completer<void>();
  bool _ready = false;
  int disposeCount = 0;

  void completeInitialize() {
    _ready = readyWhenDone;
    if (!_gate.isCompleted) _gate.complete();
  }

  @override
  Future<void> initialize() => _gate.future;

  @override
  bool get isReady => _ready;

  @override
  FrameSource? get canvasCapture => null;

  @override
  int? get avatarLoadProgress => 42;

  @override
  void dispose() => disposeCount++;
}

void main() {
  // This lifecycle had no test at all: initDreamfinderBridge and
  // handleDreamfinderLeft have exactly one production caller each (TechWorld)
  // and were never driven from the suite.
  //
  // These run on the NATIVE stub, where the bridge is a no-op that reports
  // isReady == false. That still exercises everything the host itself owns —
  // the skip conditions, idempotency, and null-safe reads — because all of
  // that is the host's logic, not the bridge's. What it cannot cover is the
  // web bridge actually going ready; that needs a browser.

  late MockLiveKitService service;

  /// Counts how many times the host ASKED for the LiveKit service. The host
  /// reads it only when it is about to construct a bridge, so this is a
  /// usable proxy for "did it try to start one?" without test-only state on
  /// the class.
  late int serviceReads;

  DreamfinderAvatarHost build({
    bool mobileWeb = false,
    bool withService = true,
    void Function()? onReady,
    DreamfinderAvatarBridge Function(LiveKitService)? bridgeFactory,
  }) =>
      DreamfinderAvatarHost(
        bridgeFactory: bridgeFactory,
        liveKitService: () {
          serviceReads++;
          return withService ? service : null;
        },
        onReady: onReady ?? () {},
        isMobileWebOverride: mobileWeb,
      );

  setUp(() {
    service = MockLiveKitService();
    serviceReads = 0;
  });

  group('when a bridge is skipped', () {
    test('mobile web never even asks for the service', () {
      // The embodied WebGL avatar renders black on mobile browsers, so loading
      // the iframe would be pure cost for an invisible result.
      final host = build(mobileWeb: true)..start();

      expect(serviceReads, equals(0));
      expect(host.isReady, isFalse);
      expect(host.canvasCapture, isNull);
      expect(host.avatarLoadProgress, isNull);
    });

    test('no LiveKit service yet leaves the host startable later', () {
      final host = build(withService: false)..start();

      expect(serviceReads, equals(1), reason: 'it asked, and got nothing');
      expect(host.isReady, isFalse);

      // Crucially it must NOT have latched a half-built state: a later start
      // with a service present has to try again.
      serviceReads = 0;
      build().start();
      expect(serviceReads, equals(1));
    });
  });

  group('idempotency', () {
    test('repeated starts do not build a second bridge', () {
      // A Dreamfinder respawn calls this again. Spawning a second iframe
      // alongside the first would leak a WebGL context per respawn.
      final host = build()
        ..start()
        ..start()
        ..start();

      expect(serviceReads, equals(1));
      expect(host.isReady, isFalse); // native stub
    });

    test('stop then start builds a fresh bridge', () {
      final host = build()..start();
      expect(serviceReads, equals(1));

      host.stop();
      host.start();

      expect(serviceReads, equals(2),
          reason: 'stop must actually clear the slot, not just dispose');
    });

    test('stop is safe repeatedly and before any start', () {
      final host = build();
      expect(host.stop, returnsNormally);
      host.start();
      expect(host.stop, returnsNormally);
      expect(host.stop, returnsNormally);
    });
  });

  group('reads are null-safe with no bridge', () {
    test('every accessor answers without a bridge present', () {
      final host = build();

      expect(host.isReady, isFalse);
      expect(host.canvasCapture, isNull);
      expect(host.avatarLoadProgress, isNull);
    });

    test('and still answers after a stop', () {
      final host = build()
        ..start()
        ..stop();

      expect(host.isReady, isFalse);
      expect(host.canvasCapture, isNull);
      expect(host.avatarLoadProgress, isNull);
    });
  });

  group('onReady — now reachable via the injected bridge', () {
    test('fires once the bridge reports ready', () async {
      var fired = 0;
      final bridge = _FakeBridge();
      build(onReady: () => fired++, bridgeFactory: (_) => bridge).start();

      await pumpEventQueue();
      expect(fired, equals(0), reason: 'not ready yet');

      bridge.completeInitialize();
      await pumpEventQueue();

      expect(fired, equals(1));
    });

    test('does NOT fire when initialize finishes without becoming ready',
        () async {
      var fired = 0;
      final bridge = _FakeBridge(readyWhenDone: false);
      build(onReady: () => fired++, bridgeFactory: (_) => bridge).start();

      bridge.completeInitialize();
      // Drain, so a green here means "the guard held", not "the callback has
      // not run yet" — which is what made the pre-seam version of this test
      // pass for the wrong reason.
      await pumpEventQueue();

      expect(fired, equals(0));
    });

    test('does NOT fire for a host stopped before initialize resolves',
        () async {
      // The reason the guard reads the FIELD rather than the local `bridge`:
      // stop() nulls the field, and firing onReady after teardown resurrects a
      // bubble for a Dreamfinder that has already left. Reading the local
      // would still see a ready bridge here and fire.
      var fired = 0;
      final bridge = _FakeBridge();
      final host =
          build(onReady: () => fired++, bridgeFactory: (_) => bridge)..start();

      host.stop();
      bridge.completeInitialize();
      await pumpEventQueue();

      expect(fired, equals(0));
      expect(bridge.disposeCount, equals(1));
    });
  });

  group('reads pass through to the live bridge', () {
    test('avatarLoadProgress comes from the bridge while one exists', () {
      final host = build(bridgeFactory: (_) => _FakeBridge())..start();

      expect(host.avatarLoadProgress, equals(42));

      host.stop();
      expect(host.avatarLoadProgress, isNull);
    });
  });
}
