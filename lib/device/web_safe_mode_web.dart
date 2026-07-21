/// Web implementation: reads the browser userAgent and delegates the at-risk
/// decision to the pure policy.
library;

import 'package:web/web.dart' as web;

import 'web_safe_mode_policy.dart';

/// `true` on a client that must be forced into web safe mode (currently: legacy
/// iOS Safari ≤ 16).
///
/// FAIL-CLOSED polarity. If `navigator.userAgent` throws (a sandboxed iframe or
/// a browser mid-freeze), we return `true` — force safe mode — rather than
/// `false`. This is a crash-safety floor: a false `true` costs a modern client
/// avatar-only mode (a graceful degrade), while a false `false` on the at-risk
/// device restores the exact allocation storm this exists to prevent. Under
/// uncertainty a floor must withhold the dangerous path, not grant it.
bool requiresWebSafeMode() {
  try {
    return isLegacyIosWebClient(userAgent: web.window.navigator.userAgent);
  } catch (_) {
    return true;
  }
}

/// `true` on a mobile browser (see [isMobileWebUserAgent]).
///
/// Fails **safe** (returns `true`) if the userAgent read throws — showing DF's
/// 2D sprite is harmless, whereas a false negative on mobile brings back the
/// black embodied bubble this suppresses.
bool isMobileWeb() {
  try {
    return isMobileWebUserAgent(userAgent: web.window.navigator.userAgent);
  } catch (_) {
    return true;
  }
}
