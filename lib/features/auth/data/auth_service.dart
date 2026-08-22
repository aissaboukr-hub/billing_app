import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';

import '../../../core/data/hive_database.dart';

enum UserRole { admin, user }

class AuthService {
  static const _usersKey = 'auth_users';
  static const _loggedInKey = 'auth_logged_in';
  static const _usernameKey = 'auth_username';
  static const _deviceIdKey = 'auth_device_id';

  static const defaultAdminUsername = 'admin';
  static const defaultAdminPassword = r'Admin@1234';

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

  bool get isAdmin => currentRole == UserRole.admin.name;

  List<Map<String, dynamic>> get _users {
    final raw = HiveDatabase.settingsBox.get(_usersKey, defaultValue: <dynamic>[]);
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

  void _validatePassword(String password) {
    if (password.length < 8) {
      throw Exception('Le mot de passe doit contenir au moins 8 caractères.');
    }
  }

  String _newSalt() =>
      base64UrlEncode(List<int>.generate(16, (_) => Random.secure().nextInt(256)));

  Future<void> initialize() async {
    final users = _users;
    final adminIndex = users.indexWhere(
      (u) => _normalizeUsername((u['username'] ?? '').toString()) ==
          defaultAdminUsername,
    );

    if (adminIndex == -1) {
      final salt = _newSalt();
      users.insert(0, {
        'username': defaultAdminUsername,
        'salt': salt,
        'hash': _hash(defaultAdminPassword, salt),
        'role': UserRole.admin.name,
        'deviceId': null,
        'mustChangePassword': true,
      });
      await HiveDatabase.settingsBox.put(_usersKey, users);
    } else {
      // Complète les anciens comptes sans casser les données existantes.
      final admin = users[adminIndex];
      admin['username'] = defaultAdminUsername;
      admin['role'] = UserRole.admin.name;
      // L'administrateur ne doit jamais être associé à un appareil.
      admin['deviceId'] = null;
      admin['mustChangePassword'] ??= false;
      users[adminIndex] = admin;
      await HiveDatabase.settingsBox.put(_usersKey, users);
    }
  }

  Future<String> _getDeviceId() async {
    final cached = HiveDatabase.settingsBox.get(_deviceIdKey) as String?;
    if (cached != null && cached.isNotEmpty) return cached;

    final plugin = DeviceInfoPlugin();
    String id;

    if (kIsWeb) {
      final info = await plugin.webBrowserInfo;
      id = 'web:${info.vendor ?? ''}:${info.userAgent ?? ''}:${info.platform ?? ''}';
    } else if (Platform.isAndroid) {
      final info = await plugin.androidInfo;
      id = 'android:${info.id}:${info.model}:${info.manufacturer}';
    } else if (Platform.isIOS) {
      final info = await plugin.iosInfo;
      id = 'ios:${info.identifierForVendor ?? info.name}';
    } else if (Platform.isWindows) {
      final info = await plugin.windowsInfo;
      id = 'windows:${info.deviceId}';
    } else if (Platform.isMacOS) {
      final info = await plugin.macOsInfo;
      id = 'macos:${info.systemGUID ?? info.model}';
    } else if (Platform.isLinux) {
      final info = await plugin.linuxInfo;
      id = 'linux:${info.machineId ?? info.prettyName}';
    } else {
      id = 'generated:${DateTime.now().microsecondsSinceEpoch}:${Random.secure().nextInt(1 << 30)}';
    }

    await HiveDatabase.settingsBox.put(_deviceIdKey, id);
    return id;
  }

  Future<void> register(String username, String password) async {
    if (!isAdmin) {
      throw Exception("La création d'un utilisateur est réservée à l'administrateur.");
    }

    final normalized = _normalizeUsername(username);
    _validateUsername(normalized);
    _validatePassword(password);

    final users = _users;
    if (users.any((u) => u['username'] == normalized)) {
      throw Exception("Ce nom d'utilisateur est déjà utilisé.");
    }

    final salt = _newSalt();
    users.add({
      'username': normalized,
      'salt': salt,
      'hash': _hash(password, salt),
      'role': UserRole.user.name,
      // Le compte sera associé au premier appareil utilisé lors de sa connexion.
      'deviceId': null,
      'mustChangePassword': false,
    });
    await HiveDatabase.settingsBox.put(_usersKey, users);
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

    if (user == null) {
      final oldIndex = users.indexWhere((u) {
        final email = (u['email'] as String?)?.trim().toLowerCase();
        return email != null && email.split('@').first == normalized;
      });
      if (oldIndex >= 0) {
        final old = users[oldIndex];
        final email = (old['email'] as String).trim().toLowerCase();
        final migratedUsername = email.split('@').first;
        if (!users.any((u) => u['username'] == migratedUsername)) {
          old['username'] = migratedUsername;
          old['role'] = old['role'] ?? (oldIndex == 0 ? 'admin' : 'user');
          old['deviceId'] ??= null;
          old['mustChangePassword'] ??= false;
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

    // L'administrateur n'est jamais associé à un appareil.
    // Cela permet à l'administrateur de se connecter sur n'importe quel appareil
    // sans consommer l'association appareil réservée aux utilisateurs.
    final isAdminAccount = user['role'] == UserRole.admin.name;
    if (!isAdminAccount) {
      final deviceId = await _getDeviceId();
      final boundDevice = user['deviceId'] as String?;

      // Un compte déjà lié à un autre appareil ne peut pas être utilisé ici.
      if (boundDevice != null && boundDevice.isNotEmpty && boundDevice != deviceId) {
        throw Exception('Ce compte est déjà associé à un autre appareil.');
      }

      // Un appareil ne peut appartenir qu'à un seul compte utilisateur.
      final otherUser = users.firstWhere(
        (u) => u['role'] != UserRole.admin.name &&
            u['deviceId'] == deviceId &&
            u['username'] != user!['username'],
        orElse: () => <String, dynamic>{},
      );
      if (otherUser.isNotEmpty) {
        throw Exception(
            "Cet appareil est déjà associé à l'utilisateur '${otherUser['username']}'.");
      }

      final index = users.indexWhere((u) => u['username'] == user!['username']);
      if (index >= 0 && users[index]['deviceId'] == null) {
        users[index]['deviceId'] = deviceId;
        await HiveDatabase.settingsBox.put(_usersKey, users);
      }
    } else {
      // Nettoyage des anciennes données : même si l'admin avait été lié avant
      // cette règle, son association est supprimée automatiquement.
      final index = users.indexWhere((u) => u['username'] == user!['username']);
      if (index >= 0 && users[index]['deviceId'] != null) {
        users[index]['deviceId'] = null;
        await HiveDatabase.settingsBox.put(_usersKey, users);
      }
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
              'deviceBound': (u['deviceId'] as String?)?.isNotEmpty == true,
              'mustChangePassword': u['mustChangePassword'] == true,
            })
        .toList();
  }

  Future<void> changeUserPassword({
    required String username,
    required String newPassword,
  }) async {
    if (!isAdmin) throw Exception('Accès réservé à l’administrateur.');
    _validatePassword(newPassword);

    final normalized = _normalizeUsername(username);
    final users = _users;
    final index = users.indexWhere((u) => u['username'] == normalized);
    if (index < 0) throw Exception('Utilisateur introuvable.');

    final salt = _newSalt();
    users[index]['salt'] = salt;
    users[index]['hash'] = _hash(newPassword, salt);
    users[index]['mustChangePassword'] = true;
    await HiveDatabase.settingsBox.put(_usersKey, users);
  }

  Future<void> changeOwnPassword(String newPassword) async {
    final username = currentUsername;
    if (username == null) throw Exception('Aucune session active.');
    _validatePassword(newPassword);

    final users = _users;
    final index = users.indexWhere((u) => u['username'] == username);
    if (index < 0) throw Exception('Utilisateur introuvable.');

    final salt = _newSalt();
    users[index]['salt'] = salt;
    users[index]['hash'] = _hash(newPassword, salt);
    users[index]['mustChangePassword'] = false;
    await HiveDatabase.settingsBox.put(_usersKey, users);
  }

  Future<void> changeUserRole({
    required String username,
    required UserRole role,
  }) async {
    if (!isAdmin) throw Exception('Accès réservé à l’administrateur.');

    final normalized = _normalizeUsername(username);
    final users = _users;
    final index = users.indexWhere((u) => u['username'] == normalized);
    if (index < 0) throw Exception('Utilisateur introuvable.');

    if (normalized == defaultAdminUsername && role != UserRole.admin) {
      throw Exception("Le compte administrateur par défaut ne peut pas perdre son rôle.");
    }

    // Un compte administrateur ne doit jamais être associé à un appareil.
    if (role == UserRole.admin) {
      users[index]['deviceId'] = null;
    }

    if (users[index]['role'] == 'admin' && role == UserRole.user) {
      final adminCount = users.where((u) => u['role'] == 'admin').length;
      if (adminCount <= 1) {
        throw Exception('Il doit rester au moins un administrateur.');
      }
    }

    users[index]['role'] = role.name;
    await HiveDatabase.settingsBox.put(_usersKey, users);
  }

  Future<void> unbindUserDevice(String username) async {
    if (!isAdmin) throw Exception('Accès réservé à l’administrateur.');
    final normalized = _normalizeUsername(username);
    final users = _users;
    final index = users.indexWhere((u) => u['username'] == normalized);
    if (index < 0) throw Exception('Utilisateur introuvable.');
    users[index]['deviceId'] = null;
    await HiveDatabase.settingsBox.put(_usersKey, users);
  }

  Future<void> logout() async {
    await HiveDatabase.settingsBox.put(_loggedInKey, false);
    await HiveDatabase.settingsBox.delete(_usernameKey);
  }
}
