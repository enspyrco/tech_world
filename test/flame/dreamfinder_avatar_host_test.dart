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

  /// Fail the in-flight initialize, so the host's error path can be driven.
  void failInitialize(Object error) {
    if (!_gate.isCompleted) _gate.completeError(error);
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

  group('a FAILED initialize must not latch the slot (cage-match #530, Tesla)',
      () {
    // start() early-returns on `_bridge != null`. A bridge left occupying the
    // slot after a failed initialize made every later Dreamfinder arrival a
    // silent no-op for the rest of the session — the avatar simply never came
    // back, with one warning in the log to say why.

    test('a late success from a REPLACED bridge must not fire onReady for its '
        'successor', () async {
      // Tesla, PR #530 round 2. The ready arm read the FIELD's readiness rather
      // than checking identity, so stop()+start() leaving two initialize
      // futures in flight meant the OLD one settling while the NEW bridge was
      // already ready fired _onReady for a successor it never initialized.
      // The other two arms were identity-guarded; this was the third door.
      final first = _FakeBridge();
      final second = _FakeBridge();
      var built = 0;
      var readyCount = 0;
      final host = build(
        onReady: () => readyCount++,
        bridgeFactory: (_) {
          built++;
          return built == 1 ? first : second;
        },
      );

      host.start();      // first is in flight
      host.stop();       // slot released; first's future still outstanding
      host.start();      // second takes the slot
      second.completeInitialize();
      await pumpEventQueue();
      expect(readyCount, 1, reason: 'the live bridge legitimately reports ready');

      // Now the ABANDONED first bridge finally resolves.
      first.completeInitialize();
      await pumpEventQueue();

      expect(readyCount, 1,
          reason: 'a future belonging to a replaced bridge must not fire '
              'onReady for the bridge that replaced it');
    });

    test('a THROWING initialize disposes the bridge, not just the slot',
        () async {
      // Tesla, PR #530 delta cage-match: the not-ready branch disposed and
      // wrote a comment saying why ("dropping the reference without disposing
      // leaks it") while catchError, one door over, cleared the slot and left
      // the iframe running. Same coil, other tap.
      final bridge = _FakeBridge();
      final host = build(onReady: () {}, bridgeFactory: (_) => bridge);

      host.start();
      bridge.failInitialize(StateError('iframe refused'));
      await pumpEventQueue();

      expect(bridge.disposeCount, 1,
          reason: 'a failed initialize can still have constructed the iframe');
    });

    test('an onReady callback that throws must NOT release a live bridge',
        () async {
      // _onReady runs inside the initialize `then`, so a throw in the CALLER'S
      // callback propagated to catchError and released the slot for a bridge
      // that had become ready — the next arrival would build a second iframe
      // beside a live one nobody would ever stop().
      final bridge = _FakeBridge();
      var built = 0;
      final host = build(
        onReady: () => throw StateError('consumer blew up'),
        bridgeFactory: (_) {
          built++;
          return bridge;
        },
      );

      host.start();
      bridge.completeInitialize();
      await pumpEventQueue();

      expect(bridge.disposeCount, 0,
          reason: 'the bridge became ready; the consumer failing is not '
              'evidence about the bridge');

      host.start();
      expect(built, 1,
          reason: 'the slot must still be held by the live bridge, so a second '
              'start() builds nothing');
    });

    test('a bridge that finishes NOT READY also releases the slot', () async {
      // Confirming round, Carnot: the first version of this fix closed only
      // the THROWING door. An initialize that RESOLVES while leaving
      // isReady == false never reaches catchError, so the slot stayed held by
      // something that would never be ready and every later arrival was a
      // no-op exactly as before.
      final first = _FakeBridge(readyWhenDone: false);
      final second = _FakeBridge();
      var built = 0;
      final host = build(
        onReady: () {},
        bridgeFactory: (_) {
          built++;
          return built == 1 ? first : second;
        },
      );

      host.start();
      first.completeInitialize(); // resolves, but never becomes ready
      await pumpEventQueue();

      expect(first.disposeCount, 1,
          reason: 'the bridge owns an iframe — dropping it without disposing '
              'leaks it, and stop() disposes for the same reason');

      host.start();
      expect(built, 2,
          reason: 'a bridge that will never be ready must not hold the slot');
    });

    test('a later start() builds a NEW bridge after a failure', () async {
      final first = _FakeBridge();
      final second = _FakeBridge();
      var built = 0;
      final host = build(
        onReady: () {},
        bridgeFactory: (_) {
          built++;
          return built == 1 ? first : second;
        },
      );

      host.start();
      expect(built, 1);
      first.failInitialize(StateError('iframe blocked'));
      await pumpEventQueue();

      // The next Dreamfinder arrives.
      host.start();
      expect(built, 2,
          reason: 'a failed bridge must release the slot, or the avatar never '
              'returns for the rest of the session');
    });

    test('NULL ARM: a SUCCEEDING initialize still holds the slot', () {
      final bridge = _FakeBridge();
      var built = 0;
      final host = build(
        onReady: () {},
        bridgeFactory: (_) {
          built++;
          return bridge;
        },
      );
      host.start();
      bridge.completeInitialize();
      host.start();
      expect(built, 1,
          reason: 'a healthy bridge must not be rebuilt on every start()');
    });
  });
}
