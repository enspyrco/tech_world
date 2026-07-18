import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// The shared message-composer text field for group chat and DM threads.
///
/// Grows with its content — one line when empty, up to [maxLines] before
/// scrolling internally (Andy's feature request: the input "must be larger").
/// Because a multiline [TextField] swallows Enter as a newline (and never
/// fires `onSubmitted`), send-on-Enter is reimplemented at the key-event
/// layer: **Enter sends, Shift+Enter inserts a newline** — the standard chat
/// convention. During an IME composition (e.g. Japanese input) Enter is left
/// alone so it can commit the composition instead of sending.
///
/// Extracted from the previously-duplicated input rows in `chat_panel.dart`
/// and `dm_thread_view.dart` so the two composers can't drift.
class ChatComposerField extends StatelessWidget {
  const ChatComposerField({
    required this.controller,
    required this.focusNode,
    required this.enabled,
    required this.hintText,
    required this.onSend,
    this.onChanged,
    this.maxLines = 5,
    super.key,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final bool enabled;
  final String hintText;

  /// Invoked on Enter (without Shift). The caller reads the text out of
  /// [controller] itself, matching the existing `_sendMessage` shape.
  final VoidCallback onSend;

  final ValueChanged<String>? onChanged;

  /// Growth cap — beyond this the field scrolls internally.
  final int maxLines;

  bool _isEnter(KeyEvent event) =>
      event.logicalKey == LogicalKeyboardKey.enter ||
      event.logicalKey == LogicalKeyboardKey.numpadEnter;

  KeyEventResult _onKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent || !_isEnter(event)) {
      return KeyEventResult.ignored;
    }
    if (HardwareKeyboard.instance.isShiftPressed) {
      // Shift+Enter: let the TextField insert the newline.
      return KeyEventResult.ignored;
    }
    if (!controller.value.composing.isCollapsed) {
      // Mid-IME-composition: Enter commits the composition, not the message.
      return KeyEventResult.ignored;
    }
    if (!enabled) return KeyEventResult.ignored;
    onSend();
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      onKeyEvent: _onKeyEvent,
      // This Focus node is a key-event interceptor, not a focus target — the
      // inner TextField owns the real [focusNode].
      canRequestFocus: false,
      child: TextField(
        controller: controller,
        focusNode: focusNode,
        enabled: enabled,
        minLines: 1,
        maxLines: maxLines,
        keyboardType: TextInputType.multiline,
        // `send`, not `newline`: a newline action would make the mobile soft
        // keyboard's return key insert newlines and never fire onSubmitted —
        // losing keyboard-send on mobile entirely. With `send`, mobile sends
        // from the keyboard (newlines there are paste-only) while hardware
        // Shift+Enter still inserts newlines on desktop/web.
        textInputAction: TextInputAction.send,
        style: const TextStyle(color: Colors.white),
        decoration: InputDecoration(
          hintText: hintText,
          hintStyle: TextStyle(color: Colors.grey[500]),
          filled: true,
          fillColor: const Color(0xFF1E1E1E),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(24),
            borderSide: BorderSide.none,
          ),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 12,
          ),
        ),
        onChanged: onChanged,
        // Hardware Enter never reaches here (the Focus interceptor above
        // returns handled, which also preventDefaults the event on web), so
        // onSubmitted fires only for IME text-input actions — the mobile
        // soft-keyboard Send key. No double-send path exists.
        onSubmitted: enabled ? (_) => onSend() : null,
      ),
    );
  }
}
