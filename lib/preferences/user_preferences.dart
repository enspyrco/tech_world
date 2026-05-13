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
}
