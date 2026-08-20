import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../data/auth_service.dart';

class UserManagementPage extends StatefulWidget {
  const UserManagementPage({super.key});

  @override
  State<UserManagementPage> createState() => _UserManagementPageState();
}

class _UserManagementPageState extends State<UserManagementPage> {
  final _auth = AuthService();

  Future<void> _changePassword(String username) async {
    final controller = TextEditingController();
    final confirm = TextEditingController();

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Modifier le mot de passe — $username'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: controller,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'Nouveau mot de passe'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: confirm,
              obscureText: true,
              decoration:
                  const InputDecoration(labelText: 'Confirmer le mot de passe'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () async {
              if (controller.text.length < 8) {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                    content: Text('Minimum 8 caractères.')));
                return;
              }
              if (controller.text != confirm.text) {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                    content: Text('Les mots de passe ne correspondent pas.')));
                return;
              }
              try {
                await _auth.changeUserPassword(
                  username: username,
                  newPassword: controller.text,
                );
                if (context.mounted) Navigator.pop(context, true);
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                      content:
                          Text(e.toString().replaceFirst('Exception: ', ''))));
                }
              }
            },
            child: const Text('Enregistrer'),
          ),
        ],
      ),
    );

    controller.dispose();
    confirm.dispose();

    if (result == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Mot de passe modifié.')));
    }
  }

  Future<void> _changeRole(String username, String currentRole) async {
    final role = await showDialog<UserRole>(
      context: context,
      builder: (context) => SimpleDialog(
        title: Text('Rôle de $username'),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, UserRole.admin),
            child: const ListTile(
              leading: Icon(Icons.admin_panel_settings),
              title: Text('Administrateur'),
              subtitle: Text('Accès complet'),
            ),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, UserRole.user),
            child: const ListTile(
              leading: Icon(Icons.person_outline),
              title: Text('Utilisateur'),
              subtitle: Text('Accès limité'),
            ),
          ),
        ],
      ),
    );

    if (role == null || role.name == currentRole) return;

    try {
      await _auth.changeUserRole(username: username, role: role);
      if (mounted) setState(() {});
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(e.toString().replaceFirst('Exception: ', ''))));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final users = _auth.getUsersForAdmin();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Gestion des utilisateurs'),
        leading: IconButton(
          icon: const Icon(Icons.chevron_left),
          onPressed: () => context.pop(),
        ),
      ),
      body: users.isEmpty
          ? const Center(child: Text('Aucun utilisateur.'))
          : ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: users.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final user = users[index];
                final username = user['username'] as String;
                final role = user['role'] as String;

                return Card(
                  child: ListTile(
                    leading: CircleAvatar(
                      child: Icon(role == 'admin'
                          ? Icons.admin_panel_settings
                          : Icons.person),
                    ),
                    title: Text(username),
                    subtitle: Text(
                        role == 'admin' ? 'Administrateur' : 'Utilisateur'),
                    trailing: PopupMenuButton<String>(
                      onSelected: (value) {
                        if (value == 'password') {
                          _changePassword(username);
                        } else if (value == 'role') {
                          _changeRole(username, role);
                        }
                      },
                      itemBuilder: (_) => const [
                        PopupMenuItem(
                          value: 'password',
                          child: ListTile(
                            leading: Icon(Icons.lock_reset),
                            title: Text('Modifier le mot de passe'),
                          ),
                        ),
                        PopupMenuItem(
                          value: 'role',
                          child: ListTile(
                            leading: Icon(Icons.admin_panel_settings),
                            title: Text('Modifier le rôle'),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }
}
