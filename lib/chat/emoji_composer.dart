import 'package:tech_world/chat/emoji_data.dart';

/// An emoji that can be inserted from the `:name` picker: its shortcode plus
/// the Unicode glyph inserted into the message text.
class EmojiCandidate {
  const EmojiCandidate({required this.name, required this.glyph});

  /// The lowercase shortcode (`fire`, `+1`) shown in the picker and matched
  /// against the active `:query`.
  final String name;

  /// The Unicode glyph inserted verbatim into the composer text.
  final String glyph;
}

/// The result of inserting a chosen emoji into the composer text: the new text
/// and the new cursor offset (in UTF-16 code units, matching [TextSelection]).
class EmojiInsertion {
  const EmojiInsertion({required this.text, required this.cursor});

  final String text;
  final int cursor;
}

/// Pure text logic for the `:name` emoji picker, factored out of the widget so
/// it is unit-testable without a running Flutter tree. Mirrors the shape of
/// `MentionComposer` (activeQuery / filter / insert) with two additions
/// specific to emoji: a shortcode lookup ([filter]) instead of a candidate
/// list, and inline auto-completion of a fully-typed `:name:` ([tryComplete]).
///
/// The `:` that opens a token must sit at the start of the text or be preceded
/// by whitespace, so `12:30` and `https://` never trigger. A token runs from
/// that `:` up to the cursor and may contain only shortcode characters
/// (`[a-z0-9_+-]`, case-insensitive) — any other character ends it.
class EmojiComposer {
  /// The active `:query` if the cursor is inside an unfinished emoji token, else
  /// null. Returns the query WITHOUT the leading `:` and the `:`'s index.
  ///
  /// The query is returned at any length; the widget layer decides how many
  /// characters are required before showing the picker (2+, so `:f` stays
  /// quiet). Returns `('', index)` for a bare `:`.
  static ({String query, int colonIndex})? activeQuery(String text, int cursor) {
    if (cursor < 0 || cursor > text.length) return null;
    var i = cursor - 1;
    while (i >= 0) {
      final ch = text[i];
      if (ch == ':') {
        // Valid only if at start or preceded by whitespace.
        if (i == 0 || _isWhitespace(text[i - 1])) {
          return (query: text.substring(i + 1, cursor), colonIndex: i);
        }
        return null;
      }
      // Anything that isn't a shortcode character ends the token unmatched —
      // this is what keeps `12:30` (a digit before the `:`) and stray
      // punctuation from ever opening the picker.
      if (!_isNameChar(ch)) return null;
      i--;
    }
    return null;
  }

  /// Shortcodes matching [query] (case-insensitive), prefix matches ranked
  /// before substring matches, each bucket sorted alphabetically for a stable
  /// order. A blank query returns nothing (the picker only opens on a real
  /// query). Capped at [limit] rows so the picker stays compact.
  static List<EmojiCandidate> filter(String query, {int limit = 30}) {
    final q = query.toLowerCase();
    if (q.isEmpty) return const [];
    final prefix = <EmojiCandidate>[];
    final contains = <EmojiCandidate>[];
    for (final entry in emojiByName.entries) {
      final name = entry.key;
      if (name.startsWith(q)) {
        prefix.add(EmojiCandidate(name: name, glyph: entry.value));
      } else if (name.contains(q)) {
        contains.add(EmojiCandidate(name: name, glyph: entry.value));
      }
    }
    prefix.sort((a, b) => a.name.compareTo(b.name));
    contains.sort((a, b) => a.name.compareTo(b.name));
    return [...prefix, ...contains].take(limit).toList();
  }

  /// Replace the active `:query` token (anchored at [colonIndex], ending at
  /// [cursor]) with the [chosen] glyph. The cursor lands just after the glyph.
  static EmojiInsertion insert({
    required String text,
    required int colonIndex,
    required int cursor,
    required EmojiCandidate chosen,
  }) {
    final before = text.substring(0, colonIndex);
    final after = text.substring(cursor);
    final glyph = chosen.glyph;
    return EmojiInsertion(
      text: '$before$glyph$after',
      cursor: before.length + glyph.length,
    );
  }

  /// If the character just before [cursor] is a closing `:` completing a known
  /// `:name:` shortcode at a word boundary, return the edit that replaces the
  /// whole `:name:` span with the glyph; otherwise null.
  ///
  /// An unknown `:name:` returns null (left untouched, per Slack), and a bare
  /// `::` returns null (empty name). This lets a user type `:fire:` and get 🔥
  /// inline without opening the picker.
  static EmojiInsertion? tryComplete(String text, int cursor) {
    // Need at least `:x:` before the cursor, and the char before it a `:`.
    if (cursor < 3 || cursor > text.length) return null;
    if (text[cursor - 1] != ':') return null;
    var i = cursor - 2;
    while (i >= 0) {
      final ch = text[i];
      if (ch == ':') {
        if (i == 0 || _isWhitespace(text[i - 1])) {
          final name = text.substring(i + 1, cursor - 1).toLowerCase();
          if (name.isEmpty) return null;
          final glyph = emojiByName[name];
          if (glyph == null) return null;
          final before = text.substring(0, i);
          final after = text.substring(cursor);
          return EmojiInsertion(
            text: '$before$glyph$after',
            cursor: before.length + glyph.length,
          );
        }
        return null;
      }
      if (!_isNameChar(ch)) return null;
      i--;
    }
    return null;
  }

  static bool _isWhitespace(String ch) =>
      ch == ' ' || ch == '\n' || ch == '\t';

  /// Shortcode characters: lowercase/uppercase letters, digits, and the `_`,
  /// `+`, `-` used by aliases like `+1` / `-1`.
  static bool _isNameChar(String ch) {
    final c = ch.codeUnitAt(0);
    return (c >= 0x30 && c <= 0x39) || // 0-9
        (c >= 0x41 && c <= 0x5A) || // A-Z
        (c >= 0x61 && c <= 0x7A) || // a-z
        ch == '_' ||
        ch == '+' ||
        ch == '-';
  }
}
