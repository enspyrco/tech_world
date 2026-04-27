import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:logging/logging.dart';
import 'package:tech_world/prompt/spell_school.dart';
import 'package:tech_world/spellbook/predefined_words.dart';
import 'package:tech_world/spellbook/word_of_power.dart';

final _log = Logger('SpellbookService');

/// Tracks which words of power a player has learned.
///
/// Persists to Firestore in `users/{uid}` as a `learnedWords` array of
/// strings (the wire format). Internally everything operates on
/// strongly-typed [WordId] values — strings only appear at the
/// Firestore boundary in [loadSpellbook] (parse via [WordId.parse]) and
/// [learnWord] (serialize via `wordId.name`).
///
/// Mirrors `ProgressService`'s shape — local cache for synchronous
/// reads, optimistic update with rollback on Firestore failure.
class SpellbookService {
  SpellbookService({
    required String uid,
    CollectionReference<Map<String, dynamic>>? collection,
  })  : _uid = uid,
        _collection =
            collection ?? FirebaseFirestore.instance.collection('users');

  final String _uid;
  final CollectionReference<Map<String, dynamic>> _collection;

  final Set<WordId> _learned = {};
  final StreamController<Set<WordId>> _controller =
      StreamController<Set<WordId>>.broadcast();

  /// Memoized [wordsBySchool] result — invalidated by [_invalidate]
  /// whenever [_learned] changes.
  Map<SpellSchool, List<WordOfPower>>? _cachedGroups;

  /// Stream of learned word ids, emits after each change.
  Stream<Set<WordId>> get learnedWords => _controller.stream;

  /// Synchronous snapshot of learned word ids (unmodifiable).
  Set<WordId> get learnedWordIds => Set.unmodifiable(_learned);

  /// Number of distinct words learned.
  int get count => _learned.length;

  /// Sync check against the local cache.
  bool hasWord(WordId word) => _learned.contains(word);

  /// Learned [WordOfPower] grouped by school. Every school is present,
  /// even if its list is empty — UI can render full schema without
  /// null-checks. Memoized; the cache is invalidated whenever the
  /// learned set changes.
  Map<SpellSchool, List<WordOfPower>> get wordsBySchool {
    final cached = _cachedGroups;
    if (cached != null) return cached;
    final groups = <SpellSchool, List<WordOfPower>>{
      for (final s in SpellSchool.values) s: <WordOfPower>[],
    };
    for (final id in _learned) {
      // wordById is total over WordId.values, so the lookup never fails.
      final word = wordById[id]!;
      groups[word.school]!.add(word);
    }
    // Stable ordering inside each school: by intensity then enum index.
    for (final list in groups.values) {
      list.sort((a, b) {
        final byIntensity = a.intensity.compareTo(b.intensity);
        return byIntensity != 0
            ? byIntensity
            : a.id.index.compareTo(b.id.index);
      });
    }
    return _cachedGroups = groups;
  }

  void _invalidate() => _cachedGroups = null;

  /// Load the user's learned words from Firestore.
  ///
  /// Wire-format strings that don't match any [WordId] are logged and
  /// skipped — protects against forward incompatibility (admin tools,
  /// future words written by a newer client) without crashing the load.
  Future<void> loadSpellbook() async {
    try {
      final doc = await _collection.doc(_uid).get();
      final data = doc.data();
      if (data != null && data['learnedWords'] is List) {
        for (final raw in List<dynamic>.from(data['learnedWords'])) {
          if (raw is! String) continue;
          final word = WordId.parse(raw);
          if (word == null) {
            _log.warning(
                'SpellbookService: ignoring unknown wire-format word "$raw" '
                'for uid $_uid');
            continue;
          }
          _learned.add(word);
        }
        _invalidate();
      }
    } on FirebaseException catch (e) {
      _log.warning('SpellbookService: failed to load spellbook', e);
      rethrow;
    }
  }

  /// Mark a word as learned. Optimistic local update then Firestore
  /// write with [FieldValue.arrayUnion] for idempotency.
  Future<void> learnWord(WordId word) async {
    if (_learned.contains(word)) return;

    _learned.add(word);
    _invalidate();
    _controller.add(Set.unmodifiable(_learned));

    try {
      await _collection.doc(_uid).set(
        {
          'learnedWords': FieldValue.arrayUnion([word.name]),
        },
        SetOptions(merge: true),
      );
    } on FirebaseException catch (e) {
      _learned.remove(word);
      _invalidate();
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
