/// Base interface for user identity.
abstract class User {
  abstract final String id;
  abstract final String displayName;
}

class AuthUser implements User {
  AuthUser({required this.id, required this.displayName});
  @override
  final String id;
  @override
  final String displayName;

  @override
  bool operator ==(Object other) => other is User && other.id == id;

  @override
  int get hashCode => id.hashCode;
}

/// Holds the details of the [AuthUser] that has signed out so the [id] can be used
/// by the [NetworkingService] to update the server's game model.
class SignedOutUser extends AuthUser {
  SignedOutUser({required super.id, required super.displayName});
}

/// Rather than a nullable authUser member we use a specific type to indicate the
/// signed in state has not yet been determined.
class PlaceholderUser extends AuthUser {
  PlaceholderUser({super.id = '', super.displayName = ''});
}
