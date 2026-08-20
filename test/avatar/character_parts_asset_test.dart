import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tech_world/avatar/avatar_composer.dart';
import 'package:tech_world/avatar/avatar_spec.dart';
import 'package:tech_world/avatar/parts/avatar_part.dart';

/// Ties the enums to the files on disk and runs real part art through the real
/// compositor.
///
/// The composer's own tests use synthetic images, which proves the algorithm
/// but not that any of the declared parts exist or line up. This is the arm
/// that fails when someone adds an enum value without running
/// `tool/extract_character_parts.py`, or re-runs it with a changed manifest.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<ui.Image> loadAsset(String asset) async {
    final file = File('assets/images/$asset');
    final codec = await ui.instantiateImageCodec(await file.readAsBytes());
    return (await codec.getNextFrame()).image;
  }

  group('declared parts exist on disk', () {
    test('every enum asset resolves to a file', () {
      final missing = allPartAssets
          .where((a) => !File('assets/images/$a').existsSync())
          .toList();
      expect(missing, isEmpty,
          reason: 'run tool/extract_character_parts.py, or remove the enum '
              'value — a part declared but not shipped throws at the moment '
              'a player first wears it');
    });

    test('every extracted file is declared by an enum', () {
      // The other direction: a part sitting in assets/ that nothing can select
      // is dead weight in the bundle, and a sign the manifest and the enums
      // have drifted.
      final onDisk = Directory('assets/images/parts')
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.png'))
          .map((f) => f.path.replaceFirst('assets/images/', ''))
          .toSet();
      expect(onDisk.difference(allPartAssets), isEmpty);
    });

    test('the starter set covers every slot', () {
      expect(BodyId.values.where((b) => b.asset.startsWith('parts/')),
          isNotEmpty);
      expect(HairId.values.where((h) => h.asset != null), isNotEmpty);
      expect(OutfitId.values.where((o) => o.asset != null), isNotEmpty);
      expect(AccessoryId.values.where((a) => a.asset != null), isNotEmpty);
    });
  });

  group('real art through the real compositor', () {
    late Map<String, ui.Image> loaded;
    late AvatarComposer composer;

    setUpAll(() async {
      loaded = {
        for (final asset in allPartAssets) asset: await loadAsset(asset),
      };
    });

    setUp(() {
      composer = AvatarComposer(loadImage: (a) => loaded[a]!);
    });

    tearDown(() => composer.clear());

    /// Raw pixels of the composed sheet, for comparing two characters.
    Future<Uint8List> rgba(AvatarSpec spec) async {
      final image = composer.acquire(spec);
      final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      return data!.buffer.asUint8List();
    }

    test('every declared part satisfies the 512x64 sheet contract', () {
      // The composer throws on a bad sheet, so composing each part alone is
      // the assertion. Doing it per-part names the offender, which a single
      // combined composite would not.
      for (final body in BodyId.values) {
        expect(
          () => composer.acquire(AvatarSpec.preset(CompositeAvatar(body: body))),
          returnsNormally,
          reason: body.wireName,
        );
      }
      for (final hair in HairId.values.where((h) => h.asset != null)) {
        expect(
          () => composer.acquire(AvatarSpec.preset(
              CompositeAvatar(body: BodyId.body01, hair: hair))),
          returnsNormally,
          reason: hair.wireName,
        );
      }
      for (final outfit in OutfitId.values.where((o) => o.asset != null)) {
        expect(
          () => composer.acquire(AvatarSpec.preset(
              CompositeAvatar(body: BodyId.body01, outfit: outfit))),
          returnsNormally,
          reason: outfit.wireName,
        );
      }
      for (final acc in AccessoryId.values.where((a) => a.asset != null)) {
        expect(
          () => composer.acquire(AvatarSpec.preset(
              CompositeAvatar(body: BodyId.body01, accessory: acc))),
          returnsNormally,
          reason: acc.wireName,
        );
      }
    });

    test('a fully-dressed character composes to one 512x64 sheet', () async {
      final image = composer.acquire(AvatarSpec.preset(const CompositeAvatar(
        body: BodyId.body03,
        hair: HairId.hair02c02,
        outfit: OutfitId.outfit03c02,
        accessory: AccessoryId.glasses,
      )));

      expect(image.width, kSheetWidth);
      expect(image.height, kSheetHeight);
    });

    test('each added layer actually changes the composed pixels', () async {
      // Counting opaque pixels does NOT work here, and the first version of
      // this test failed because of it: an outfit is painted inside the body's
      // own silhouette, so it recolours pixels without covering any new ones —
      // body-only and dressed both came to 15844. Coverage is the wrong
      // measure for a layer that fits within the one beneath it; the bytes are
      // the thing that changed.
      const body = CompositeAvatar(body: BodyId.body03);
      final bodyOnly = await rgba(const AvatarSpec(parts: body));
      final dressed = await rgba(
          AvatarSpec(parts: body.copyWith(outfit: OutfitId.outfit03c02)));
      final withHair = await rgba(AvatarSpec(
          parts: body.copyWith(
              outfit: OutfitId.outfit03c02, hair: HairId.hair02c02)));
      final withHat = await rgba(AvatarSpec(
          parts: body.copyWith(
              outfit: OutfitId.outfit03c02,
              hair: HairId.hair02c02,
              accessory: AccessoryId.snapback)));

      // A slot that contributed nothing — wrong path, empty sheet, a z-order
      // that buries it — leaves the bytes untouched, which the "composes to
      // 512x64" test above cannot see.
      expect(dressed, isNot(equals(bodyOnly)), reason: 'outfit');
      expect(withHair, isNot(equals(dressed)), reason: 'hair');
      expect(withHat, isNot(equals(withHair)), reason: 'accessory');
    });

    test('two characters differing by one slot compose differently', () async {
      const base = CompositeAvatar(body: BodyId.body05);
      final blond = await rgba(
          AvatarSpec(parts: base.copyWith(hair: HairId.hair01c04)));
      final other = await rgba(
          AvatarSpec(parts: base.copyWith(hair: HairId.hair05c05)));

      expect(blond, isNot(equals(other)),
          reason: 'two hairstyles that render identically would mean the '
              'manifest points two ids at the same source art');
    });
  });
}
