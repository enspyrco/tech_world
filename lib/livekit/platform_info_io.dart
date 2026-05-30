/// Native-platform implementation: reports `Platform.operatingSystem`.
///
/// Used on iOS / Android / macOS / Linux / Windows. Web has its own stub at
/// `platform_info_web.dart`.
library;

import 'dart:io' show Platform;

/// Short OS identifier — `'macos'`, `'ios'`, `'android'`, `'linux'`,
/// `'windows'`, or `'fuchsia'`.
String agentHelloPlatform() => Platform.operatingSystem;

/// Native builds don't have a userAgent — returns null.
String? agentHelloUserAgent() => null;
