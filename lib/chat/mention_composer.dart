/// A participant that can be `@mention`ed: a stable UID plus a display name.
class MentionCandidate {
  const MentionCandidate({required this.uid, required this.displayName});

  /// The participant's stable UID (LiveKit identity) — the trust anchor that
  /// rides the wire as the structured `mentions` entry.
  final String uid;

  /// The cosmetic name shown in the picker and inserted as `@displayName`.
  final String displayName;
}

/// The result of inserting a chosen mention into the composer text: the new
/// text, the new cursor offset, and the UID to record so the structured
/// `mentions` list can be built at send time.
class MentionInsertion {
  const MentionInsertion({
    required this.text,
    required this.cursor,
    required this.uid,
  });

  final String text;
  final int cursor;
  final String uid;
}

/// Pure text logic for the `@mention` picker, factored out of the widget so it
/// is unit-testable without a running Flutter tree.
///
/// The widget feeds it the current text + cursor; it reports the active `@`
/// query (if the cursor sits in an unfinished `@token`), filters candidates,
/// and computes the text/cursor edit when a candidate is chosen. The display
/// name is inserted as `@Name `; the UID is reported separately so the caller
/// can map inserted spans back to UIDs for the structured wire list.
class MentionComposer {
  /// The active `@query` if the cursor is inside an unfinished mention token,
  /// else null. A mention token starts at an `@` that is at the start of the
  /// text or preceded by whitespace, and runs up to the cursor with no
  /// whitespace in between. Returns the lowercase query WITHOUT the `@`.
  ///
  /// Returns `('', start)` for a bare `@` (show all candidates).
  static ({String query, int atIndex})? activeQuery(String text, int cursor) {
    if (cursor < 0 || cursor > text.length) return null;
    // Walk back from the cursor to find an `@` with no intervening whitespace.
    var i = cursor - 1;
    while (i >= 0) {
      final ch = text[i];
      if (ch == '@') {
        // Valid only if at start or preceded by whitespace.
        if (i == 0 || _isWhitespace(text[i - 1])) {
          return (query: text.substring(i + 1, cursor), atIndex: i);
        }
        return null;
      }
      if (_isWhitespace(ch)) return null;
      i--;
    }
    return null;
  }

  /// Candidates whose display name contains [query] (case-insensitive),
  /// preserving the input order. A blank query returns all candidates.
  static List<MentionCandidate> filter(
    List<MentionCandidate> candidates,
    String query,
  ) {
    if (query.isEmpty) return List.of(candidates);
    final q = query.toLowerCase();
    return candidates
        .where((c) => c.displayName.toLowerCase().contains(q))
        .toList();
  }

  /// Replace the active `@query` token (anchored at [atIndex], ending at
  /// [cursor]) with `@displayName ` and report the [chosen]'s UID. The trailing
  /// space lets the user keep typing after the mention.
  static MentionInsertion insert({
    required String text,
    required int atIndex,
    required int cursor,
    required MentionCandidate chosen,
  }) {
    final before = text.substring(0, atIndex);
    final after = text.substring(cursor);
    final inserted = '@${chosen.displayName} ';
    final newText = '$before$inserted$after';
    return MentionInsertion(
      text: newText,
      cursor: before.length + inserted.length,
      uid: chosen.uid,
    );
  }

  /// Given the final message text and the set of (displayName → uid) pairs the
  /// user picked while composing, return the UIDs whose `@displayName` token
  /// still survives in the text. This keeps the structured `mentions` list
  /// honest if the user deleted a mention after inserting it.
  ///
  /// Matching is on the literal `@displayName` token bounded by start/whitespace
  /// and whitespace/end — the display name is cosmetic, but its presence is the
  /// signal that the user still intends that mention.
  static List<String> survivingUids(
    String text,
    List<MentionCandidate> picked,
  ) {
    final result = <String>[];
    final seen = <String>{};
    for (final cand in picked) {
      if (seen.contains(cand.uid)) continue;
      if (_containsMentionToken(text, cand.displayName)) {
        result.add(cand.uid);
        seen.add(cand.uid);
      }
    }
    return result;
  }

  static bool _containsMentionToken(String text, String displayName) {
    final token = '@$displayName';
    var from = 0;
    while (true) {
      final idx = text.indexOf(token, from);
      if (idx < 0) return false;
      final atStart = idx == 0 || _isWhitespace(text[idx - 1]);
      final endIdx = idx + token.length;
      final atEnd = endIdx == text.length || _isWhitespace(text[endIdx]);
      if (atStart && atEnd) return true;
      from = idx + 1;
    }
  }

  static bool _isWhitespace(String ch) =>
      ch == ' ' || ch == '\n' || ch == '\t';
}
