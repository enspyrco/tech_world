/// Base interface for user identity.
///
/// Implemented by [AuthUser] (sealed auth hierarchy) and by Flame
/// components like `PlayerComponent` that carry a user identity but
/// are not auth states.
abstract interface class User {
  String get id;
  String get displayName;
}

/// Sealed user-identity hierarchy — a 3-summand coproduct.
///
/// Using `sealed` gives exhaustive `switch` on auth state and closes the
/// hierarchy so no external code can extend it.
sealed class AuthUser implements User {
  const AuthUser({required this.id, required this.displayName});

  @override
  final String id;
  @override
  final String displayName;

  @override
  bool operator ==(Object other) => other is AuthUser && other.id == id;

  @override
  int get hashCode => id.hashCode;
}

/// A fully authenticated user (Firebase Auth).
final class SignedInUser extends AuthUser {
  const SignedInUser({
    required super.id,
    required super.displayName,
    this.isAnonymous = false,
  });

  /// Whether this user signed in anonymously (guest mode).
  final bool isAnonymous;
}

/// Holds the details of the user that has signed out so the [id] can be used
/// by the [NetworkingService] to update the server's game model.
final class SignedOutUser extends AuthUser {
  const SignedOutUser({required super.id, required super.displayName});
}

/// Rather than a nullable authUser member we use a specific type to indicate the
/// signed in state has not yet been determined.
final class PlaceholderUser extends AuthUser {
  const PlaceholderUser({super.id = '', super.displayName = ''});
}
