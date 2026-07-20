/// Pure, testable heuristic for deciding whether a browser is running on a
/// memory-constrained device that should default to the low-memory safe mode
/// (avatar-only bubbles + reduced motion).
///
/// The motivating failure: an iPhone 8 (2 GB RAM, capped at iOS 16 / old
/// WebKit) white-screens at world entry — the peak memory/GPU moment where the
/// Flame scene, LiveKit connect, video decode, and WebGL shaders all land at
/// once. Safari jettisons the tab before any Dart exception can fire, so the
/// only defence is to *not allocate* the heavy in-world surface on such
/// devices. See [isLowMemoryUserAgent] wired at the two world-entry seams in
/// `main.dart`.
///
/// v1 keys purely off the iOS major version parsed from the userAgent, because:
///   * It targets the confirmed device class exactly — every iPhone that can
///     only reach iOS ≤ 16 is a 2–3 GB A11-or-older device (iPhone 8, 8 Plus,
///     X, 7, SE 1). Anything on iOS 17+ has ≥ 3 GB and newer WebKit.
///   * It needs only `navigator.userAgent`, which is already read WASM-safely
///     elsewhere (`platform_info_web.dart`). `navigator.deviceMemory` is *not*
///     implemented by iOS Safari, so it can't help the actual crashing device.
///
/// Extension point: when low-RAM Android/Chrome becomes evidenced, add a
/// `deviceMemoryGb` parameter and OR in `deviceMemoryGb <= 2` — Chrome exposes
/// `navigator.deviceMemory` quantized to {0.25, 0.5, 1, 2, 4, 8}.
library;

/// True when [userAgent] identifies a device that should default to safe mode.
///
/// Returns `false` for a null/unparseable userAgent — we only enable safe mode
/// on a *positive* identification of an at-risk device, so modern hardware
/// keeps full fidelity.
bool isLowMemoryUserAgent({required String? userAgent}) {
  if (userAgent == null) return false;
  final iosMajor = iosMajorVersion(userAgent);
  return iosMajor != null && iosMajor <= 16;
}

/// Parses the iOS/iPadOS major version from a Mobile Safari userAgent, or
/// `null` if the string isn't a recognisable iOS UA.
///
/// iOS UAs embed the version as e.g. `CPU iPhone OS 16_5 like Mac OS X` on
/// iPhone and `CPU OS 16_5 like Mac OS X` on iPad. (iPadOS 13+ can spoof a
/// desktop-Mac UA with no version token — those fall through to `null` and are
/// treated as not-at-risk, which is correct: an iPad new enough to spoof
/// desktop Safari is not the 2 GB device we're guarding.)
int? iosMajorVersion(String userAgent) {
  final match = RegExp(r'CPU (?:iPhone )?OS (\d+)[_\d]* like Mac OS X')
      .firstMatch(userAgent);
  if (match == null) return null;
  return int.tryParse(match.group(1)!);
}
