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
      data['displayNameLower'] = displayName.toLowerCase();
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
      avatarId: data['avatarId'] as String?,
      profilePictureUrl: data['profilePictureUrl'] as String?,
    );
  }

  /// Get the display name for a user, first checking Firestore,
  /// then falling back to the provided fallback.
  Future<String> getDisplayName(String uid, {String fallback = ''}) async {
    final profile = await getUserProfile(uid);
    return profile?.displayName ?? fallback;
  }

  /// Save the chosen avatar ID to the user's profile.
  Future<void> saveAvatarId(String uid, String avatarId) async {
    await _collection.doc(uid).set(
      {
        'avatarId': avatarId,
        'updatedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
  }

  /// Get the saved avatar ID for a user, or null if none saved.
  Future<String?> getAvatarId(String uid) async {
    final profile = await getUserProfile(uid);
    return profile?.avatarId;
  }

  /// Save a profile picture URL to the user's profile.
  Future<void> saveProfilePictureUrl(String uid, String url) async {
    await _collection.doc(uid).set(
      {
        'profilePictureUrl': url,
        'updatedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
  }
  /// Search users by display name prefix (case-insensitive).
  ///
  /// Uses the `displayNameLower` field for matching. Returns up to [limit]
  /// results. Users without a `displayNameLower` field won't appear in results
  /// until their profile is next saved.
  Future<List<UserProfile>> searchUsers(
    String query, {
    int limit = 20,
  }) async {
    if (query.isEmpty) return [];
    final lower = query.toLowerCase();
    final snapshot = await _collection
        .orderBy('displayNameLower')
        .startAt([lower])
        .endAt(['$lower\uf8ff'])
        .limit(limit)
        .get();
    return snapshot.docs.map(_profileFromDoc).toList();
  }

  /// Fetch profiles for a list of UIDs.
  ///
  /// Firestore `whereIn` supports max 30 values per query, so this method
  /// chunks the list automatically for larger sets.
  Future<List<UserProfile>> getUserProfiles(List<String> uids) async {
    if (uids.isEmpty) return [];
    final results = <UserProfile>[];
    // Firestore whereIn limit is 30.
    for (var i = 0; i < uids.length; i += 30) {
      final chunk = uids.sublist(i, i + 30 > uids.length ? uids.length : i + 30);
      final snapshot = await _collection
          .where(FieldPath.documentId, whereIn: chunk)
          .get();
      results.addAll(snapshot.docs.map(_profileFromDoc));
    }
    return results;
  }

  UserProfile _profileFromDoc(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data();
    return UserProfile(
      uid: doc.id,
      displayName: data['displayName'] as String?,
      email: data['email'] as String?,
      avatarId: data['avatarId'] as String?,
      profilePictureUrl: data['profilePictureUrl'] as String?,
    );
  }
}

/// User profile data stored in Firestore.
class UserProfile {
  const UserProfile({
    required this.uid,
    this.displayName,
    this.email,
    this.avatarId,
    this.profilePictureUrl,
  });

  final String uid;
  final String? displayName;
  final String? email;
  final String? avatarId;
  final String? profilePictureUrl;
}
