import 'package:flutter_test/flutter_test.dart';
import 'package:tech_world/device/low_memory_heuristic.dart';

void main() {
  // Real userAgent strings captured from the named devices/browsers — external
  // known-answer vectors, not values derived from the parser under test.
  const iphone8IOS16 =
      'Mozilla/5.0 (iPhone; CPU iPhone OS 16_7_10 like Mac OS X) '
      'AppleWebKit/605.1.15 (KHTML, like Gecko) Version/16.6 '
      'Mobile/15E148 Safari/604.1';
  const iphone8IOS15 =
      'Mozilla/5.0 (iPhone; CPU iPhone OS 15_8 like Mac OS X) '
      'AppleWebKit/605.1.15 (KHTML, like Gecko) Version/15.6 '
      'Mobile/15E148 Safari/604.1';
  const iphone15IOS18 =
      'Mozilla/5.0 (iPhone; CPU iPhone OS 18_2 like Mac OS X) '
      'AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.2 '
      'Mobile/15E148 Safari/604.1';
  const iphone17IOS17 =
      'Mozilla/5.0 (iPhone; CPU iPhone OS 17_5_1 like Mac OS X) '
      'AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.5 '
      'Mobile/15E148 Safari/604.1';
  const ipadIOS16 =
      'Mozilla/5.0 (iPad; CPU OS 16_5 like Mac OS X) '
      'AppleWebKit/605.1.15 (KHTML, like Gecko) Version/16.5 '
      'Mobile/15E148 Safari/604.1';
  const chromeIOS16 =
      'Mozilla/5.0 (iPhone; CPU iPhone OS 16_5 like Mac OS X) '
      'AppleWebKit/605.1.15 (KHTML, like Gecko) CriOS/120.0.6099.119 '
      'Mobile/15E148 Safari/604.1';
  const desktopChrome =
      'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) '
      'AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36';
  const androidChrome =
      'Mozilla/5.0 (Linux; Android 13; Pixel 7) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36';

  group('isLowMemoryUserAgent — at-risk (iOS ≤ 16)', () {
    test('iPhone 8 on iOS 16', () {
      expect(isLowMemoryUserAgent(userAgent: iphone8IOS16), isTrue);
    });
    test('iPhone 8 on iOS 15', () {
      expect(isLowMemoryUserAgent(userAgent: iphone8IOS15), isTrue);
    });
    test('iPad on iPadOS 16 (no "iPhone" token)', () {
      expect(isLowMemoryUserAgent(userAgent: ipadIOS16), isTrue);
    });
    test('Chrome on iOS 16 (still WebKit under the hood)', () {
      expect(isLowMemoryUserAgent(userAgent: chromeIOS16), isTrue);
    });
  });

  group('isLowMemoryUserAgent — not at-risk (iOS ≥ 17 / non-iOS)', () {
    test('iPhone on iOS 17', () {
      expect(isLowMemoryUserAgent(userAgent: iphone17IOS17), isFalse);
    });
    test('iPhone on iOS 18', () {
      expect(isLowMemoryUserAgent(userAgent: iphone15IOS18), isFalse);
    });
    test('desktop Chrome', () {
      expect(isLowMemoryUserAgent(userAgent: desktopChrome), isFalse);
    });
    test('Android Chrome', () {
      expect(isLowMemoryUserAgent(userAgent: androidChrome), isFalse);
    });
    test('null userAgent fails open to full fidelity', () {
      expect(isLowMemoryUserAgent(userAgent: null), isFalse);
    });
    test('garbage userAgent is not at-risk', () {
      expect(isLowMemoryUserAgent(userAgent: 'not a real ua'), isFalse);
    });
  });

  group('iosMajorVersion', () {
    test('parses iPhone UA', () {
      expect(iosMajorVersion(iphone8IOS16), 16);
    });
    test('parses iPad UA (CPU OS form)', () {
      expect(iosMajorVersion(ipadIOS16), 16);
    });
    test('parses iOS 17', () {
      expect(iosMajorVersion(iphone17IOS17), 17);
    });
    test('returns null for non-iOS UA', () {
      expect(iosMajorVersion(desktopChrome), isNull);
      expect(iosMajorVersion(androidChrome), isNull);
    });
    // Boundary: the ≤ 16 cutoff is the whole policy. Pin it explicitly so a
    // future bump to "≤ 17" can't slip in unnoticed.
    test('16 is at-risk, 17 is not (boundary)', () {
      expect(isLowMemoryUserAgent(userAgent: iphone8IOS16), isTrue);
      expect(isLowMemoryUserAgent(userAgent: iphone17IOS17), isFalse);
    });
  });
}
