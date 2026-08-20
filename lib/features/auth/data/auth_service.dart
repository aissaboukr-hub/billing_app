import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';
import '../../../core/data/hive_database.dart';

class AuthService {
  static const _usersKey = 'auth_users';
  static const _loggedInKey = 'auth_logged_in';
  static const _usernameKey = 'auth_username';

  bool get isLoggedIn =>
      HiveDatabase.settingsBox.get(_loggedInKey, defaultValue: false) == true;

  String? get currentUsername =>
      HiveDatabase.settingsBox.get(_usernameKey) as String?;

  Map<String, dynamic>? get currentUser {
    final username = currentUsername;
    if (username == null) return null;
    for (final user in _users) {
      if ((user['username'] ?? '').toString().toLowerCase() ==
          username.toLowerCase()) {
        return user;
      }
    }
    return null;
  }

  String get currentRole => (currentUser?['role'] ?? 'user').toString();
  bool get isAdmin => currentRole == 'admin';

  List<Map<String, dynamic>> get users =>
      _users.map((u) => Map<String, dynamic>.from(u)).toList();

  List<Map<String, dynamic>> get _users {
    final raw =
        HiveDatabase.settingsBox.get(_usersKey, defaultValue: <dynamic>[]);
    final list = (raw as List)
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();

    // Migration des anciens comptes : l'adresse e-mail devient temporairement
    // le nom d'utilisateur pour conserver les comptes existants.
    var changed = false;
    for (final user in list) {
      if (user['username'] == null && user['email'] != null) {
        user['username'] = user['email'].toString();
        user['role'] ??= list.length == 1 ? 'admin' : 'user';
        changed = true;
      }
      user['role'] ??= 'user';
    }
    if (changed) {
      HiveDatabase.settingsBox.put(_usersKey, list);
    }
    return list;
  }

  String _hash(String password, String salt) =>
      sha256.convert(utf8.encode('$salt:$password')).toString();

  Future<void> register(String username, String password) async {
    final normalized = username.trim().toLowerCase();
    if (normalized.length < 3) {
      throw Exception('Le nom d’utilisateur doit contenir au moins 3 caractères.');
    }

    final users = _users;
    if (users.any((u) =>
        (u['username'] ?? '').toString().toLowerCase() == normalized)) {
      throw Exception('Ce nom d’utilisateur est déjà utilisé.');
    }

    final salt = List<int>.generate(
        16, (_) => Random.secure().nextInt(256));
    final salt64 = base64UrlEncode(salt);
    users.add({
      'username': normalized,
      'salt': salt64,
      'hash': _hash(password, salt64),
      'role': users.isEmpty ? 'admin' : 'user',
    });
    await HiveDatabase.settingsBox.put(_usersKey, users);
    await login(normalized, password);
  }

  Future<void> login(String username, String password) async {
    final normalized = username.trim().toLowerCase();
    final user = _users.where((u) =>
        (u['username'] ?? '').toString().toLowerCase() == normalized).firstOrNull;

    if (user == null ||
        _hash(password, user['salt'] as String) != user['hash']) {
      throw Exception('Nom d’utilisateur ou mot de passe incorrect.');
    }

    await HiveDatabase.settingsBox.put(_loggedInKey, true);
    await HiveDatabase.settingsBox.put(_usernameKey, normalized);
  }

  Future<void> changePassword(String username, String newPassword) async {
    if (!isAdmin) throw Exception('Seul un administrateur peut gérer les mots de passe.');
    if (newPassword.length < 8) {
      throw Exception('Le mot de passe doit contenir au moins 8 caractères.');
    }

    final users = _users;
    final index = users.indexWhere((u) =>
        (u['username'] ?? '').toString().toLowerCase() ==
        username.trim().toLowerCase());
    if (index < 0) throw Exception('Utilisateur introuvable.');

    final salt = List<int>.generate(
        16, (_) => Random.secure().nextInt(256));
    final salt64 = base64UrlEncode(salt);
    users[index]['salt'] = salt64;
    users[index]['hash'] = _hash(newPassword, salt64);
    await HiveDatabase.settingsBox.put(_usersKey, users);
  }

  Future<void> setRole(String username, String role) async {
    if (!isAdmin) throw Exception('Accès administrateur requis.');
    if (role != 'admin' && role != 'user') {
      throw Exception('Rôle invalide.');
    }
    final normalized = username.trim().toLowerCase();
    if (normalized == currentUsername?.toLowerCase() && role != 'admin') {
      throw Exception('Vous ne pouvez pas retirer votre propre rôle administrateur.');
    }
    final users = _users;
    final index = users.indexWhere((u) =>
        (u['username'] ?? '').toString().toLowerCase() == normalized);
    if (index < 0) throw Exception('Utilisateur introuvable.');
    users[index]['role'] = role;
    await HiveDatabase.settingsBox.put(_usersKey, users);
  }

  Future<void> logout() async {
    await HiveDatabase.settingsBox.put(_loggedInKey, false);
    await HiveDatabase.settingsBox.delete(_usernameKey);
  }
}
