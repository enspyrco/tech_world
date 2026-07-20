/// Pure, testable policy for deciding whether the current *web* client must be
/// forced into safe mode (avatar-only bubbles + reduced motion) to survive
/// world entry.
///
/// This is a **policy over the browser/OS, not a memory measurement** — the
/// name says what it detects, not what it wishes it could. The motivating
/// failure: an iPhone 8 (2 GB RAM, capped at iOS 16 / old WebKit) white-screens
/// at world entry, the peak where the Flame scene, LiveKit connect, per-frame
/// video decode, and WebGL shaders all land at once. Safari jettisons the tab
/// before any Dart exception can fire, so the only defence is to *not allocate*
/// the heavy in-world video surface on such a client.
///
/// v1 keys off the iOS major version parsed from the userAgent: **iOS/iPadOS
/// Safari with major version ≤ 16**. Every iPhone that tops out at iOS 16 is a
/// 2–3 GB A11-or-older device (iPhone 8/8+/X/7/SE1); anything on iOS 17+ has
/// ≥ 3 GB and newer WebKit. `navigator.userAgent` is the only signal iOS Safari
/// exposes — it does not implement `navigator.deviceMemory`.
///
/// KNOWN RESIDUAL GAPS (documented, not silently absorbed):
///  1. **Desktop-mode opt-out.** An iPhone with Safari's "Request Desktop
///     Website" on sends a Macintosh-style UA with no `CPU iPhone OS N` token,
///     so [iosMajorVersion] returns null and the client is treated as full
///     fidelity. This is irreducible for UA sniffing: a desktop-mode iPhone UA
///     is byte-indistinguishable from a real Mac. We cannot close it without
///     forcing safe mode on every real desktop too.
///  2. **iPad false-positive (harmless).** A high-RAM iPad still on iPadOS 16
///     is flagged at-risk it doesn't need to be. The cost is avatar-only mode,
///     never a crash — acceptable for a crash-safety floor.
///
/// Extension point: when low-RAM Android/Chrome is evidenced, add a
/// `deviceMemoryGb` parameter and OR in `deviceMemoryGb <= 2` (Chrome quantizes
/// `navigator.deviceMemory` to {0.25, 0.5, 1, 2, 4, 8}).
library;

/// True when [userAgent] identifies a legacy iOS/iPadOS Safari client (major
/// version ≤ 16) that must be forced into web safe mode.
///
/// Returns `false` for a null/unparseable userAgent — we only enable safe mode
/// on a *positive* identification, so modern hardware keeps full fidelity. (The
/// *runtime* boundary in `web_safe_mode_web.dart` fails the other way — closed —
/// when the userAgent read itself throws; see the polarity note there.)
bool isLegacyIosWebClient({required String? userAgent}) {
  if (userAgent == null) return false;
  final iosMajor = iosMajorVersion(userAgent);
  return iosMajor != null && iosMajor <= 16;
}

/// Parses the iOS/iPadOS major version from a Mobile Safari userAgent, or
/// `null` if the string isn't a recognisable iOS UA.
///
/// iOS UAs embed the version as e.g. `CPU iPhone OS 16_5 like Mac OS X` on
/// iPhone and `CPU OS 16_5 like Mac OS X` on iPad. (A desktop-mode iPad/iPhone
/// spoofing a Macintosh UA has no such token and returns `null` — see residual
/// gap 1 in the library doc.)
int? iosMajorVersion(String userAgent) {
  final match = RegExp(r'CPU (?:iPhone )?OS (\d+)[_\d]* like Mac OS X')
      .firstMatch(userAgent);
  if (match == null) return null;
  return int.tryParse(match.group(1)!);
}
