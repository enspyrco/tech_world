import 'package:firebase_auth/firebase_auth.dart' show FirebaseAuth;
import 'package:tech_world/auth/user.dart';
import 'package:tech_world_networking_types/tech_world_networking_types.dart';

/// When a user signs in the [User] member is updated but the only time the
/// [authStateChanges] [Stream] emits a [User] is on
/// [FirebaseAuth.instance.authStateChanges].
/// TODO: this needs testing an more documentation.
class AuthService {
  AuthUser _user = PlaceholderUser();

  User get user => _user;
  String get userId => _user.id;
  bool get signedIn => !(_user is PlaceholderUser || _user is SignedOutUser);

  Future<void> sendPasswordReset({required String email}) =>
      FirebaseAuth.instance.sendPasswordResetEmail(email: email);

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
}
