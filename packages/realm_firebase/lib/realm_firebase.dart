/// Firebase-backed implementations of Realm engine interfaces.
///
/// Plugin package skeleton (migration step 2). `FirebaseAuthProvider`,
/// `FirestoreRoomConfigStore`, and `FirebaseStorageProvider` land in step 4,
/// once the engine interfaces exist (step 3). See `packages/realm/DESIGN.md`.
///
/// Dependency direction is load-bearing: this package will depend on `realm`
/// and `firebase_*`; `realm` must NEVER depend on `firebase_core` (the
/// engine-package deps whitelist, enforced in CI at step 4, guards this).
library;
