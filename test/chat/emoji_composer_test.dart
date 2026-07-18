import 'package:flutter_test/flutter_test.dart';
import 'package:tech_world/chat/emoji_composer.dart';
import 'package:tech_world/chat/emoji_data.dart';

void main() {
  group('activeQuery', () {
    test('detects a partial :query at end of text', () {
      final q = EmojiComposer.activeQuery('hey :fi', 7);
      expect(q, isNotNull);
      expect(q!.query, equals('fi'));
      expect(q.colonIndex, equals(4));
    });

    test(': at the very start is valid', () {
      final q = EmojiComposer.activeQuery(':fire', 5);
      expect(q!.query, equals('fire'));
      expect(q.colonIndex, equals(0));
    });

    test('a bare : reports an empty query (widget gates on length)', () {
      final q = EmojiComposer.activeQuery('hey :', 5);
      expect(q, isNotNull);
      expect(q!.query, equals(''));
    });

    test('a timestamp like 12:30 does NOT trigger (digit before colon)', () {
      expect(EmojiComposer.activeQuery('12:30', 5), isNull);
    });

    test('a URL like https:// does NOT trigger', () {
      expect(EmojiComposer.activeQuery('https://', 8), isNull);
      // Cursor mid-scheme, right after the colon.
      expect(EmojiComposer.activeQuery('https://x', 6), isNull);
    });

    test('a colon mid-word (foo:bar) does NOT trigger', () {
      expect(EmojiComposer.activeQuery('foo:bar', 7), isNull);
    });

    test('whitespace after the token ends it', () {
      expect(EmojiComposer.activeQuery(':fire ', 6), isNull);
    });

    test('cursor before the : is not in the token', () {
      expect(EmojiComposer.activeQuery('hey :fi', 2), isNull);
    });

    test('cursor mid-token reports the query up to the cursor only', () {
      // "hey :fire" with cursor after ":fi".
      final q = EmojiComposer.activeQuery('hey :fire', 7);
      expect(q!.query, equals('fi'));
    });

    test('alias chars +/- are valid token chars (:+1)', () {
      final q = EmojiComposer.activeQuery(':+1', 3);
      expect(q!.query, equals('+1'));
      expect(q.colonIndex, equals(0));
    });
  });

  group('filter', () {
    test('blank query returns nothing', () {
      expect(EmojiComposer.filter(''), isEmpty);
    });

    test('prefix matches rank before substring matches', () {
      // "fire" is a prefix match; "campfire"/"fireworks" contain it. A prefix
      // match must come before any pure-substring match.
      final r = EmojiComposer.filter('fire');
      expect(r, isNotEmpty);
      // First result is a prefix match (name starts with "fire").
      expect(r.first.name.startsWith('fire'), isTrue);
    });

    test('case-insensitive', () {
      final lower = EmojiComposer.filter('fire');
      final upper = EmojiComposer.filter('FIRE');
      expect(upper.map((c) => c.name), equals(lower.map((c) => c.name)));
    });

    test('resolves a known shortcode to its glyph', () {
      final r = EmojiComposer.filter('fire');
      final fire = r.firstWhere((c) => c.name == 'fire');
      expect(fire.glyph, equals('🔥'));
    });

    test('unknown query returns empty', () {
      expect(EmojiComposer.filter('zzzznotanemoji'), isEmpty);
    });

    test('respects the limit', () {
      // A very common substring; cap keeps the picker compact.
      final r = EmojiComposer.filter('a', limit: 5);
      expect(r.length, lessThanOrEqualTo(5));
    });
  });

  group('insert', () {
    test('replaces the :query token with the glyph, cursor after it', () {
      final ins = EmojiComposer.insert(
        text: 'hey :fi',
        colonIndex: 4,
        cursor: 7,
        chosen: const EmojiCandidate(name: 'fire', glyph: '🔥'),
      );
      expect(ins.text, equals('hey 🔥'));
      expect(ins.cursor, equals('hey 🔥'.length));
    });

    test('preserves text after the cursor', () {
      final ins = EmojiComposer.insert(
        text: 'hey :fi there',
        colonIndex: 4,
        cursor: 7,
        chosen: const EmojiCandidate(name: 'fire', glyph: '🔥'),
      );
      expect(ins.text, equals('hey 🔥 there'));
    });
  });

  group('tryComplete', () {
    test('a closed :fire: auto-completes to the glyph inline', () {
      final ins = EmojiComposer.tryComplete('hey :fire:', 10);
      expect(ins, isNotNull);
      expect(ins!.text, equals('hey 🔥'));
      expect(ins.cursor, equals('hey 🔥'.length));
    });

    test(':name: at the very start completes', () {
      final ins = EmojiComposer.tryComplete(':fire:', 6);
      expect(ins!.text, equals('🔥'));
    });

    test('an unknown :name: is left untouched', () {
      expect(EmojiComposer.tryComplete('hey :notareal:', 14), isNull);
    });

    test('a bare :: does not complete', () {
      expect(EmojiComposer.tryComplete('hey ::', 6), isNull);
    });

    test('preserves text after the closing colon', () {
      final ins = EmojiComposer.tryComplete('a :fire: b', 8);
      expect(ins!.text, equals('a 🔥 b'));
    });

    test('case-insensitive shortcode match', () {
      final ins = EmojiComposer.tryComplete(':FIRE:', 6);
      expect(ins!.text, equals('🔥'));
    });

    test('an opening colon mid-word does not complete (URL-safe)', () {
      // "http://x:" — the inner colon is preceded by a letter, no boundary.
      expect(EmojiComposer.tryComplete('http://x:', 9), isNull);
    });
  });

  group('emoji_data', () {
    test('all glyphs are non-empty and names lowercase', () {
      for (final entry in emojiByName.entries) {
        expect(entry.key, equals(entry.key.toLowerCase()),
            reason: 'shortcode ${entry.key} must be lowercase');
        expect(entry.value, isNotEmpty,
            reason: 'glyph for ${entry.key} must be non-empty');
      }
    });

    test('the documented common shortcodes are present', () {
      const required = [
        'smile', 'grin', 'joy', 'heart', 'fire', 'rocket', 'tada',
        'thumbsup', '+1', 'thumbsdown', '-1', 'eyes', 'thinking', 'wave',
        'clap', 'pray', 'muscle', 'bug', 'sparkles', 'check',
        'white_check_mark', 'x', 'warning', 'question', 'zap', 'star', '100',
        'robot', 'dragon', 'ghost', 'coffee', 'pizza', 'party',
      ];
      for (final name in required) {
        expect(emojiByName.containsKey(name), isTrue,
            reason: 'expected shortcode :$name: to exist');
      }
    });
  });
}
