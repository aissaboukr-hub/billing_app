import 'dart:io';

import 'package:billing_app/core/data/hive_database.dart';
import 'package:billing_app/features/auth/data/auth_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

// These tests exercise AuthService against a real (temporary, on-disk) Hive
// box rather than mocking Hive, since AuthService's contract IS "reads and
// writes users/session correctly from the settings box".
void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('auth_service_test_');
    Hive.init(tempDir.path);
    await Hive.openBox(HiveDatabase.settingsBoxName);
  });

  tearDown(() async {
    await Hive.deleteBoxFromDisk(HiveDatabase.settingsBoxName);
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('AuthService', () {
    test('starts logged out', () {
      final auth = AuthService();
      expect(auth.isLoggedIn, isFalse);
      expect(auth.currentEmail, isNull);
    });

    test('register creates an account and logs the user in', () async {
      final auth = AuthService();
      await auth.register('Test@Example.com', 'password123');

      expect(auth.isLoggedIn, isTrue);
      // Email is normalized to lowercase/trimmed.
      expect(auth.currentEmail, 'test@example.com');
    });

    test('register rejects a duplicate email (case-insensitive)', () async {
      final auth = AuthService();
      await auth.register('user@example.com', 'password123');
      await auth.logout();

      expect(
        () => auth.register('  USER@Example.com ', 'anotherPassword'),
        throwsA(isA<Exception>()),
      );
    });

    test('login succeeds with correct credentials', () async {
      final auth = AuthService();
      await auth.register('user@example.com', 'correct-password');
      await auth.logout();
      expect(auth.isLoggedIn, isFalse);

      await auth.login('user@example.com', 'correct-password');
      expect(auth.isLoggedIn, isTrue);
      expect(auth.currentEmail, 'user@example.com');
    });

    test('login fails with wrong password', () async {
      final auth = AuthService();
      await auth.register('user@example.com', 'correct-password');
      await auth.logout();

      expect(
        () => auth.login('user@example.com', 'wrong-password'),
        throwsA(isA<Exception>()),
      );
      expect(auth.isLoggedIn, isFalse);
    });

    test('login fails for an unknown email', () async {
      final auth = AuthService();
      expect(
        () => auth.login('nobody@example.com', 'whatever'),
        throwsA(isA<Exception>()),
      );
    });

    test('passwords are never stored in clear text', () async {
      final auth = AuthService();
      const password = 'super-secret-password';
      await auth.register('user@example.com', password);

      final rawUsers =
          HiveDatabase.settingsBox.get('auth_users') as List<dynamic>;
      final stored = Map<String, dynamic>.from(rawUsers.first as Map);

      expect(stored['hash'], isNot(equals(password)));
      expect(stored.toString().contains(password), isFalse);
    });

    test('logout clears the session', () async {
      final auth = AuthService();
      await auth.register('user@example.com', 'password123');
      expect(auth.isLoggedIn, isTrue);

      await auth.logout();
      expect(auth.isLoggedIn, isFalse);
      expect(auth.currentEmail, isNull);
    });
  });
}
