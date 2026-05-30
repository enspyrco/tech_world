/// Agent-hello payload — one-shot self-report sent by every client on connect.
///
/// Lets the bot fleet observe each client's actual `ConnectOptions` and warn
/// when a known-bad configuration (e.g. `adaptiveStream: true`, which breaks
/// Tech World video/audio forwarding because we render via Flame canvas
/// instead of `VideoTrackRenderer`) shows up in the wild.
///
/// Schema is intentionally flat and stable; `schemaVersion` lets future bot
/// code switch on the shape if it ever changes.
library;

import 'dart:convert';

import 'package:flutter/foundation.dart' show kIsWeb;

/// Current schema version stamped on every outgoing agent-hello payload.
///
/// Bump only on a breaking shape change. Additive field changes don't require
/// a bump — bot code reads fields defensively.
const int kAgentHelloSchemaVersion = 1;

/// Pure builder for the agent-hello payload.
///
/// All inputs are explicit so the function can be unit-tested without any
/// `Room`, platform, or environment dependency. Callers (live code in
/// `livekit_service.dart`) pass real values; tests pass fixtures.
///
/// Returns a `Map<String, Object?>` ready to be `jsonEncode`d. We don't
/// encode here so call sites can interpose if they need to.
Map<String, Object?> buildAgentHelloPayload({
  required String clientSdkVersion,
  required String buildSha,
  required String appVersion,
  required bool adaptiveStream,
  required bool dynacast,
  required String platform,
  String? userAgent,
}) {
  return {
    'schemaVersion': kAgentHelloSchemaVersion,
    'clientSdk': 'flutter',
    'clientSdkVersion': clientSdkVersion,
    'buildSha': buildSha,
    'appVersion': appVersion,
    'adaptiveStream': adaptiveStream,
    'dynacast': dynacast,
    'platform': platform,
    'userAgent': userAgent,
  };
}

/// Encode the payload as UTF-8 bytes for `publishData`.
List<int> encodeAgentHelloPayload(Map<String, Object?> payload) {
  return utf8.encode(jsonEncode(payload));
}

/// Whether the current Flutter runtime is web — exposed for call-site clarity
/// so platform resolution lives in one place.
bool get isWebRuntime => kIsWeb;
