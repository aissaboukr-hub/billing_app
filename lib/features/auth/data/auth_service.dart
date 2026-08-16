import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';
import '../../../core/data/hive_database.dart';

class AuthService {
  static const _usersKey = 'auth_users';
  static const _loggedInKey = 'auth_logged_in';
  static const _emailKey = 'auth_email';

  bool get isLoggedIn => HiveDatabase.settingsBox.get(_loggedInKey, defaultValue: false) == true;
  String? get currentEmail => HiveDatabase.settingsBox.get(_emailKey) as String?;

  List<Map<String, dynamic>> get _users {
    final raw = HiveDatabase.settingsBox.get(_usersKey, defaultValue: <dynamic>[]);
    return (raw as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  String _hash(String password, String salt) => sha256.convert(utf8.encode('$salt:$password')).toString();

  Future<void> register(String email, String password) async {
    final normalized = email.trim().toLowerCase();
    final users = _users;
    if (users.any((u) => u['email'] == normalized)) {
      throw Exception('Cette adresse e-mail est déjà utilisée.');
    }
    final salt = List<int>.generate(16, (_) => Random.secure().nextInt(256));
    final salt64 = base64UrlEncode(salt);
    users.add({'email': normalized, 'salt': salt64, 'hash': _hash(password, salt64)});
    await HiveDatabase.settingsBox.put(_usersKey, users);
    await login(normalized, password);
  }

  Future<void> login(String email, String password) async {
    final normalized = email.trim().toLowerCase();
    final user = _users.where((u) => u['email'] == normalized).firstOrNull;
    if (user == null || _hash(password, user['salt'] as String) != user['hash']) {
      throw Exception('Adresse e-mail ou mot de passe incorrect.');
    }
    await HiveDatabase.settingsBox.put(_loggedInKey, true);
    await HiveDatabase.settingsBox.put(_emailKey, normalized);
  }

  Future<void> logout() async {
    await HiveDatabase.settingsBox.put(_loggedInKey, false);
    await HiveDatabase.settingsBox.delete(_emailKey);
  }
}
