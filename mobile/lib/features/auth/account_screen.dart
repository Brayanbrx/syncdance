import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/network/catalog_session.dart';
import '../routines/reference/catalog_api.dart';
import '../routines/reference/motion_reference.dart';
import 'account_data.dart';

/// "Mi cuenta": sign out, or delete the account on the server and its files
/// on this phone (Google Play requires deletion inside the app).
class AccountScreen extends StatelessWidget {
  const AccountScreen({this.session, this.eraseLocal, super.key});
  final CatalogSession? session;

  /// Erases the account's practices and references here; defaults to [AccountData].
  final Future<void> Function(String scope)? eraseLocal;

  static Future<void> _eraseOnPhone(String scope) async =>
      (await AccountData.open()).erase(scope);

  @override
  Widget build(BuildContext context) {
    final current = session ?? catalogSession;
    final account = current.account;
    final danger = Theme.of(context).colorScheme.error;
    return Scaffold(
      appBar: AppBar(title: const Text('Mi cuenta')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: account == null
            ? [
                const Text(
                  'Estás usando la app sin cuenta: tus prácticas no se '
                  'sincronizan ni las ve tu instructor.',
                ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: () => context.go('/login'),
                  child: const Text('Ingresar o crear cuenta'),
                ),
              ]
            : [
                ListTile(
                  leading: const Icon(Icons.person_outline),
                  title: Text(account.username),
                  subtitle: const Text('Cuenta en este teléfono'),
                ),
                ListTile(
                  leading: const Icon(Icons.logout),
                  title: const Text('Cerrar sesión'),
                  subtitle: const Text(
                    'Tus prácticas siguen guardadas aquí para cuando vuelvas.',
                  ),
                  onTap: () async {
                    await current.signOut();
                    if (context.mounted) context.go('/login');
                  },
                ),
                const Divider(height: 32),
                ListTile(
                  leading: Icon(Icons.delete_forever_outlined, color: danger),
                  title: Text(
                    'Borrar mi cuenta',
                    style: TextStyle(color: danger),
                  ),
                  subtitle: const Text(
                    'Borra tu cuenta, tus prácticas y tu inscripción en cursos. '
                    'No se puede deshacer.',
                  ),
                  onTap: () async {
                    final deleted = await showDialog<bool>(
                      context: context,
                      barrierDismissible: false,
                      builder: (_) => DeleteAccountDialog(
                        session: current,
                        eraseLocal: eraseLocal ?? _eraseOnPhone,
                      ),
                    );
                    if (deleted != true || !context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Tu cuenta se borró.')),
                    );
                    context.go('/login');
                  },
                ),
              ],
      ),
    );
  }
}

/// Asks for the password again; pops `true` once the account is gone.
class DeleteAccountDialog extends StatefulWidget {
  const DeleteAccountDialog({
    required this.session,
    required this.eraseLocal,
    super.key,
  });
  final CatalogSession session;
  final Future<void> Function(String scope) eraseLocal;
  @override
  State<DeleteAccountDialog> createState() => _DeleteAccountDialogState();
}

class _DeleteAccountDialogState extends State<DeleteAccountDialog> {
  final _password = TextEditingController();
  bool _busy = false;
  String? _error;

  Future<void> _delete() async {
    if (_password.text.isEmpty) {
      setState(() => _error = 'Escribe tu contraseña.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final session = widget.session;
    final scope = session.cacheScope; // before signing out
    try {
      await session.authorized(
        (account) => session.api.deleteAccount(account, _password.text),
      );
    } on SessionExpiredException {
      _fail('Tu sesión venció: vuelve a ingresar y repite el borrado.');
      return;
    } on ReferenceException catch (error) {
      _fail(error.message);
      return;
    }
    try {
      await widget.eraseLocal(scope);
    } catch (_) {
      // The account is gone; leftover files go with the app's private data.
    }
    await session.signOut();
    if (mounted) Navigator.of(context).pop(true);
  }

  void _fail(String message) {
    if (!mounted) return;
    setState(() {
      _busy = false;
      _error = message;
    });
  }

  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final danger = Theme.of(context).colorScheme.error;
    return AlertDialog(
      title: const Text('¿Borrar tu cuenta?'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Se borran tu cuenta, tus prácticas con sus puntajes, las '
            'observaciones de tu instructor y tu inscripción en los cursos, '
            'en el servidor y en este teléfono. No se puede deshacer.',
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _password,
            enabled: !_busy,
            obscureText: true,
            decoration: InputDecoration(
              labelText: 'Tu contraseña',
              errorText: _error,
              errorMaxLines: 4,
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(false),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: danger),
          onPressed: _busy ? null : _delete,
          child: Text(_busy ? 'Borrando…' : 'Borrar para siempre'),
        ),
      ],
    );
  }
}
