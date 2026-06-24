import 'package:flutter_test/flutter_test.dart';
import 'package:tech_world/native/decode_size.dart';

void main() {
  group('scaledDecodeSize', () {
    test('passes through when both sides are within the cap', () {
      final r = scaledDecodeSize(200, 150, 256);
      expect(r.width, 200);
      expect(r.height, 150);
    });

    test('exactly at the cap is a pass-through (no upscaling)', () {
      final r = scaledDecodeSize(256, 256, 256);
      expect(r.width, 256);
      expect(r.height, 256);
    });

    test('caps the longest side preserving aspect ratio (landscape 16:9)', () {
      final r = scaledDecodeSize(1280, 720, 256);
      expect(r.width, 256);
      expect(r.height, 144); // 720 * 256/1280
    });

    test('caps the longest side preserving aspect ratio (portrait 9:16)', () {
      final r = scaledDecodeSize(720, 1280, 256);
      expect(r.height, 256);
      expect(r.width, 144);
    });

    test('square frame caps to maxDim x maxDim', () {
      final r = scaledDecodeSize(1000, 1000, 256);
      expect(r.width, 256);
      expect(r.height, 256);
    });

    test('never returns a zero dimension for extreme aspect ratios', () {
      final r = scaledDecodeSize(4096, 8, 256);
      expect(r.width, 256);
      expect(r.height, greaterThanOrEqualTo(1));
    });

    test('common webcam 640x480 shrinks with 4:3 preserved', () {
      final r = scaledDecodeSize(640, 480, 256);
      expect(r.width, 256);
      expect(r.height, 192); // 480 * 256/640
    });

    test('non-positive source dimensions pass through unchanged', () {
      final r = scaledDecodeSize(0, 0, 256);
      expect(r.width, 0);
      expect(r.height, 0);
    });
  });
}
