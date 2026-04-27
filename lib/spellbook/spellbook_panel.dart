import 'package:flutter/material.dart';
import 'package:tech_world/prompt/spell_school.dart';
import 'package:tech_world/spellbook/predefined_words.dart';
import 'package:tech_world/spellbook/spellbook_service.dart';
import 'package:tech_world/spellbook/word_of_power.dart';

/// Side panel showing the player's learned words of power, grouped by school.
///
/// Listens to [SpellbookService.learnedWords] so the panel updates the
/// instant a challenge passes — no manual refresh needed.
class SpellbookPanel extends StatelessWidget {
  const SpellbookPanel({
    required this.service,
    required this.onClose,
    super.key,
  });

  final SpellbookService service;
  final VoidCallback onClose;

  static const _bgColor = Color(0xEE0A0814);

  @override
  Widget build(BuildContext context) {
    return Material(
      color: _bgColor,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Header(onClose: onClose),
          Expanded(
            child: StreamBuilder<Set<WordId>>(
              stream: service.learnedWords,
              initialData: service.learnedWordIds,
              builder: (context, _) {
                // Always read groups from the service — initialData/snapshot
                // both produce id sets, but the service computes the
                // canonical sorted/grouped view in one place.
                final groups = service.wordsBySchool;
                final total = service.count;
                return ListView(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  children: [
                    _TotalCounter(total: total),
                    const SizedBox(height: 12),
                    for (final school in SpellSchool.values)
                      _SchoolSection(
                        school: school,
                        words: groups[school] ?? const [],
                      ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.onClose});
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: const BoxDecoration(
        border: Border(
          bottom: BorderSide(color: Colors.white12),
        ),
      ),
      child: Row(
        children: [
          const Icon(Icons.auto_stories,
              color: arcaneColor, size: 22),
          const SizedBox(width: 8),
          const Text(
            'Spellbook',
            style: TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w600,
            ),
          ),
          const Spacer(),
          IconButton(
            onPressed: onClose,
            icon: const Icon(Icons.close,
                color: Colors.white70, size: 20),
            tooltip: 'Close spellbook',
          ),
        ],
      ),
    );
  }
}

class _TotalCounter extends StatelessWidget {
  const _TotalCounter({required this.total});
  final int total;

  @override
  Widget build(BuildContext context) {
    return Text(
      '$total / ${allWords.length} words known',
      style: const TextStyle(
        color: Colors.white60,
        fontSize: 12,
        letterSpacing: 0.4,
      ),
    );
  }
}

class _SchoolSection extends StatelessWidget {
  const _SchoolSection({required this.school, required this.words});

  final SpellSchool school;
  final List<WordOfPower> words;

  static const _wordsPerSchool = 3;

  @override
  Widget build(BuildContext context) {
    final element = schoolElement[school]!;
    final color = _elementColor(element);
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: color,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                school.label,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                '· ${words.length}/$_wordsPerSchool',
                style: const TextStyle(
                  color: Colors.white38,
                  fontSize: 12,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (words.isEmpty)
            const Padding(
              padding: EdgeInsets.only(left: 16),
              child: Text(
                'No words yet — complete a challenge to learn one.',
                style: TextStyle(color: Colors.white30, fontSize: 12),
              ),
            )
          else
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final w in words) _WordChip(word: w, color: color),
              ],
            ),
        ],
      ),
    );
  }
}

class _WordChip extends StatelessWidget {
  const _WordChip({required this.word, required this.color});
  final WordOfPower word;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: '${word.meaning} · intensity ${word.intensity}',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.15),
          border: Border.all(color: color.withValues(alpha: 0.6)),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          word.displayName,
          style: TextStyle(
            color: color,
            fontSize: 12,
            fontWeight: FontWeight.w600,
            letterSpacing: 1.2,
          ),
        ),
      ),
    );
  }
}

Color _elementColor(SpellElement element) => switch (element) {
      SpellElement.fire => const Color(0xFFFF7043),
      SpellElement.water => const Color(0xFF42A5F5),
      SpellElement.earth => const Color(0xFF8D6E63),
      SpellElement.air => const Color(0xFFB39DDB),
      SpellElement.spirit => const Color(0xFFEEE8AA),
      SpellElement.void_ => const Color(0xFFAA44FF),
    };
