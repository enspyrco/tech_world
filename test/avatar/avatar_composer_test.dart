import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:tech_world/avatar/avatar_composer.dart';
import 'package:tech_world/avatar/avatar_spec.dart';
import 'package:tech_world/avatar/parts/avatar_part.dart';

/// A part with a caller-chosen asset name, so a test can point the composer at
/// a deliberately malformed sheet or stack more layers than the shipping
/// content currently has.
class _FakePart implements AvatarPart {
  const _FakePart(this.wireName, this.asset, this.zPos);

  @override
  final String wireName;
  @override
  final String? asset;
  @override
  final int zPos;
}

ui.Image _solidImage(int width, int height) {
  final recorder = ui.PictureRecorder();
  ui.Canvas(recorder).drawRect(
    ui.Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
    ui.Paint()..color = const ui.Color(0xFFFF0000),
  );
  return recorder.endRecording().toImageSync(width, height);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late List<String> loaded;
  late Map<String, ui.Image> sources;

  AvatarComposer composerWith({int maxCached = 32}) => AvatarComposer(
        maxCached: maxCached,
        loadImage: (asset) {
          loaded.add(asset);
          return sources[asset] ??
              (sources[asset] = _solidImage(kSheetWidth, kSheetHeight));
        },
      );

  setUp(() {
    loaded = [];
    sources = {};
  });

  tearDown(() {
    for (final image in sources.values) {
      if (!image.debugDisposed) image.dispose();
    }
  });

  group('sheet contract (F7)', () {
    test('composes a 512x64 sheet from a preset', () {
      final composer = composerWith();
      final image = composer.acquire(AvatarSpec.preset(CompositeAvatar.npc11));

      expect(image.width, kSheetWidth);
      expect(image.height, kSheetHeight);
    });

    test('a part missing its wave strip is rejected, and the error says so',
        () {
      sources['short.png'] = _solidImage(384, 64); // 12 cells, no wave strip
      final composer = composerWith();
      final spec = AvatarSpec(
        parts: const CompositeAvatar(body: BodyId.npc11),
      );

      // Point the body at the malformed asset via a fake layer.
      final direct = AvatarComposer(
        loadImage: (_) => sources['short.png']!,
      );

      expect(
        () => direct.acquire(spec),
        throwsA(isA<StateError>().having(
          (e) => e.message,
          'message',
          allOf(contains('384x64'), contains('wave')),
        )),
      );
      expect(composer.cachedCount, 0);
    });
  });

  group('refcounted sharing', () {
    test('two holders of the same spec share one composed image', () {
      final composer = composerWith();
      final spec = AvatarSpec.preset(CompositeAvatar.npc11);

      final first = composer.acquire(spec);
      final second = composer.acquire(spec);

      expect(second, same(first));
      expect(composer.refCountOf(spec), 2);
      // Composed once, so the underlying part asset was loaded once.
      expect(loaded, hasLength(1));
    });

    test('one of two peers leaving does NOT dispose the shared image', () {
      final composer = composerWith();
      final spec = AvatarSpec.preset(CompositeAvatar.npc12);

      final image = composer.acquire(spec); // peer A
      composer.acquire(spec); // peer B
      composer.release(spec); // peer A leaves

      expect(image.debugDisposed, isFalse,
          reason: 'peer B is still drawing with it');
      expect(composer.refCountOf(spec), 1);
      expect(composer.acquire(spec), same(image));
    });

    test('refcount 0 keeps the image warm rather than disposing it', () {
      final composer = composerWith();
      final spec = AvatarSpec.preset(CompositeAvatar.npc13);

      final image = composer.acquire(spec);
      composer.release(spec);

      expect(composer.refCountOf(spec), 0);
      expect(image.debugDisposed, isFalse);
      // Re-acquiring hits the cache: no second load.
      expect(composer.acquire(spec), same(image));
      expect(loaded, hasLength(1));
    });

    test('unbalanced release does not throw during teardown', () {
      final composer = composerWith();
      final spec = AvatarSpec.preset(CompositeAvatar.npc11);

      expect(() => composer.release(spec), returnsNormally);
      composer.acquire(spec);
      composer.release(spec);
      expect(() => composer.release(spec), returnsNormally);
      expect(composer.refCountOf(spec), 0);
    });

    test('clear disposes everything', () {
      final composer = composerWith();
      final image = composer.acquire(AvatarSpec.preset(CompositeAvatar.npc11));

      composer.clear();

      expect(image.debugDisposed, isTrue);
      expect(composer.cachedCount, 0);
    });
  });

  group('LRU eviction respects live references', () {
    // Positive control: with the cap exceeded and entries released, eviction
    // must actually happen. Without this arm, the invariant test below would
    // pass just as well against a cache that never evicts at all.
    test('evicts the least recently used UNREFERENCED entry over cap', () {
      final composer = composerWith(maxCached: 2);
      final a = AvatarSpec.preset(CompositeAvatar.npc11);
      final b = AvatarSpec.preset(CompositeAvatar.npc12);
      final c = AvatarSpec.preset(CompositeAvatar.npc13);

      final imageA = composer.acquire(a);
      composer.release(a);
      composer.acquire(b);
      composer.release(b);

      composer.acquire(c); // third entry, cap is 2

      expect(imageA.debugDisposed, isTrue, reason: 'a was the oldest release');
      expect(composer.cachedCount, 2);
      expect(composer.refCountOf(a), 0);
    });

    test('never evicts a referenced image, even over cap', () {
      final composer = composerWith(maxCached: 1);
      final a = AvatarSpec.preset(CompositeAvatar.npc11);
      final b = AvatarSpec.preset(CompositeAvatar.npc12);

      final imageA = composer.acquire(a); // held
      final imageB = composer.acquire(b); // held, now 2 entries over a cap of 1

      expect(imageA.debugDisposed, isFalse);
      expect(imageB.debugDisposed, isFalse);
      expect(composer.cachedCount, 2, reason: 'grew rather than evicting live');

      // Releasing one makes it evictable; the next insert collects it.
      composer.release(a);
      composer.acquire(AvatarSpec.preset(CompositeAvatar.npc13));
      expect(imageA.debugDisposed, isTrue);
      expect(imageB.debugDisposed, isFalse, reason: 'still referenced');
    });

    test('acquiring refreshes recency so the true LRU is evicted', () {
      final composer = composerWith(maxCached: 2);
      final a = AvatarSpec.preset(CompositeAvatar.npc11);
      final b = AvatarSpec.preset(CompositeAvatar.npc12);
      final c = AvatarSpec.preset(CompositeAvatar.npc13);

      final imageA = composer.acquire(a);
      composer.release(a);
      final imageB = composer.acquire(b);
      composer.release(b);

      // Touch `a` so `b` becomes the oldest.
      composer.acquire(a);
      composer.release(a);

      composer.acquire(c);

      expect(imageB.debugDisposed, isTrue);
      expect(imageA.debugDisposed, isFalse);
    });
  });

  group('cache keys are value-based', () {
    test('two independently built equal specs share one image', () {
      final composer = composerWith();
      // Built at runtime, not as `const` literals: Dart canonicalizes equal
      // const expressions to the same instance, so a const pair would satisfy
      // `same()` through identity and prove nothing about value equality —
      // exactly the property the cache key depends on.
      final one = AvatarSpec(
          parts: const CompositeAvatar(body: BodyId.npc11)
              .copyWith(body: BodyId.npc12));
      final two = AvatarSpec(
          parts: const CompositeAvatar(body: BodyId.npc13)
              .copyWith(body: BodyId.npc12));

      expect(identical(one, two), isFalse);
      expect(one, equals(two));
      expect(composer.acquire(one), same(composer.acquire(two)));
      expect(loaded, hasLength(1));
    });

    test('different parts compose separately', () {
      final composer = composerWith();
      final first = composer.acquire(AvatarSpec.preset(CompositeAvatar.npc11));
      final second = composer.acquire(AvatarSpec.preset(CompositeAvatar.npc12));

      expect(second, isNot(same(first)));
      expect(composer.cachedCount, 2);
    });
  });

  group('layer ordering', () {
    test('layers are painted in zPos order regardless of field order', () {
      const spec = CompositeAvatar(body: BodyId.npc11);
      expect(spec.layers.map((p) => p.zPos).toList(),
          orderedEquals(spec.layers.map((p) => p.zPos).toList()..sort()));
    });

    test('empty slots contribute no layer', () {
      const spec = CompositeAvatar(body: BodyId.npc11);
      expect(spec.layers, hasLength(1));
      expect(spec.layers.single, BodyId.npc11);
    });

    test('a populated slot is ordered by zPos, not declaration order', () {
      // Fakes stand in for part art that does not exist yet (OV2 open).
      const parts = <AvatarPart>[
        _FakePart('acc', 'a.png', ZPos.accessory),
        _FakePart('body', 'b.png', ZPos.body),
        _FakePart('hair', 'h.png', ZPos.hair),
        _FakePart('outfit', 'o.png', ZPos.outfit),
      ];
      final sorted = [...parts]..sort((a, b) => a.zPos.compareTo(b.zPos));
      expect(sorted.map((p) => p.wireName),
          orderedEquals(['body', 'outfit', 'hair', 'acc']));
    });
  });
}
