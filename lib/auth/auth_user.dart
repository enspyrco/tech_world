import 'package:tech_world_networking_types/tech_world_networking_types.dart';

class AuthUser implements User {
  AuthUser({required this.id, required this.displayName});
  @override
  final String id;
  @override
  final String displayName;
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
