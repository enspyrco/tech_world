import 'package:flutter_test/flutter_test.dart';
import 'package:tech_world/widgets/edit_profile_dialog.dart';

void main() {
  group('EditProfileResult', () {
    test('stores displayName', () {
      const result = EditProfileResult(displayName: 'Alice');

      expect(result.displayName, equals('Alice'));
      expect(result.profilePictureUrl, isNull);
    });

    test('stores displayName and profilePictureUrl', () {
      const result = EditProfileResult(
        displayName: 'Bob',
        profilePictureUrl: 'https://storage.example.com/photo.jpg',
      );

      expect(result.displayName, equals('Bob'));
      expect(result.profilePictureUrl,
          equals('https://storage.example.com/photo.jpg'));
    });
  });
}
