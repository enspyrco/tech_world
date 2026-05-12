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
}
