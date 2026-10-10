import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/network/catalog_session.dart';
import '../routines/reference/catalog_api.dart';
import '../routines/reference/motion_reference.dart';

/// Student sign-up. The server always assigns the student role and checks the
/// password (length, common, only digits, similar to the name); its messages
/// are shown under each field. On success the new account signs in.
class RegisterScreen extends StatefulWidget {
  const RegisterScreen({this.session, super.key});
  final CatalogSession? session;
  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _username = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _repeat = TextEditingController();
  bool _busy = false;
  String? _error;
  Map<String, String> _fields = const {};
  CatalogSession get _session => widget.session ?? catalogSession;

  /// Checks that need no server; the server repeats them and adds its own.
  Map<String, String> _localErrors() => {
    if (_username.text.trim().isEmpty) 'username': 'Escribe un usuario.',
    if (!RegExp(r'^\S+@\S+\.\S+$').hasMatch(_email.text.trim()))
      'email': 'Escribe un correo válido.',
    if (_password.text.length < 8)
      'password': 'Usa al menos 8 caracteres.'
    else if (_password.text != _repeat.text)
      'repeat': 'Las contraseñas no coinciden.',
  };

  Future<void> _register() async {
    final local = _localErrors();
    if (local.isNotEmpty) {
      setState(() {
        _fields = local;
        _error = null;
      });
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
      _fields = const {};
    });
    final username = _username.text.trim();
    try {
      await _session.api.register(username, _email.text.trim(), _password.text);
      await _session.signIn(username, _password.text);
      if (!mounted) return;
      context.go('/home');
    } on RegistrationException catch (error) {
      if (mounted) {
        setState(() {
          _fields = error.fields;
          // Messages without a field of their own go above the button.
          final known = {'username', 'email', 'password'};
          _error = error.fields.keys.any(known.contains) ? null : error.message;
        });
      }
    } catch (error) {
      if (mounted) {
        setState(
          () => _error = error is ReferenceException
              ? error.message
              : 'No se pudo crear la cuenta.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    for (final controller in [_username, _email, _password, _repeat]) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Crear cuenta')),
    body: SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _username,
            enabled: !_busy,
            autocorrect: false,
            decoration: InputDecoration(
              labelText: 'Usuario',
              errorText: _fields['username'],
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _email,
            enabled: !_busy,
            autocorrect: false,
            keyboardType: TextInputType.emailAddress,
            decoration: InputDecoration(
              labelText: 'Correo',
              errorText: _fields['email'],
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _password,
            enabled: !_busy,
            obscureText: true,
            decoration: InputDecoration(
              labelText: 'Contraseña',
              helperText: 'Al menos 8 caracteres; no solo números.',
              errorText: _fields['password'],
              errorMaxLines: 3,
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _repeat,
            enabled: !_busy,
            obscureText: true,
            decoration: InputDecoration(
              labelText: 'Repetir contraseña',
              errorText: _fields['repeat'],
            ),
          ),
          const SizedBox(height: 24),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(_error!),
            ),
          FilledButton(
            onPressed: _busy ? null : _register,
            child: Text(_busy ? 'Creando cuenta…' : 'Crear cuenta'),
          ),
        ],
      ),
    ),
  );
}
