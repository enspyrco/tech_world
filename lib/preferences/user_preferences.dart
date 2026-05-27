import 'package:shared_preferences/shared_preferences.dart';

/// Local-only (per-device) user preferences persisted via [SharedPreferences].
///
/// Keys are kept here so producers and consumers can't drift.
abstract final class UserPreferences {
  /// Whether the user has opted to replace proximity *video* bubbles with the
  /// existing avatar-only placeholder. Audio is unaffected.
  ///
  /// Motivated by ASD accessibility research (face-in-bubble can be
  /// overwhelming), but generally useful for privacy and bandwidth.
  static const String hideVideoBubblesKey = 'hideVideoBubbles';

  /// Read the saved [hideVideoBubblesKey] value, defaulting to `false` when
  /// the user has never toggled it.
  static Future<bool> hideVideoBubbles() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(hideVideoBubblesKey) ?? false;
  }

  /// Persist the [hideVideoBubblesKey] preference.
  static Future<void> setHideVideoBubbles(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(hideVideoBubblesKey, value);
  }

  /// Whether the user has opted to disable purely decorative animation on
  /// proximity video bubbles. When on, the bubble breathing scale, voice
  /// ripples, and metaball merge animation render in their resting state.
  ///
  /// Universal benefit (vestibular disorders, low-power devices, ADHD, autism,
  /// motion sensitivity). Gameplay-essential animation — avatar walk, bubble
  /// physics repulsion, camera, tile rendering — is unaffected.
  static const String reduceMotionKey = 'reduceMotion';

  /// Read the saved [reduceMotionKey] value, defaulting to `false` when
  /// the user has never toggled it.
  static Future<bool> reduceMotion() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(reduceMotionKey) ?? false;
  }

  /// Persist the [reduceMotionKey] preference.
  static Future<void> setReduceMotion(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(reduceMotionKey, value);
  }

  /// Default proximity radius (grid squares, Chebyshev) when the user has
  /// never touched the slider. Matches the historical hardcoded behaviour
  /// from before the slider existed.
  static const int defaultProximityRadius = 3;

  /// Maximum value exposed by the "Proximity range" slider.
  static const int maxProximityRadius = 6;

  /// User-configurable proximity radius (grid squares, Chebyshev). When `0`,
  /// proximity is disabled entirely — no video bubble ever forms for anyone.
  /// Otherwise the value is the Chebyshev radius around the local player
  /// inside which other players become nearby.
  ///
  /// Universal benefit: overstimulation reduction (autism / ADHD / sensory
  /// sensitivity), conscious-presence-without-socializing primitive, and
  /// performance on slow devices. Same accessibility lineage as
  /// [hideVideoBubblesKey] and [reduceMotionKey].
  static const String proximityRadiusKey = 'proximityRadius';

  /// Read the saved [proximityRadiusKey] value, clamped to
  /// `[0, maxProximityRadius]`, defaulting to [defaultProximityRadius] when
  /// the user has never set it.
  static Future<int> proximityRadius() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getInt(proximityRadiusKey) ?? defaultProximityRadius;
    if (raw < 0) return 0;
    if (raw > maxProximityRadius) return maxProximityRadius;
    return raw;
  }

  /// Persist the [proximityRadiusKey] preference. Values outside the
  /// `[0, maxProximityRadius]` range are clamped before saving — the slider
  /// in the UI is the producer, so this should not happen in practice, but
  /// the clamp keeps consumers safe from corrupted on-disk values.
  static Future<void> setProximityRadius(int value) async {
    final clamped = value < 0
        ? 0
        : (value > maxProximityRadius ? maxProximityRadius : value);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(proximityRadiusKey, clamped);
  }

  // ── AV diagnostics ─────────────────────────────────────────────────────

  /// Whether to write AV pipeline diagnostic events (periodic snapshots,
  /// track lifecycle, capture init, bubble create/remove) to
  /// `av-pipeline.jsonl`. Default on — local-only logs, rotates at
  /// 5MB x 3 files. Override via `DiagnosticsService.setAvEnabled(false)`
  /// when a session needs to be untraced.
  static const String avDiagnosticsEnabledKey = 'avDiagnosticsEnabled';

  static Future<bool> avDiagnosticsEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(avDiagnosticsEnabledKey) ?? true;
  }

  static Future<void> setAvDiagnosticsEnabled(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(avDiagnosticsEnabledKey, value);
  }

  /// Whether to write error-level events (warning+) to `errors.jsonl`.
  /// Default on — low volume, high signal, rarely a reason to disable.
  static const String errorLoggingEnabledKey = 'errorLoggingEnabled';

  static Future<bool> errorLoggingEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(errorLoggingEnabledKey) ?? true;
  }

  static Future<void> setErrorLoggingEnabled(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(errorLoggingEnabledKey, value);
  }
}
