import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tech_world/chat/mention_text.dart';

void main() {
  const base = TextStyle(color: Color(0xFFFFFFFF));
  const mention = TextStyle(color: Color(0xFFFFC247));

  List<InlineSpan> spansFor(String t) =>
      buildMentionSpans(t, baseStyle: base, mentionStyle: mention);

  // Flatten to (text, isMention) pairs for assertions.
  List<({String text, bool isMention})> flat(String t) => spansFor(t)
      .whereType<TextSpan>()
      .map((s) => (text: s.text ?? '', isMention: s.style == mention))
      .toList();

  test('plain text has no mention spans', () {
    final f = flat('hello world');
    expect(f.where((s) => s.isMention), isEmpty);
    expect(f.map((s) => s.text).join(), equals('hello world'));
  });

  test('highlights an @mention mid-sentence', () {
    final f = flat('hey @Alice how are you');
    final mentions = f.where((s) => s.isMention).map((s) => s.text).toList();
    expect(mentions, equals(['@Alice']));
    // Round-trips to the original text.
    expect(f.map((s) => s.text).join(), equals('hey @Alice how are you'));
  });

  test('highlights an @mention at the start', () {
    final f = flat('@Bob hi');
    expect(f.first.isMention, isTrue);
    expect(f.first.text, equals('@Bob'));
  });

  test('does not highlight an email-like @', () {
    final f = flat('email me@host.com please');
    expect(f.where((s) => s.isMention), isEmpty);
  });

  test('highlights multiple mentions', () {
    final f = flat('@Alice and @Bob');
    expect(
      f.where((s) => s.isMention).map((s) => s.text),
      equals(['@Alice', '@Bob']),
    );
    expect(f.map((s) => s.text).join(), equals('@Alice and @Bob'));
  });
}
