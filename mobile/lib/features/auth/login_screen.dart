import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/network/catalog_session.dart';
import '../routines/reference/motion_reference.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({this.session, super.key});
  final CatalogSession? session;
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _username = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;
  String? _error;
  CatalogSession get _session => widget.session ?? catalogSession;

  Future<void> _login() async {
    if (_username.text.trim().isEmpty || _password.text.isEmpty) {
      setState(() => _error = 'Escribe tu usuario y contraseña.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    _session.signOut();
    try {
      final account = await _session.api.login(
        _username.text.trim(),
        _password.text,
      );
      if (!mounted) return;
      _session.account = account;
      context.go('/home');
    } catch (error) {
      if (mounted) {
        setState(
          () => _error = error is ReferenceException
              ? error.message
              : 'No se pudo iniciar sesión.',
        );
      }
    } finally {
      if (mounted) {
        _password.clear();
        setState(() => _busy = false);
      }
    }
  }

  @override
  void dispose() {
    _username.dispose();
    _password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('SyncDance AI')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _username,
              enabled: !_busy,
              decoration: const InputDecoration(labelText: 'Usuario'),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _password,
              enabled: !_busy,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'Contraseña'),
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _busy ? null : _login,
              child: Text(_busy ? 'Ingresando…' : 'Ingresar'),
            ),
            if (_error != null)
              Padding(padding: const EdgeInsets.all(12), child: Text(_error!)),
            TextButton(
              onPressed: _busy
                  ? null
                  : () {
                      _session.signOut();
                      context.go('/home');
                    },
              child: const Text('Continuar sin cuenta'),
            ),
          ],
        ),
      ),
    );
  }
}
