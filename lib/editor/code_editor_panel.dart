import 'package:code_forge_web/code_forge_web.dart';
import 'package:flutter/material.dart';
import 'package:re_highlight/languages/dart.dart';
import 'package:tech_world/editor/challenge.dart';
import 'package:tech_world/editor/lsp_config.dart';
import 'package:tech_world/flame/components/bot_status.dart';
import 'package:tech_world/flame/shared/constants.dart';

/// Panel that displays a code editor for a coding challenge.
/// Replaces the chat panel when a player interacts with a terminal.
class CodeEditorPanel extends StatefulWidget {
  const CodeEditorPanel({
    required this.challenge,
    required this.onClose,
    required this.onSubmit,
    this.onHelpRequest,
    this.isCompleted = false,
    super.key,
  });

  final Challenge challenge;
  final VoidCallback onClose;
  final void Function(String code) onSubmit;

  /// Callback to request a hint from Clawd. Returns the hint text, or null
  /// if the request failed or timed out.
  final Future<String?> Function(String code)? onHelpRequest;

  /// Whether this challenge has already been completed.
  final bool isCompleted;

  @override
  State<CodeEditorPanel> createState() => _CodeEditorPanelState();
}

class _CodeEditorPanelState extends State<CodeEditorPanel> {
  late final CodeForgeWebController _controller;
  late final String _fileUri;

  static const _clawdOrange = Color(0xFFD97757);

  String? _hintText;
  bool _isRequesting = false;

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

  Future<void> _handleHelpRequest() async {
    if (_isRequesting || widget.onHelpRequest == null) return;

    setState(() => _isRequesting = true);

    final hint = await widget.onHelpRequest!(_controller.text);

    // Guard against the widget being disposed while awaiting the hint
    // (e.g. player closed the editor).
    if (!mounted) return;

    setState(() {
      _isRequesting = false;
      if (hint != null) _hintText = hint;
    });
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
                if (widget.isCompleted)
                  Container(
                    margin: const EdgeInsets.only(right: 8),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: completedGold.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: completedGold.withValues(alpha: 0.5),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.check_circle,
                          color: completedGold,
                          size: 14,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          'Completed',
                          style: TextStyle(
                            color: completedGold,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
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

          // Hint section — slides open when a hint arrives
          AnimatedSize(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeInOut,
            child: _hintText != null
                ? Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: const BoxDecoration(
                      color: Color(0xFF252525),
                      border: Border(
                        bottom: BorderSide(color: Color(0xFF3D3D3D)),
                        left: BorderSide(color: _clawdOrange, width: 3),
                      ),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                "Clawd's hint:",
                                style: TextStyle(
                                  color: _clawdOrange,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                _hintText!,
                                style: TextStyle(
                                  color: Colors.grey[300],
                                  fontSize: 13,
                                  height: 1.4,
                                ),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          onPressed: () =>
                              setState(() => _hintText = null),
                          icon: const Icon(Icons.close, size: 16),
                          color: Colors.grey[500],
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(
                            minWidth: 24,
                            minHeight: 24,
                          ),
                        ),
                      ],
                    ),
                  )
                : const SizedBox.shrink(),
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

          // Footer with help and submit buttons
          Container(
            padding: const EdgeInsets.all(16),
            decoration: const BoxDecoration(
              color: Color(0xFF2D2D2D),
              border: Border(
                top: BorderSide(color: Color(0xFF3D3D3D)),
              ),
            ),
            child: Row(
              children: [
                // Help button — left side
                if (widget.onHelpRequest != null)
                  ValueListenableBuilder<BotStatus>(
                    valueListenable: botStatusNotifier,
                    builder: (context, botStatus, _) {
                      final enabled =
                          !_isRequesting && botStatus != BotStatus.absent;
                      return TextButton.icon(
                        onPressed: enabled ? _handleHelpRequest : null,
                        icon: _isRequesting
                            ? const SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: _clawdOrange,
                                ),
                              )
                            : Icon(
                                Icons.lightbulb_outline,
                                size: 16,
                                color: enabled
                                    ? _clawdOrange
                                    : Colors.grey[600],
                              ),
                        label: Text(
                          _isRequesting
                              ? 'Clawd is coming...'
                              : "Help, I'm stuck",
                          style: TextStyle(
                            color: enabled
                                ? _clawdOrange
                                : Colors.grey[600],
                            fontSize: 13,
                          ),
                        ),
                      );
                    },
                  ),
                const Spacer(),
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
