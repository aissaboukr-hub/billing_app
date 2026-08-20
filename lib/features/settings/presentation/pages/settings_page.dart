import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:app_settings/app_settings.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../shop/presentation/bloc/shop_bloc.dart';
import '../bloc/printer_bloc.dart';
import '../bloc/printer_event.dart';
import '../bloc/printer_state.dart';
import '../../../auth/data/auth_service.dart';
import '../../../../core/data/hive_database.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final AuthService _auth = AuthService();

  @override
  void initState() {
    super.initState();
    // Re-initialize printer state whenever settings page opens
    context.read<PrinterBloc>().add(InitPrinterEvent());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Paramètres',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
        centerTitle: true,
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.chevron_left,
              size: 28, color: Theme.of(context).primaryColor),
          onPressed: () => context.pop(),
        ),
      ),
      body: SingleChildScrollView(
        child: Column(
          children: [
            // Profile Section
            Container(
              width: double.infinity,
              color: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 24),
              child: BlocBuilder<ShopBloc, ShopState>(
                builder: (context, state) {
                  String shopName = 'Elite Groceries';
                  String initials = 'EG';
                  if (state is ShopLoaded && state.shop.name.isNotEmpty) {
                    shopName = state.shop.name;
                    final parts = shopName.split(' ');
                    initials = parts
                        .take(2)
                        .map((p) => p.isNotEmpty ? p[0].toUpperCase() : '')
                        .join('');
                    if (initials.isEmpty) initials = 'S';
                  }

                  return Column(
                    children: [
                      Container(
                        width: 96,
                        height: 96,
                        decoration: BoxDecoration(
                            color: AppTheme.primaryColor,
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: AppTheme.primaryColor
                                    .withValues(alpha: 0.2),
                                blurRadius: 15,
                                spreadRadius: 5,
                              )
                            ]),
                        alignment: Alignment.center,
                        child: Text(initials,
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 32,
                                fontWeight: FontWeight.bold,
                                letterSpacing: -1)),
                      ),
                      const SizedBox(height: 16),
                      Text(shopName.toUpperCase(),
                          style: const TextStyle(
                              fontSize: 20, fontWeight: FontWeight.bold)),
                    ],
                  );
                },
              ),
            ),

            const SizedBox(height: 24),

            // Management Section — réservée aux administrateurs.
            if (_auth.isAdmin) ...[
              _buildSectionHeader('Gestion'),
              _buildListGroup(
                children: [
                  _buildListItem(
                    icon: Icons.qr_code_scanner,
                    title: 'Produits',
                    subtitle: 'Gérer le stock et les codes-barres',
                    onTap: () => context.push('/products'),
                  ),
                  _buildDivider(),
                  _buildListItem(
                    icon: Icons.storefront,
                    title: 'Informations du commerce',
                    subtitle: 'Modifier les informations et l’adresse',
                    onTap: () => context.push('/shop'),
                  ),
                ],
              ),
              const SizedBox(height: 24),
            ],

            // Hardware Section
            _buildSectionHeader('Matériel'),
            BlocConsumer<PrinterBloc, PrinterState>(
              listener: (context, state) {
                if (state.errorMessage != null) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                      content: Text(state.errorMessage!),
                      backgroundColor: Colors.red));
                } else if (state.status == PrinterStatus.connected) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                      content: Text('Imprimante connectée'),
                      backgroundColor: Colors.green));
                }
              },
              builder: (context, state) {
                return _buildListGroup(
                  children: [
                    _buildListItem(
                      icon: Icons.print,
                      title: 'Imprimante',
                      subtitleWidget: Row(
                        children: [
                          Text(
                            state.connectedMac != null
                                ? (state.connectedName ?? 'Imprimante connectée')
                                : 'Aucune imprimante connectée',
                            style: TextStyle(
                                fontSize: 12, color: Colors.grey[500]),
                          ),
                          if (state.connectedMac != null) ...[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                  color: Colors.teal[100],
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(color: Colors.teal[200]!)),
                              child: Text(
                                'CONNECTÉE',
                                style: TextStyle(
                                    fontSize: 9,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.teal[700]),
                              ),
                            ),
                          ]
                        ],
                      ),
                      trailingWidget: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (state.status == PrinterStatus.scanning ||
                              state.status == PrinterStatus.connecting)
                            const SizedBox(
                                width: 24,
                                height: 24,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2))
                          else
                            IconButton(
                              icon: const Icon(Icons.refresh),
                              onPressed: () => context
                                  .read<PrinterBloc>()
                                  .add(RefreshPrinterEvent()),
                              color: AppTheme.primaryColor,
                            ),
                          IconButton(
                            icon: const Icon(Icons.settings),
                            onPressed: () {
                              AppSettings.openAppSettings(
                                  type: AppSettingsType.bluetooth);
                            },
                            color: Colors.grey,
                          ),
                        ],
                      ),
                    ),
                  ],
                );
              },
            ),

            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              child: Text(
                "Pour connecter un nouvel appareil, ouvrez les réglages Bluetooth du téléphone, effectuez l’appairage, puis revenez ici et actualisez.",
                style: TextStyle(
                    fontSize: 11,
                    fontStyle: FontStyle.italic,
                    color: Colors.grey[500]),
              ),
            ),

            if (_auth.isAdmin) ...[
              const SizedBox(height: 24),
              _buildSectionHeader('Données'),
              _buildListGroup(children: [
                _buildListItem(
                  icon: Icons.import_export,
                  title: 'Import / Export',
                  subtitle: 'Produits, factures et Google Sheets',
                  onTap: () => context.push('/import-export'),
                ),
                _buildDivider(),
                _buildListItem(
                  icon: Icons.cloud_upload,
                  title: 'URL Google Sheets',
                  subtitle: 'Configurer l’URL Google Apps Script pour les ventes',
                  onTap: _configureGoogleSheets,
                ),
              ]),
            ],
            if (_auth.isAdmin) ...[
              const SizedBox(height: 24),
              _buildSectionHeader('Administration'),
              _buildListGroup(children: [
                _buildListItem(
                  icon: Icons.manage_accounts,
                  title: 'Utilisateurs et mots de passe',
                  subtitle: 'Gérer les rôles et les mots de passe',
                  onTap: _manageUsers,
                ),
              ]),
            ],
            const SizedBox(height: 16),
            Padding(padding: const EdgeInsets.symmetric(horizontal: 24), child: OutlinedButton.icon(onPressed: () async { await AuthService().logout(); if (context.mounted) context.go('/login'); }, icon: const Icon(Icons.logout), label: const Text('Se déconnecter'))),
            const SizedBox(height: 48),
          ],
        ),
      ),
    );
  }


  Future<void> _manageUsers() async {
    if (!_auth.isAdmin) return;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          final users = _auth.users;
          return AlertDialog(
            title: const Text('Utilisateurs et mots de passe'),
            content: SizedBox(
              width: 520,
              child: users.isEmpty
                  ? const Text('Aucun utilisateur.')
                  : ListView.separated(
                      shrinkWrap: true,
                      itemCount: users.length,
                      separatorBuilder: (_, __) => const Divider(),
                      itemBuilder: (context, index) {
                        final user = users[index];
                        final username = (user['username'] ?? '').toString();
                        final role = (user['role'] ?? 'user').toString();
                        final isSelf = username.toLowerCase() ==
                            (_auth.currentUsername ?? '').toLowerCase();

                        return ListTile(
                          leading: CircleAvatar(
                            child: Text(username.isNotEmpty
                                ? username[0].toUpperCase()
                                : '?'),
                          ),
                          title: Text(username),
                          subtitle: Text(
                            role == 'admin' ? 'Administrateur' : 'Utilisateur',
                          ),
                          trailing: PopupMenuButton<String>(
                            onSelected: (action) async {
                              try {
                                if (action == 'password') {
                                  final controller = TextEditingController();
                                  final value = await showDialog<String>(
                                    context: context,
                                    builder: (context) => AlertDialog(
                                      title: Text('Mot de passe — $username'),
                                      content: TextField(
                                        controller: controller,
                                        obscureText: true,
                                        autofocus: true,
                                        decoration: const InputDecoration(
                                          labelText: 'Nouveau mot de passe',
                                        ),
                                      ),
                                      actions: [
                                        TextButton(
                                          onPressed: () =>
                                              Navigator.pop(context),
                                          child: const Text('Annuler'),
                                        ),
                                        FilledButton(
                                          onPressed: () => Navigator.pop(
                                              context, controller.text),
                                          child: const Text('Enregistrer'),
                                        ),
                                      ],
                                    ),
                                  );
                                  controller.dispose();
                                  if (value != null) {
                                    await _auth.changePassword(username, value);
                                  }
                                } else if (action == 'role') {
                                  await _auth.setRole(
                                      username,
                                      role == 'admin' ? 'user' : 'admin');
                                }
                                setDialogState(() {});
                              } catch (e) {
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(e
                                          .toString()
                                          .replaceFirst('Exception: ', '')),
                                      backgroundColor: Colors.red,
                                    ),
                                  );
                                }
                              }
                            },
                            itemBuilder: (context) => [
                              const PopupMenuItem(
                                value: 'password',
                                child: Text('Modifier le mot de passe'),
                              ),
                              if (!isSelf)
                                PopupMenuItem(
                                  value: 'role',
                                  child: Text(role == 'admin'
                                      ? 'Passer en Utilisateur'
                                      : 'Passer en Administrateur'),
                                ),
                            ],
                          ),
                        );
                      },
                    ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Fermer'),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _configureGoogleSheets() async {
    final controller = TextEditingController(text: HiveDatabase.settingsBox.get('google_sheets_export_url', defaultValue: '') as String);
    final value = await showDialog<String>(context: context, builder: (context) => AlertDialog(title: const Text('Google Sheets'), content: TextField(controller: controller, decoration: const InputDecoration(labelText: 'URL Google Apps Script', hintText: 'https://script.google.com/macros/s/.../exec')), actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Annuler')), FilledButton(onPressed: () => Navigator.pop(context, controller.text.trim()), child: const Text('Enregistrer'))]));
    controller.dispose();
    if (value != null) await HiveDatabase.settingsBox.put('google_sheets_export_url', value);
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text(
          title.toUpperCase(),
          style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: Colors.grey,
              letterSpacing: 1.2),
        ),
      ),
    );
  }

  Widget _buildListGroup({required List<Widget> children}) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey[100]!),
      ),
      child: Column(children: children),
    );
  }

  Widget _buildDivider() {
    return Divider(height: 1, thickness: 1, color: Colors.grey[50], indent: 64);
  }

  Widget _buildListItem({
    required IconData icon,
    required String title,
    String? subtitle,
    Widget? subtitleWidget,
    Widget? trailingWidget,
    IconData? trailingIcon = Icons.chevron_right,
    VoidCallback? onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: AppTheme.primaryColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, color: AppTheme.primaryColor, size: 20),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: const TextStyle(
                          fontWeight: FontWeight.w600, fontSize: 14)),
                  if (subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(subtitle,
                        style:
                            TextStyle(fontSize: 12, color: Colors.grey[500])),
                  ],
                  if (subtitleWidget != null) ...[
                    const SizedBox(height: 4),
                    subtitleWidget,
                  ]
                ],
              ),
            ),
            if (trailingWidget != null)
              trailingWidget
            else if (trailingIcon != null)
              Icon(trailingIcon, color: Colors.grey[300]),
          ],
        ),
      ),
    );
  }
}
