import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:url_launcher/url_launcher.dart';

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
      spans.add(
          TextSpan(text: text.substring(last, leadStart), style: baseStyle));
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

/// A URL detected in a plain-text run: its [start]/[end] offsets within the
/// run and the [href] to open (bare `www.` links get `https://` prefixed).
typedef LinkMatch = ({int start, int end, String href});

/// Find URLs in [text]: `http(s)://…` or bare `www.…`.
///
/// Deliberately conservative about boundaries: trailing sentence punctuation
/// (`.,;:!?'"`) is not part of the link, and a trailing `)` is included only
/// when the URL body contains a matching `(` (so a parenthesized "(see
/// https://example.com)" stays clean while a Wikipedia-style
/// `…/Foo_(bar)` survives intact).
List<LinkMatch> findLinks(String text) {
  final matches = <LinkMatch>[];
  final pattern = RegExp(r'(https?://[^\s]+|www\.[^\s]+)');
  for (final m in pattern.allMatches(text)) {
    var raw = m.group(0)!;
    // Trim trailing punctuation that reads as sentence structure, not URL.
    while (raw.isNotEmpty) {
      final tail = raw[raw.length - 1];
      if ('.,;:!?\'"'.contains(tail)) {
        raw = raw.substring(0, raw.length - 1);
        continue;
      }
      if (tail == ')' &&
          ')'.allMatches(raw).length > '('.allMatches(raw).length) {
        raw = raw.substring(0, raw.length - 1);
        continue;
      }
      break;
    }
    // A bare "www." with nothing meaningful after it isn't a link.
    if (raw == 'www.' || raw.isEmpty) continue;
    final href = raw.startsWith('www.') ? 'https://$raw' : raw;
    matches.add((start: m.start, end: m.start + raw.length, href: href));
  }
  return matches;
}

/// Renders a chat message body with `@mention` highlighting AND clickable
/// links, owning the [TapGestureRecognizer] lifecycle.
///
/// Stateful because recognizers attached to [TextSpan]s are NOT disposed by
/// the framework — a stateless builder would leak one recognizer per link per
/// rebuild. This widget rebuilds its span tree (and re-mints recognizers) only
/// when the message [text] changes, and disposes every recognizer it created.
///
/// Mentions are detected first (via [buildMentionSpans]); the base-styled
/// segments between/around them are then linkified. A mention is never
/// linkified and a link never mention-styled.
class MessageText extends StatefulWidget {
  const MessageText(
    this.text, {
    required this.baseStyle,
    required this.mentionStyle,
    required this.linkStyle,
    this.onOpenLink,
    super.key,
  });

  final String text;
  final TextStyle baseStyle;
  final TextStyle mentionStyle;
  final TextStyle linkStyle;

  /// Test seam — defaults to launching the URL in a new tab/external app.
  final void Function(String href)? onOpenLink;

  @override
  State<MessageText> createState() => _MessageTextState();
}

class _MessageTextState extends State<MessageText> {
  final List<TapGestureRecognizer> _recognizers = [];
  late List<InlineSpan> _spans;

  @override
  void initState() {
    super.initState();
    _spans = _build();
  }

  @override
  void didUpdateWidget(covariant MessageText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.text != widget.text ||
        oldWidget.baseStyle != widget.baseStyle) {
      _disposeRecognizers();
      _spans = _build();
    }
  }

  @override
  void dispose() {
    _disposeRecognizers();
    super.dispose();
  }

  void _disposeRecognizers() {
    for (final r in _recognizers) {
      r.dispose();
    }
    _recognizers.clear();
  }

  void _open(String href) {
    final opener = widget.onOpenLink;
    if (opener != null) {
      opener(href);
      return;
    }
    final uri = Uri.tryParse(href);
    if (uri == null) return;
    // New tab on web; external browser elsewhere. Fire-and-forget — a failed
    // launch (popup blocker, malformed host) is not worth surfacing in-world.
    launchUrl(uri, webOnlyWindowName: '_blank');
  }

  /// Split a base-styled run into plain + link spans.
  List<InlineSpan> _linkified(String segment) {
    final links = findLinks(segment);
    if (links.isEmpty) {
      return [TextSpan(text: segment, style: widget.baseStyle)];
    }
    final out = <InlineSpan>[];
    var last = 0;
    for (final link in links) {
      if (link.start > last) {
        out.add(TextSpan(
            text: segment.substring(last, link.start),
            style: widget.baseStyle));
      }
      final recognizer = TapGestureRecognizer()..onTap = () => _open(link.href);
      _recognizers.add(recognizer);
      out.add(TextSpan(
        text: segment.substring(link.start, link.end),
        style: widget.linkStyle,
        recognizer: recognizer,
      ));
      last = link.end;
    }
    if (last < segment.length) {
      out.add(TextSpan(text: segment.substring(last), style: widget.baseStyle));
    }
    return out;
  }

  List<InlineSpan> _build() {
    final withMentions = buildMentionSpans(
      widget.text,
      baseStyle: widget.baseStyle,
      mentionStyle: widget.mentionStyle,
    );
    final out = <InlineSpan>[];
    for (final span in withMentions) {
      if (span is TextSpan &&
          span.style == widget.baseStyle &&
          span.text != null) {
        out.addAll(_linkified(span.text!));
      } else {
        out.add(span);
      }
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    return Text.rich(TextSpan(children: _spans));
  }
}
