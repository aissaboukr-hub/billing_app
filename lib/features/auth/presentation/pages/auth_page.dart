import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../data/auth_service.dart';
import '../../../../core/theme/app_theme.dart';

class AuthPage extends StatefulWidget {
  const AuthPage({super.key});
  @override
  State<AuthPage> createState() => _AuthPageState();
}

class _AuthPageState extends State<AuthPage> {
  final _formKey = GlobalKey<FormState>();
  final _username = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  final _auth = AuthService();
  bool _register = false;
  bool _loading = false;
  bool _obscure = true;

  @override
  void dispose() {
    _username.dispose();
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _loading = true);
    try {
      if (_register) {
        await _auth.register(_username.text, _password.text);
      } else {
        await _auth.login(_username.text, _password.text);
      }
      if (mounted) context.go('/');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(e.toString().replaceFirst('Exception: ', '')),
          backgroundColor: Colors.red,
        ));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: Card(
                elevation: 4,
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Icon(Icons.receipt_long,
                            size: 64, color: AppTheme.primaryColor),
                        const SizedBox(height: 12),
                        Text(
                          _register ? 'Créer un compte' : 'Connexion',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                              fontSize: 26, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _register
                              ? "Créez votre accès sécurisé à l’application."
                              : 'Connectez-vous avec votre nom d’utilisateur.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.grey[600]),
                        ),
                        const SizedBox(height: 28),
                        TextFormField(
                          controller: _username,
                          textInputAction: TextInputAction.next,
                          decoration: const InputDecoration(
                            labelText: "Nom d'utilisateur",
                            prefixIcon: Icon(Icons.person_outline),
                          ),
                          validator: (v) {
                            final value = v?.trim() ?? '';
                            if (value.length < 3) {
                              return "Minimum 3 caractères";
                            }
                            if (!RegExp(r'^[a-zA-Z0-9._-]+$').hasMatch(value)) {
                              return "Lettres, chiffres, '.', '_' et '-' uniquement";
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: _password,
                          obscureText: _obscure,
                          decoration: InputDecoration(
                            labelText: 'Mot de passe',
                            prefixIcon: const Icon(Icons.lock_outline),
                            suffixIcon: IconButton(
                              onPressed: () =>
                                  setState(() => _obscure = !_obscure),
                              icon: Icon(_obscure
                                  ? Icons.visibility
                                  : Icons.visibility_off),
                            ),
                          ),
                          validator: (v) => v == null || v.length < 8
                              ? 'Minimum 8 caractères'
                              : null,
                        ),
                        if (_register) ...[
                          const SizedBox(height: 16),
                          TextFormField(
                            controller: _confirm,
                            obscureText: true,
                            decoration: const InputDecoration(
                              labelText: 'Confirmer le mot de passe',
                              prefixIcon: Icon(Icons.lock_reset),
                            ),
                            validator: (v) => v != _password.text
                                ? 'Les mots de passe ne correspondent pas'
                                : null,
                          ),
                        ],
                        const SizedBox(height: 24),
                        FilledButton.icon(
                          onPressed: _loading ? null : _submit,
                          icon: _loading
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2))
                              : Icon(_register ? Icons.person_add : Icons.login),
                          label: Text(
                              _register ? 'Créer mon compte' : 'Se connecter'),
                        ),
                        const SizedBox(height: 12),
                        TextButton(
                          onPressed: _loading
                              ? null
                              : () => setState(() => _register = !_register),
                          child: Text(_register
                              ? 'J’ai déjà un compte'
                              : 'Créer un nouveau compte'),
                        ),
                        if (_register)
                          Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Text(
                              'Le premier compte créé est administrateur. Les comptes suivants sont utilisateurs.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                  fontSize: 11, color: Colors.grey[600]),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
