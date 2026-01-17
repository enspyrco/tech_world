import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import 'package:tech_world/auth/auth_user.dart';
import 'package:tech_world/auth/user_profile_service.dart';
import 'package:tech_world_networking_types/tech_world_networking_types.dart'
    as networking;

/// When a user signs in the [User] member is updated but the only time the
/// [authStateChanges] [Stream] emits a [User] is on
/// [FirebaseAuth.instance.authStateChanges].
/// TODO: this needs testing an more documentation.
class AuthService {
  AuthUser _user = PlaceholderUser();
  final _userProfileService = UserProfileService();

  networking.User get user => _user;
  String get userId => _user.id;
  bool get signedIn => !(_user is PlaceholderUser || _user is SignedOutUser);
  Stream<AuthUser> get authStateChanges async* {
    await for (final firebaseUser in FirebaseAuth.instance.authStateChanges()) {
      if (firebaseUser == null) {
        _user = SignedOutUser(id: _user.id, displayName: _user.displayName);
      } else {
        _user = AuthUser(
            id: firebaseUser.uid, displayName: firebaseUser.displayName ?? '');
      }
      yield _user;
    }
  }

  Future<void> sendPasswordReset({required String email}) =>
      FirebaseAuth.instance.sendPasswordResetEmail(email: email);

  Future<void> signInAnonymously() async {
    final credential = await FirebaseAuth.instance.signInAnonymously();
    if (credential.user == null) {
      _user = SignedOutUser(id: _user.id, displayName: _user.displayName);
    } else {
      _user = AuthUser(
        id: credential.user!.uid,
        displayName: credential.user!.displayName ?? '',
      );
    }
  }

  Future<void> signInWithEmailAndPassword(
      {required String email, required String password}) async {
    final credential = await FirebaseAuth.instance
        .signInWithEmailAndPassword(email: email, password: password);
    if (credential.user == null) {
      _user = SignedOutUser(id: _user.id, displayName: _user.displayName);
    } else {
      _user = AuthUser(
        id: credential.user!.uid,
        displayName: credential.user!.displayName ?? '',
      );
    }
  }

  Future<void> createUserWithEmailAndPassword(
      {required String email, required String password}) async {
    final credential = await FirebaseAuth.instance
        .createUserWithEmailAndPassword(email: email, password: password);
    if (credential.user == null) {
      _user = SignedOutUser(id: _user.id, displayName: _user.displayName);
    } else {
      _user = AuthUser(
        id: credential.user!.uid,
        displayName: credential.user!.displayName ?? '',
      );
    }
  }

  /// Sign in with Apple - requests name and email scopes.
  /// Note: Apple only provides name/email on FIRST sign-in, so we must
  /// update the Firebase user profile immediately.
  Future<void> signInWithApple() async {
    // Generate a random nonce for security
    final rawNonce = _generateNonce();
    final nonce = _sha256ofString(rawNonce);

    // Request Apple credential with name and email scopes
    final appleCredential = await SignInWithApple.getAppleIDCredential(
      scopes: [
        AppleIDAuthorizationScopes.email,
        AppleIDAuthorizationScopes.fullName,
      ],
      nonce: nonce,
    );

    // Create OAuth credential for Firebase
    final oauthCredential = OAuthProvider('apple.com').credential(
      idToken: appleCredential.identityToken,
      rawNonce: rawNonce,
    );

    // Sign in to Firebase
    final credential =
        await FirebaseAuth.instance.signInWithCredential(oauthCredential);

    if (credential.user == null) {
      _user = SignedOutUser(id: _user.id, displayName: _user.displayName);
      return;
    }

    // Apple only provides name on first sign-in, so save it to Firebase profile AND Firestore
    final givenName = appleCredential.givenName;
    final familyName = appleCredential.familyName;
    String displayName = '';

    if (givenName != null || familyName != null) {
      displayName = [givenName, familyName]
          .where((s) => s != null && s.isNotEmpty)
          .join(' ');
      if (displayName.isNotEmpty) {
        await credential.user!.updateDisplayName(displayName);
        // Reload to get updated profile
        await credential.user!.reload();
      }
    }

    final firebaseUser = FirebaseAuth.instance.currentUser!;

    // Save to Firestore (this persists even if Apple doesn't provide name again)
    await _userProfileService.saveUserProfile(
      uid: firebaseUser.uid,
      displayName:
          displayName.isNotEmpty ? displayName : firebaseUser.displayName,
      email: appleCredential.email ?? firebaseUser.email,
    );

    // If we don't have a display name from Apple or Firebase, try Firestore
    String finalDisplayName = firebaseUser.displayName ?? '';
    if (finalDisplayName.isEmpty) {
      finalDisplayName =
          await _userProfileService.getDisplayName(firebaseUser.uid);
    }

    _user = AuthUser(
      id: firebaseUser.uid,
      displayName: finalDisplayName,
    );
  }

  /// Sign in with Google - works on Android, iOS, macOS, and Web.
  /// Uses google_sign_in 7.x API with singleton pattern.
  Future<void> signInWithGoogle() async {
    final signIn = GoogleSignIn.instance;

    // Initialize if not already done (safe to call multiple times)
    await signIn.initialize();

    // Trigger the authentication flow
    // In google_sign_in 7.x, cancellation throws GoogleSignInCanceledException
    final googleUser = await signIn.authenticate();

    // Get the ID token from authentication (access token is now separate)
    final googleAuth = googleUser.authentication;

    // Create a new credential using ID token
    // Note: accessToken is optional for Firebase Auth
    final credential = GoogleAuthProvider.credential(
      idToken: googleAuth.idToken,
    );

    // Sign in to Firebase
    final userCredential =
        await FirebaseAuth.instance.signInWithCredential(credential);

    if (userCredential.user == null) {
      _user = SignedOutUser(id: _user.id, displayName: _user.displayName);
      return;
    }

    final firebaseUser = userCredential.user!;

    // Save to Firestore
    await _userProfileService.saveUserProfile(
      uid: firebaseUser.uid,
      displayName: firebaseUser.displayName,
      email: firebaseUser.email,
    );

    _user = AuthUser(
      id: firebaseUser.uid,
      displayName: firebaseUser.displayName ?? '',
    );
  }

  /// Generates a random nonce string.
  String _generateNonce([int length = 32]) {
    const charset =
        '0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._';
    final random = Random.secure();
    return List.generate(length, (_) => charset[random.nextInt(charset.length)])
        .join();
  }

  /// Returns the SHA256 hash of the input string.
  String _sha256ofString(String input) {
    final bytes = utf8.encode(input);
    final digest = sha256.convert(bytes);
    return digest.toString();
  }
}
