import 'package:flutter/foundation.dart';

/// Configuration for server connections.
///
/// In development mode, set the `DEV_SERVER_HOST` environment variable
/// to your local machine's IP address, or it defaults to localhost.
///
/// Example usage:
/// ```bash
/// # Run with custom dev server IP
/// flutter run --dart-define=DEV_SERVER_HOST=192.168.1.100
/// ```
class ServerConfig {
  ServerConfig._();

  /// The WebSocket URL for the game server.
  ///
  /// In release mode: wss://adventures-in-tech.world
  /// In debug mode: ws://{DEV_SERVER_HOST}:8080
  ///
  /// Set DEV_SERVER_HOST via --dart-define to use a custom IP for local
  /// development (e.g., when testing on a physical device).
  static String get gameServerUrl {
    if (kReleaseMode) {
      return 'wss://adventures-in-tech.world';
    }
    return 'ws://$devServerHost:$devServerPort';
  }

  /// The host for the development server.
  /// Defaults to '127.0.0.1' (localhost).
  /// Override with: --dart-define=DEV_SERVER_HOST=192.168.1.100
  static const String devServerHost = String.fromEnvironment(
    'DEV_SERVER_HOST',
    defaultValue: '127.0.0.1',
  );

  /// The port for the development server.
  /// Defaults to 8080.
  /// Override with: --dart-define=DEV_SERVER_PORT=9000
  static const int devServerPort = int.fromEnvironment(
    'DEV_SERVER_PORT',
    defaultValue: 8080,
  );
}
