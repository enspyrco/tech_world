import 'package:flutter/material.dart';
import 'package:tech_world/chat/emoji_composer.dart';

/// A compact, filterable list of emoji shown above the composer while the user
/// is typing a `:name` shortcode. Tapping a row inserts the glyph (see
/// `_pickEmoji` in the group + DM composers). Public (unlike `_MentionPicker`)
/// so both `chat_panel.dart` and `dm_thread_view.dart` share one widget.
class EmojiPicker extends StatelessWidget {
  const EmojiPicker({
    required this.candidates,
    required this.onPick,
    required this.accentColor,
    super.key,
  });

  final List<EmojiCandidate> candidates;
  final ValueChanged<EmojiCandidate> onPick;
  final Color accentColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(maxHeight: 180),
      decoration: const BoxDecoration(
        color: Color(0xFF252525),
        border: Border(top: BorderSide(color: Color(0xFF3D3D3D))),
      ),
      child: ListView.builder(
        shrinkWrap: true,
        padding: EdgeInsets.zero,
        itemCount: candidates.length,
        itemBuilder: (context, i) {
          final c = candidates[i];
          return InkWell(
            onTap: () => onPick(c),
            child: Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  Text(c.glyph, style: const TextStyle(fontSize: 20)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      ':${c.name}:',
                      style: const TextStyle(color: Colors.white, fontSize: 14),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
