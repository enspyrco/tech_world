import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tech_world/chat/mention_text.dart';

void main() {
  group('findLinks', () {
    test('detects an https URL mid-sentence', () {
      final links = findLinks('see https://example.com/page for more');
      expect(links, hasLength(1));
      expect(links.single.href, 'https://example.com/page');
    });

    test('bare www gets https prefixed', () {
      final links = findLinks('go to www.example.com now');
      expect(links.single.href, 'https://www.example.com');
    });

    test('trailing sentence punctuation is not part of the link', () {
      expect(findLinks('read https://example.com/a.').single.href,
          'https://example.com/a');
      expect(findLinks('read https://example.com/a, then b').single.href,
          'https://example.com/a');
      expect(findLinks('really? https://example.com/a!').single.href,
          'https://example.com/a');
    });

    test('parenthesized link sheds the closing paren', () {
      expect(findLinks('(see https://example.com/a)').single.href,
          'https://example.com/a');
    });

    test('wikipedia-style balanced parens survive', () {
      expect(
          findLinks('https://en.wikipedia.org/wiki/Foo_(bar)').single.href,
          'https://en.wikipedia.org/wiki/Foo_(bar)');
    });

    test('no links in plain text or timestamps', () {
      expect(findLinks('meet at 12:30 tomorrow'), isEmpty);
      expect(findLinks('hello world'), isEmpty);
      expect(findLinks('www.'), isEmpty);
    });

    test('multiple links in one message', () {
      final links =
          findLinks('https://a.com and https://b.com are both good');
      expect(links.map((l) => l.href), ['https://a.com', 'https://b.com']);
    });
  });

  group('MessageText', () {
    const base = TextStyle(color: Colors.white, fontSize: 14);
    const mention =
        TextStyle(color: Colors.orange, fontSize: 14, fontWeight: FontWeight.w600);
    const link = TextStyle(
        color: Colors.blue, fontSize: 14, decoration: TextDecoration.underline);

    Future<Text> pump(WidgetTester tester, String text,
        {void Function(String)? onOpenLink}) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MessageText(
              text,
              baseStyle: base,
              mentionStyle: mention,
              linkStyle: link,
              onOpenLink: onOpenLink,
            ),
          ),
        ),
      );
      return tester.widget<Text>(find.byType(Text));
    }

    List<TextSpan> flatSpans(Text t) {
      final spans = <TextSpan>[];
      (t.textSpan as TextSpan).visitChildren((s) {
        if (s is TextSpan && s.text != null) spans.add(s);
        return true;
      });
      return spans;
    }

    testWidgets('link span carries link style and a tap recognizer',
        (tester) async {
      final opened = <String>[];
      final t = await pump(tester, 'go to https://example.com now',
          onOpenLink: opened.add);
      final spans = flatSpans(t);

      final linkSpan =
          spans.firstWhere((s) => s.text == 'https://example.com');
      expect(linkSpan.style, link);
      expect(linkSpan.recognizer, isA<TapGestureRecognizer>());

      (linkSpan.recognizer as TapGestureRecognizer).onTap!();
      expect(opened, ['https://example.com']);
    });

    testWidgets('mention and link coexist without cross-styling',
        (tester) async {
      final t =
          await pump(tester, '@Andy check https://example.com please');
      final spans = flatSpans(t);

      expect(spans.firstWhere((s) => s.text == '@Andy').style, mention);
      expect(spans.firstWhere((s) => s.text == 'https://example.com').style,
          link);
      // The mention was not linkified: no recognizer on it.
      expect(spans.firstWhere((s) => s.text == '@Andy').recognizer, isNull);
    });

    testWidgets('plain text has no recognizers', (tester) async {
      final t = await pump(tester, 'just words here');
      for (final s in flatSpans(t)) {
        expect(s.recognizer, isNull);
      }
    });
  });
}
