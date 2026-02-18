import 'package:code_forge_web/code_forge_web.dart';
import 'package:flutter/material.dart';
import 'package:re_highlight/languages/dart.dart';
import 'package:tech_world/editor/challenge.dart';
import 'package:tech_world/editor/lsp_config.dart';

/// Panel that displays a code editor for a coding challenge.
/// Replaces the chat panel when a player interacts with a terminal.
class CodeEditorPanel extends StatefulWidget {
  const CodeEditorPanel({
    required this.challenge,
    required this.onClose,
    required this.onSubmit,
    super.key,
  });

  final Challenge challenge;
  final VoidCallback onClose;
  final void Function(String code) onSubmit;

  @override
  State<CodeEditorPanel> createState() => _CodeEditorPanelState();
}

class _CodeEditorPanelState extends State<CodeEditorPanel> {
  late final CodeForgeWebController _controller;
  late final String _fileUri;

  static const _clawdOrange = Color(0xFFD97757);

  @override
  void initState() {
    super.initState();

    final timestamp = DateTime.now().millisecondsSinceEpoch;
    _fileUri =
        '${LspConstants.fileBasePath}/${widget.challenge.id}_$timestamp.dart';

    LspSocketConfig? lspConfig;
    try {
      lspConfig = LspSocketConfig(
        serverUrl: LspConstants.serverUrl,
        workspacePath: LspConstants.workspacePath,
        languageId: LspConstants.languageId,
        capabilities: const LspClientCapabilities(
          codeCompletion: true,
          hoverInfo: true,
          signatureHelp: true,
          semanticHighlighting: false,
          codeAction: false,
          documentColor: false,
          documentHighlight: false,
          codeFolding: false,
          inlayHint: false,
          goToDefinition: false,
          rename: false,
        ),
      );
    } catch (_) {
      // Catches synchronous constructor errors (e.g. malformed URL).
      // Async WebSocket failures (e.g. DNS) are handled internally by
      // CodeForgeWebController — the editor falls back to plain text.
    }

    _controller = CodeForgeWebController(lspConfig: lspConfig);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _handleSubmit() {
    final code = _controller.text;
    widget.onSubmit(code);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF1E1E1E),
      child: Column(
        children: [
          // Header
          Container(
            padding: const EdgeInsets.all(16),
            decoration: const BoxDecoration(
              color: Color(0xFF2D2D2D),
              border: Border(
                bottom: BorderSide(color: Color(0xFF3D3D3D)),
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: const Color(0xFF00FF41).withValues(alpha: 0.2),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: const Color(0xFF00FF41),
                      width: 2,
                    ),
                  ),
                  child: const Center(
                    child: Text(
                      '>_',
                      style: TextStyle(
                        color: Color(0xFF00FF41),
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    widget.challenge.title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                IconButton(
                  onPressed: widget.onClose,
                  icon: const Icon(Icons.close),
                  color: Colors.grey[400],
                  iconSize: 20,
                ),
              ],
            ),
          ),

          // Challenge description
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: const BoxDecoration(
              color: Color(0xFF252525),
              border: Border(
                bottom: BorderSide(color: Color(0xFF3D3D3D)),
              ),
            ),
            child: Text(
              widget.challenge.description,
              style: TextStyle(
                color: Colors.grey[300],
                fontSize: 13,
                height: 1.5,
              ),
            ),
          ),

          // Code editor
          Expanded(
            child: CodeForgeWeb(
              controller: _controller,
              initialText: widget.challenge.starterCode,
              language: langDart,
              fileUri: _fileUri,
              textStyle: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 14,
              ),
              enableSuggestions: true,
              enableFolding: false,
            ),
          ),

          // Footer with submit button
          Container(
            padding: const EdgeInsets.all(16),
            decoration: const BoxDecoration(
              color: Color(0xFF2D2D2D),
              border: Border(
                top: BorderSide(color: Color(0xFF3D3D3D)),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: widget.onClose,
                  child: Text(
                    'Cancel',
                    style: TextStyle(color: Colors.grey[400]),
                  ),
                ),
                const SizedBox(width: 12),
                ElevatedButton.icon(
                  onPressed: _handleSubmit,
                  icon: const Icon(Icons.send, size: 16),
                  label: const Text('Submit to Clawd'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _clawdOrange,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 12,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
