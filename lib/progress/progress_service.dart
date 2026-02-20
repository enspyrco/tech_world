import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

/// Tracks which coding challenges a player has completed.
///
/// Persists to Firestore in the `users/{uid}` document as a
/// `completedChallenges` array field. Keeps a local [Set] cache for
/// synchronous reads (terminals render every frame).
class ProgressService {
  ProgressService({
    required String uid,
    CollectionReference<Map<String, dynamic>>? collection,
  })  : _uid = uid,
        _collection =
            collection ?? FirebaseFirestore.instance.collection('users');

  final String _uid;
  final CollectionReference<Map<String, dynamic>> _collection;

  final Set<String> _completed = {};
  final StreamController<Set<String>> _controller =
      StreamController<Set<String>>.broadcast();

  /// Stream of completed challenge IDs, emits after each change.
  Stream<Set<String>> get completedChallenges => _controller.stream;

  /// Load the user's completed challenges from Firestore.
  ///
  /// Logs and rethrows on Firestore errors so callers can handle failure
  /// (e.g. show a retry prompt).
  Future<void> loadProgress() async {
    try {
      final doc = await _collection.doc(_uid).get();
      final data = doc.data();
      if (data != null && data['completedChallenges'] is List) {
        _completed.addAll(List<String>.from(data['completedChallenges']));
      }
    } on FirebaseException catch (e) {
      debugPrint('ProgressService: Failed to load progress: $e');
      rethrow;
    }
  }

  /// Mark a challenge as completed. Optimistic local update then Firestore
  /// write with [FieldValue.arrayUnion] for idempotency.
  ///
  /// If the Firestore write fails the local cache is rolled back and
  /// the error is rethrown.
  Future<void> markChallengeCompleted(String challengeId) async {
    if (_completed.contains(challengeId)) return;

    // Optimistic local update.
    _completed.add(challengeId);
    _controller.add(Set.unmodifiable(_completed));

    try {
      await _collection.doc(_uid).set(
        {
          'completedChallenges': FieldValue.arrayUnion([challengeId]),
        },
        SetOptions(merge: true),
      );
    } on FirebaseException catch (e) {
      // Rollback the optimistic update.
      _completed.remove(challengeId);
      _controller.add(Set.unmodifiable(_completed));
      debugPrint('ProgressService: Failed to persist completion: $e');
      rethrow;
    }
  }

  /// Synchronous check against the local cache.
  bool isChallengeCompleted(String challengeId) =>
      _completed.contains(challengeId);

  /// Number of challenges the player has completed.
  int get completedCount => _completed.length;

  /// Clean up resources.
  void dispose() {
    _controller.close();
  }
}
