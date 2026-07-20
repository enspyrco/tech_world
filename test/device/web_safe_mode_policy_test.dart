import 'package:flutter_test/flutter_test.dart';
import 'package:tech_world/device/web_safe_mode_policy.dart';

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
  const firefoxIOS16 =
      'Mozilla/5.0 (iPhone; CPU iPhone OS 16_5 like Mac OS X) '
      'AppleWebKit/605.1.15 (KHTML, like Gecko) FxiOS/120.0 '
      'Mobile/15E148 Safari/605.1.15';
  const desktopChrome =
      'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) '
      'AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36';
  const androidChrome =
      'Mozilla/5.0 (Linux; Android 13; Pixel 7) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36';
  // Adversarial: an iPhone 8 with Safari "Request Desktop Website" sends a
  // Macintosh-style UA with no `CPU iPhone OS N` token — byte-indistinguishable
  // from a real Mac. This is the documented residual gap (opt-out of safe mode).
  const macSafari =
      'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) '
      'AppleWebKit/605.1.15 (KHTML, like Gecko) Version/16.6 Safari/605.1.15';

  group('isLegacyIosWebClient — at-risk (iOS ≤ 16 → force safe mode)', () {
    test('iPhone 8 on iOS 16', () {
      expect(isLegacyIosWebClient(userAgent: iphone8IOS16), isTrue);
    });
    test('iPhone 8 on iOS 15', () {
      expect(isLegacyIosWebClient(userAgent: iphone8IOS15), isTrue);
    });
    test('iPad on iPadOS 16 (no "iPhone" token; harmless false-positive)', () {
      expect(isLegacyIosWebClient(userAgent: ipadIOS16), isTrue);
    });
    test('Chrome on iOS 16 (WebKit under the hood)', () {
      expect(isLegacyIosWebClient(userAgent: chromeIOS16), isTrue);
    });
    test('Firefox on iOS 16 (also WebKit under the hood)', () {
      expect(isLegacyIosWebClient(userAgent: firefoxIOS16), isTrue);
    });
  });

  group('isLegacyIosWebClient — not at-risk (iOS ≥ 17 / non-iOS)', () {
    test('iPhone on iOS 17', () {
      expect(isLegacyIosWebClient(userAgent: iphone17IOS17), isFalse);
    });
    test('iPhone on iOS 18', () {
      expect(isLegacyIosWebClient(userAgent: iphone15IOS18), isFalse);
    });
    test('desktop Chrome', () {
      expect(isLegacyIosWebClient(userAgent: desktopChrome), isFalse);
    });
    test('Android Chrome', () {
      expect(isLegacyIosWebClient(userAgent: androidChrome), isFalse);
    });
    test('real Mac Safari 16', () {
      expect(isLegacyIosWebClient(userAgent: macSafari), isFalse);
    });
    test('null userAgent → not at-risk (positive-ID only)', () {
      expect(isLegacyIosWebClient(userAgent: null), isFalse);
    });
    test('empty string', () {
      expect(isLegacyIosWebClient(userAgent: ''), isFalse);
    });
    test('garbage userAgent', () {
      expect(isLegacyIosWebClient(userAgent: 'not a real ua'), isFalse);
    });
  });

  group('documented residual gap — desktop-mode iPhone opts out', () {
    // An iPhone 8 with "Request Desktop Website" is indistinguishable from a
    // Mac and therefore NOT forced into safe mode. This test pins the known
    // limitation so a future change that closes it is a deliberate, visible
    // decision — not an accident.
    test('desktop-mode iPhone (Mac UA) is treated as full fidelity', () {
      expect(isLegacyIosWebClient(userAgent: macSafari), isFalse);
    });
  });

  group('iosMajorVersion + boundary', () {
    test('parses iPhone UA', () => expect(iosMajorVersion(iphone8IOS16), 16));
    test('parses iPad UA (CPU OS form)',
        () => expect(iosMajorVersion(ipadIOS16), 16));
    test('parses iOS 17', () => expect(iosMajorVersion(iphone17IOS17), 17));
    test('null for non-iOS UA', () {
      expect(iosMajorVersion(desktopChrome), isNull);
      expect(iosMajorVersion(androidChrome), isNull);
      expect(iosMajorVersion(macSafari), isNull);
    });
    // Synthetic boundary strings (not full UAs) — the ≤ 16 cutoff is the whole
    // policy, so pin it directly against the version number.
    test('synthetic 16_0 is at-risk, 17_0 is not', () {
      const s16 = 'CPU iPhone OS 16_0 like Mac OS X';
      const s17 = 'CPU iPhone OS 17_0 like Mac OS X';
      expect(isLegacyIosWebClient(userAgent: s16), isTrue);
      expect(isLegacyIosWebClient(userAgent: s17), isFalse);
      expect(iosMajorVersion(s16), 16);
      expect(iosMajorVersion(s17), 17);
    });
  });
}
