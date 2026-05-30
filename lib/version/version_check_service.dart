import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// Polls `/version.json` to detect when a newer bundle has been deployed
/// to the server than the one the user is currently running.
///
/// Build SHA injection:
/// - At build time CI writes `web/version.json` (`{"build": "...", ...}`).
/// - At build time CI also passes `--dart-define=APP_BUILD_SHA=...` so the
///   running bundle knows its own SHA via [String.fromEnvironment].
///
/// When the server build differs from the runtime build, [updateAvailable]
/// flips to true. Consumers (the in-app banner) listen via
/// [ValueListenable].
///
/// The dev/local case (`APP_BUILD_SHA == 'dev'`) is treated as "do not
/// nag" — the polling still runs, but a mismatch against a real deployed
/// SHA wouldn't be actionable. We compare strings regardless; the
/// `'dev'` value is just what shows up when no `--dart-define` was set.
class VersionCheckService {
  VersionCheckService({
    required this.runtimeBuild,
    required this.versionJsonUrl,
    http.Client? httpClient,
    Duration pollInterval = const Duration(minutes: 5),
    DateTime Function() now = _defaultNow,
  })  : _http = httpClient ?? http.Client(),
        _pollInterval = pollInterval,
        _now = now;

  /// The SHA the running bundle was built from, injected via
  /// `--dart-define=APP_BUILD_SHA=...`. `'dev'` in local builds.
  final String runtimeBuild;

  /// The URL to GET `version.json` from. For the deployed web app this is
  /// the relative path `/version.json` resolved against the current origin;
  /// CI deploys `version.json` alongside `index.html`.
  final String versionJsonUrl;

  final http.Client _http;
  final Duration _pollInterval;
  final DateTime Function() _now;

  static DateTime _defaultNow() => DateTime.now();

  final ValueNotifier<bool> _updateAvailable = ValueNotifier<bool>(false);

  /// True once a poll observes a server build SHA that differs from
  /// [runtimeBuild]. Latches to true — never flips back.
  ValueListenable<bool> get updateAvailable => _updateAvailable;

  Timer? _timer;
  bool _disposed = false;

  /// Kick off the first check immediately, then poll every [_pollInterval].
  void start() {
    // First check fires immediately (non-blocking).
    unawaited(_checkOnce());
    _timer = Timer.periodic(_pollInterval, (_) => _checkOnce());
  }

  /// Cancel the polling timer and the underlying HTTP client.
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _timer?.cancel();
    _timer = null;
    _http.close();
    _updateAvailable.dispose();
  }

  /// Perform one poll. Public so tests can drive it deterministically
  /// instead of waiting on the timer.
  @visibleForTesting
  Future<void> checkOnce() => _checkOnce();

  Future<void> _checkOnce() async {
    if (_disposed) return;
    // Latched — once true, no need to keep polling, but we leave the timer
    // running rather than complicate the lifecycle. The fetch is cheap.
    if (_updateAvailable.value) return;
    try {
      final url = Uri.parse(
        '$versionJsonUrl?t=${_now().millisecondsSinceEpoch}',
      );
      final response = await _http.get(url, headers: const {
        'Cache-Control': 'no-cache',
      });
      if (response.statusCode != 200) return;
      final json = jsonDecode(response.body);
      if (json is! Map) return;
      final serverBuild = json['build'];
      if (serverBuild is! String || serverBuild.isEmpty) return;
      if (serverBuild != runtimeBuild) {
        _updateAvailable.value = true;
      }
    } catch (_) {
      // Network blip, JSON corruption, server hiccup — ignore. We'll try
      // again on the next poll. There is no benefit to dispatching this
      // upstream: the failure mode "user keeps running the old bundle"
      // is the default with or without this service.
    }
  }
}
