import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';
import '../../../core/data/hive_database.dart';

enum UserRole { admin, user }

class AuthService {
  static const _usersKey = 'auth_users';
  static const _loggedInKey = 'auth_logged_in';
  static const _usernameKey = 'auth_username';

  bool get isLoggedIn =>
      HiveDatabase.settingsBox.get(_loggedInKey, defaultValue: false) == true;

  String? get currentUsername =>
      HiveDatabase.settingsBox.get(_usernameKey) as String?;

  String? get currentRole {
    final username = currentUsername;
    if (username == null) return null;
    final user = _users.where((u) => u['username'] == username).firstOrNull;
    return user?['role'] as String?;
  }

  bool get isAdmin => currentRole == 'admin';

  List<Map<String, dynamic>> get _users {
    final raw =
        HiveDatabase.settingsBox.get(_usersKey, defaultValue: <dynamic>[]);
    return (raw as List)
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
  }

  String _hash(String password, String salt) =>
      sha256.convert(utf8.encode('$salt:$password')).toString();

  String _normalizeUsername(String username) => username.trim().toLowerCase();

  void _validateUsername(String username) {
    if (username.length < 3) {
      throw Exception("Le nom d'utilisateur doit contenir au moins 3 caractères.");
    }
    if (!RegExp(r'^[a-z0-9._-]+$').hasMatch(username)) {
      throw Exception(
          "Le nom d'utilisateur ne peut contenir que des lettres, chiffres, '.', '_' ou '-'.");
    }
  }

  Future<void> register(String username, String password) async {
    final normalized = _normalizeUsername(username);
    _validateUsername(normalized);

    final users = _users;
    if (users.any((u) => u['username'] == normalized)) {
      throw Exception("Ce nom d'utilisateur est déjà utilisé.");
    }

    final salt = List<int>.generate(16, (_) => Random.secure().nextInt(256));
    final salt64 = base64UrlEncode(salt);

    // Le premier compte créé devient administrateur. Tous les suivants sont
    // des utilisateurs avec des droits limités.
    final role = users.isEmpty ? 'admin' : 'user';
    users.add({
      'username': normalized,
      'salt': salt64,
      'hash': _hash(password, salt64),
      'role': role,
    });
    await HiveDatabase.settingsBox.put(_usersKey, users);
    await login(normalized, password);
  }

  Future<void> login(String username, String password) async {
    final normalized = _normalizeUsername(username);
    final users = _users;
    Map<String, dynamic>? user;

    for (final candidate in users) {
      if (candidate['username'] == normalized) {
        user = candidate;
        break;
      }
    }

    // Migration de l'ancien format : les anciens comptes possédaient un
    // champ "email". Leur nom d'utilisateur devient la partie avant @.
    if (user == null) {
      final oldIndex = users.indexWhere((u) {
        final email = (u['email'] as String?)?.trim().toLowerCase();
        return email != null && email.split('@').first == normalized;
      });
      if (oldIndex >= 0) {
        final old = users[oldIndex];
        final email = (old['email'] as String).trim().toLowerCase();
        final migratedUsername = email.split('@').first;
        final existingUsername =
            users.any((u) => u['username'] == migratedUsername);
        if (!existingUsername) {
          old['username'] = migratedUsername;
          old['role'] = old['role'] ?? (oldIndex == 0 ? 'admin' : 'user');
          users[oldIndex] = old;
          await HiveDatabase.settingsBox.put(_usersKey, users);
          if (normalized == migratedUsername) user = old;
        }
      }
    }

    if (user == null ||
        _hash(password, user['salt'] as String) != user['hash']) {
      throw Exception("Nom d'utilisateur ou mot de passe incorrect.");
    }

    await HiveDatabase.settingsBox.put(_loggedInKey, true);
    await HiveDatabase.settingsBox.put(_usernameKey, user['username']);
  }

  List<Map<String, dynamic>> getUsersForAdmin() {
    if (!isAdmin) throw Exception('Accès réservé à l’administrateur.');
    return _users
        .map((u) => {
              'username': u['username'],
              'role': u['role'] ?? 'user',
            })
        .toList();
  }

  Future<void> changeUserPassword({
    required String username,
    required String newPassword,
  }) async {
    if (!isAdmin) throw Exception('Accès réservé à l’administrateur.');
    if (newPassword.length < 8) {
      throw Exception('Le mot de passe doit contenir au moins 8 caractères.');
    }

    final users = _users;
    final index = users.indexWhere((u) => u['username'] == username);
    if (index < 0) throw Exception("Utilisateur introuvable.");

    final salt = List<int>.generate(16, (_) => Random.secure().nextInt(256));
    final salt64 = base64UrlEncode(salt);
    users[index]['salt'] = salt64;
    users[index]['hash'] = _hash(newPassword, salt64);
    await HiveDatabase.settingsBox.put(_usersKey, users);
  }

  Future<void> changeUserRole({
    required String username,
    required UserRole role,
  }) async {
    if (!isAdmin) throw Exception('Accès réservé à l’administrateur.');

    final users = _users;
    final index = users.indexWhere((u) => u['username'] == username);
    if (index < 0) throw Exception("Utilisateur introuvable.");

    // Empêche de supprimer le dernier administrateur.
    if (users[index]['role'] == 'admin' && role == UserRole.user) {
      final adminCount = users.where((u) => u['role'] == 'admin').length;
      if (adminCount <= 1) {
        throw Exception('Il doit rester au moins un administrateur.');
      }
    }

    users[index]['role'] = role.name;
    await HiveDatabase.settingsBox.put(_usersKey, users);
  }

  Future<void> logout() async {
    await HiveDatabase.settingsBox.put(_loggedInKey, false);
    await HiveDatabase.settingsBox.delete(_usernameKey);
  }
}
