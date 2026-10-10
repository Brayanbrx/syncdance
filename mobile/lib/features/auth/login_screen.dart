import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/network/catalog_session.dart';
import '../routines/reference/motion_reference.dart';
import '../training/history/session_sync.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({this.session, this.syncPending, super.key});
  final CatalogSession? session;

  /// Uploads the account's pending practices; defaults to [SessionSync].
  final Future<Object?> Function(CatalogSession)? syncPending;
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
    try {
      await _session.signIn(_username.text.trim(), _password.text);
      // Practices this account saved offline go up now, in the background.
      unawaited(
        (widget.syncPending ?? SessionSync.forSession)(
          _session,
        ).then((_) {}, onError: (Object _) {}),
      );
      if (!mounted) return;
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
              onPressed: _busy ? null : () => context.push('/register'),
              child: const Text('Crear cuenta de estudiante'),
            ),
            TextButton(
              onPressed: _busy
                  ? null
                  : () {
                      unawaited(_session.signOut());
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
