import 'package:cloud_firestore/cloud_firestore.dart';

/// Service to store and retrieve user profile data from Firestore.
/// This is used as a backup for display names since Apple only provides
/// the name on the first sign-in.
class UserProfileService {
  UserProfileService({CollectionReference<Map<String, dynamic>>? collection})
      : _collection =
            collection ?? FirebaseFirestore.instance.collection('users');

  final CollectionReference<Map<String, dynamic>> _collection;

  /// Save user profile to Firestore.
  /// Only updates fields that are non-empty to avoid overwriting existing data.
  Future<void> saveUserProfile({
    required String uid,
    String? displayName,
    String? email,
  }) async {
    final data = <String, dynamic>{
      'updatedAt': FieldValue.serverTimestamp(),
    };

    if (displayName != null && displayName.isNotEmpty) {
      data['displayName'] = displayName;
    }
    if (email != null && email.isNotEmpty) {
      data['email'] = email;
    }

    // Use set with merge to avoid overwriting existing fields
    await _collection.doc(uid).set(data, SetOptions(merge: true));
  }

  /// Get user profile from Firestore.
  /// Returns null if the user doesn't exist.
  Future<UserProfile?> getUserProfile(String uid) async {
    final doc = await _collection.doc(uid).get();
    if (!doc.exists) return null;

    final data = doc.data();
    if (data == null) return null;

    return UserProfile(
      uid: uid,
      displayName: data['displayName'] as String?,
      email: data['email'] as String?,
    );
  }

  /// Get the display name for a user, first checking Firestore,
  /// then falling back to the provided fallback.
  Future<String> getDisplayName(String uid, {String fallback = ''}) async {
    final profile = await getUserProfile(uid);
    return profile?.displayName ?? fallback;
  }
}

/// User profile data stored in Firestore.
class UserProfile {
  const UserProfile({
    required this.uid,
    this.displayName,
    this.email,
  });

  final String uid;
  final String? displayName;
  final String? email;
}
