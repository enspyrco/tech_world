import 'package:flutter/widgets.dart';

/// Builds a [TextSpan] tree that highlights `@Name` mention spans within a chat
/// message body, used by both the group panel and the DM thread view so the two
/// render mentions identically.
///
/// A mention span is an `@` that is at the start of the text or preceded by
/// whitespace, followed by one or more non-whitespace characters. This is a
/// DISPLAY-ONLY treatment — the inline `@Name` text is never a trust anchor for
/// the world beacon (that is the structured `mentions` UID list). Highlighting
/// here is purely cosmetic and is intentionally permissive: it styles whatever
/// looks like a mention, even if the name doesn't resolve to a participant.
List<InlineSpan> buildMentionSpans(
  String text, {
  required TextStyle baseStyle,
  required TextStyle mentionStyle,
}) {
  final spans = <InlineSpan>[];
  final pattern = RegExp(r'(^|\s)(@[^\s]+)');
  var last = 0;

  for (final m in pattern.allMatches(text)) {
    // Leading whitespace (capture group 1) stays in the base run.
    final leadStart = m.start;
    final mentionStart = m.start + (m.group(1)?.length ?? 0);

    if (leadStart > last) {
      spans.add(TextSpan(text: text.substring(last, leadStart), style: baseStyle));
    }
    final lead = m.group(1) ?? '';
    if (lead.isNotEmpty) {
      spans.add(TextSpan(text: lead, style: baseStyle));
    }
    spans.add(TextSpan(text: m.group(2), style: mentionStyle));
    last = mentionStart + (m.group(2)?.length ?? 0);
  }

  if (last < text.length) {
    spans.add(TextSpan(text: text.substring(last), style: baseStyle));
  }
  return spans;
}
