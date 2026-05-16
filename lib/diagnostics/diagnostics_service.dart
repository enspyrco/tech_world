import 'package:flutter/foundation.dart';
import 'package:tech_world/preferences/user_preferences.dart';

/// Single owner of runtime diagnostic toggle state.
///
/// Replaces the module-level `_avDiagnosticsEnabled` / `_errorLoggingEnabled`
/// globals in `main.dart` and the shadow `BubbleManager.avDiagnosticsEnabled`
/// field that had to be kept in sync via manual propagation. Both readers
/// and writers now go through this service.
///
/// **Why a service (per `feedback_cross_cutting_toggle_needs_single_owner`):**
/// when a runtime toggle gates dispatches in M call-sites across N classes,
/// the toggle must be owned by exactly one service exposing a
/// [ValueListenable]. Module-level globals with manual propagation to per-class
/// shadow copies invite the regression where a future call-site sets one
/// without the other.
///
/// **Wiring:** registered via [Locator] at app startup
/// (`_initializeAppServices` in `main.dart`). Producers gate AV-event
/// dispatches by reading `avEnabled.value`. Sinks read `.value` from
/// their `enabledCheck` callbacks. UI toggles bind to the listenable
/// via `ValueListenableBuilder`.
class DiagnosticsService {
  DiagnosticsService({
    required bool avEnabled,
    required bool errorLoggingEnabled,
  })  : _av = ValueNotifier<bool>(avEnabled),
        _err = ValueNotifier<bool>(errorLoggingEnabled);

  /// Loads persisted toggle state from [UserPreferences] and constructs
  /// the service. Call once at startup before registering with [Locator].
  static Future<DiagnosticsService> load() async {
    return DiagnosticsService(
      avEnabled: await UserPreferences.avDiagnosticsEnabled(),
      errorLoggingEnabled: await UserPreferences.errorLoggingEnabled(),
    );
  }

  final ValueNotifier<bool> _av;
  final ValueNotifier<bool> _err;

  /// Whether AV pipeline diagnostic events should be generated.
  /// Producers read `.value` before dispatching; the toggle UI binds
  /// to this listenable directly.
  ValueListenable<bool> get avEnabled => _av;

  /// Whether warning-or-above events should be persisted to
  /// `errors.jsonl`. Read by the error sink's `enabledCheck`.
  ValueListenable<bool> get errorLoggingEnabled => _err;

  /// Update the AV toggle and persist. Listeners fire synchronously
  /// before the persistence write completes.
  Future<void> setAvEnabled(bool value) async {
    _av.value = value;
    await UserPreferences.setAvDiagnosticsEnabled(value);
  }

  /// Update the error-logging toggle and persist.
  Future<void> setErrorLoggingEnabled(bool value) async {
    _err.value = value;
    await UserPreferences.setErrorLoggingEnabled(value);
  }

  void dispose() {
    _av.dispose();
    _err.dispose();
  }
}
