import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:logging/logging.dart';
import 'package:tech_world/prompt/spell_school.dart';
import 'package:tech_world/spellbook/predefined_words.dart';
import 'package:tech_world/spellbook/word_of_power.dart';

final _log = Logger('SpellbookService');

/// Tracks which words of power a player has learned.
///
/// Persists to Firestore in `users/{uid}` as a `learnedWords` array.
/// Mirrors [ProgressService] — local [Set] cache for synchronous reads,
/// optimistic update with rollback on Firestore failure.
class SpellbookService {
  SpellbookService({
    required String uid,
    CollectionReference<Map<String, dynamic>>? collection,
  })  : _uid = uid,
        _collection =
            collection ?? FirebaseFirestore.instance.collection('users');

  final String _uid;
  final CollectionReference<Map<String, dynamic>> _collection;

  final Set<String> _learned = {};
  final StreamController<Set<String>> _controller =
      StreamController<Set<String>>.broadcast();

  /// Stream of learned word ids, emits after each change.
  Stream<Set<String>> get learnedWords => _controller.stream;

  /// Synchronous snapshot of learned word ids (unmodifiable).
  Set<String> get learnedWordIds => Set.unmodifiable(_learned);

  /// Number of distinct words learned.
  int get count => _learned.length;

  /// Sync check against the local cache.
  bool hasWord(String wordId) => _learned.contains(wordId);

  /// Learned [WordOfPower] grouped by school. Every school is present,
  /// even if its list is empty — UI can render full schema without
  /// null-checks.
  Map<SpellSchool, List<WordOfPower>> get wordsBySchool {
    final groups = <SpellSchool, List<WordOfPower>>{
      for (final s in SpellSchool.values) s: <WordOfPower>[],
    };
    for (final id in _learned) {
      final word = wordById[id];
      if (word != null) groups[word.school]!.add(word);
    }
    // Stable ordering inside each school: by intensity then id.
    for (final list in groups.values) {
      list.sort((a, b) {
        final byIntensity = a.intensity.compareTo(b.intensity);
        return byIntensity != 0 ? byIntensity : a.id.compareTo(b.id);
      });
    }
    return groups;
  }

  /// Load the user's learned words from Firestore.
  Future<void> loadSpellbook() async {
    try {
      final doc = await _collection.doc(_uid).get();
      final data = doc.data();
      if (data != null && data['learnedWords'] is List) {
        _learned.addAll(List<String>.from(data['learnedWords']));
      }
    } on FirebaseException catch (e) {
      _log.warning('SpellbookService: failed to load spellbook', e);
      rethrow;
    }
  }

  /// Mark a word as learned. Optimistic local update then Firestore write
  /// with [FieldValue.arrayUnion] for idempotency. Throws [ArgumentError]
  /// if [wordId] is not a known word.
  Future<void> learnWord(String wordId) async {
    if (!wordById.containsKey(wordId)) {
      throw ArgumentError.value(wordId, 'wordId', 'unknown word');
    }
    if (_learned.contains(wordId)) return;

    _learned.add(wordId);
    _controller.add(Set.unmodifiable(_learned));

    try {
      await _collection.doc(_uid).set(
        {
          'learnedWords': FieldValue.arrayUnion([wordId]),
        },
        SetOptions(merge: true),
      );
    } on FirebaseException catch (e) {
      _learned.remove(wordId);
      _controller.add(Set.unmodifiable(_learned));
      _log.warning('SpellbookService: failed to persist learnWord', e);
      rethrow;
    }
  }

  /// Clean up resources.
  void dispose() {
    _controller.close();
  }
}
