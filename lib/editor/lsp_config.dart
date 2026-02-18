/// Constants for the LSP proxy server used by the in-game code editor.
///
/// The proxy runs `lsp-ws-proxy` on the GCP Compute Engine instance,
/// bridging WebSocket connections to `dart language-server --protocol=lsp`.
/// nginx handles SSL termination at `lsp.adventures-in-tech.world`.
abstract final class LspConstants {
  /// WebSocket URL for the LSP proxy (nginx → lsp-ws-proxy → dart LSP).
  static const serverUrl = 'wss://lsp.adventures-in-tech.world';

  /// Workspace root on the server, pre-configured with pubspec.yaml
  /// and analysis_options.yaml so the Dart analysis server resolves types.
  static const workspacePath = 'file:///opt/lsp-workspace';

  /// Language identifier sent during LSP initialization.
  static const languageId = 'dart';

  /// Base path for virtual file URIs. Each editor session creates a unique
  /// file under this path so concurrent sessions don't collide.
  static const fileBasePath = 'file:///opt/lsp-workspace/lib';
}
