import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import '../../core/network/catalog_session.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/brand_widgets.dart';
import '../routines/reference/catalog_api.dart';
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
  bool _hidePassword = true;
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
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      // The indigo header runs under the status bar: light icons on it.
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        body: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const _BrandHeader(),
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 28, 24, 32),
                child: AutofillGroup(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'Ingresa a tu cuenta',
                        style: theme.textTheme.headlineSmall,
                      ),
                      const SizedBox(height: 20),
                      TextField(
                        controller: _username,
                        enabled: !_busy,
                        textInputAction: TextInputAction.next,
                        autofillHints: const [AutofillHints.username],
                        decoration: const InputDecoration(
                          labelText: 'Usuario',
                          prefixIcon: Icon(Icons.person_outline_rounded),
                        ),
                      ),
                      const SizedBox(height: 14),
                      TextField(
                        controller: _password,
                        enabled: !_busy,
                        obscureText: _hidePassword,
                        textInputAction: TextInputAction.done,
                        autofillHints: const [AutofillHints.password],
                        onSubmitted: (_) => _busy ? null : _login(),
                        decoration: InputDecoration(
                          labelText: 'Contraseña',
                          prefixIcon: const Icon(Icons.lock_outline_rounded),
                          suffixIcon: IconButton(
                            tooltip: _hidePassword
                                ? 'Mostrar contraseña'
                                : 'Ocultar contraseña',
                            icon: Icon(
                              _hidePassword
                                  ? Icons.visibility_outlined
                                  : Icons.visibility_off_outlined,
                            ),
                            onPressed: () =>
                                setState(() => _hidePassword = !_hidePassword),
                          ),
                        ),
                      ),
                      if (_error != null) ...[
                        const SizedBox(height: 14),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: scheme.errorContainer,
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                Icons.error_outline_rounded,
                                color: scheme.onErrorContainer,
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  _error!,
                                  style: TextStyle(
                                    color: scheme.onErrorContainer,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                      const SizedBox(height: 20),
                      FilledButton(
                        onPressed: _busy ? null : _login,
                        child: Text(_busy ? 'Ingresando…' : 'Ingresar'),
                      ),
                      const SizedBox(height: 4),
                      TextButton(
                        onPressed: _busy
                            ? null
                            : () => showDialog<void>(
                                context: context,
                                builder: (_) =>
                                    ForgotPasswordDialog(api: _session.api),
                              ),
                        child: const Text('¿Olvidaste tu contraseña?'),
                      ),
                      const SizedBox(height: 20),
                      Text(
                        '¿Es tu primera vez?',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 8),
                      OutlinedButton(
                        onPressed: _busy
                            ? null
                            : () => context.push('/register'),
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
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The indigo stage with the brand, at the top of the sign-in screen.
class _BrandHeader extends StatelessWidget {
  const _BrandHeader();

  @override
  Widget build(BuildContext context) {
    final sync = SyncColors.of(context);
    final theme = Theme.of(context);
    final top = MediaQuery.paddingOf(context).top;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: sync.stage,
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(32)),
      ),
      child: Padding(
        padding: EdgeInsets.fromLTRB(24, top + 36, 24, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'SyncDance',
              style: theme.textTheme.displayMedium?.copyWith(
                color: sync.onStage,
                height: 1,
              ),
            ),
            const SizedBox(height: 14),
            const BrandStripe(width: 96),
            const SizedBox(height: 18),
            Text(
              'Aprende a bailar y a cantar con tu teléfono. Te corrige al '
              'momento, y tu imagen y tu voz no salen del celular.',
              style: theme.textTheme.bodyLarge?.copyWith(
                color: sync.onStageMuted,
                height: 1.45,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Asks for the account's email; the link arrives by mail and opens the web
/// page that sets the new password. Then the student signs in here again.
class ForgotPasswordDialog extends StatefulWidget {
  const ForgotPasswordDialog({required this.api, super.key});
  final CatalogApi api;
  @override
  State<ForgotPasswordDialog> createState() => _ForgotPasswordDialogState();
}

class _ForgotPasswordDialogState extends State<ForgotPasswordDialog> {
  final _email = TextEditingController();
  bool _busy = false;
  String? _error;
  String? _sent;

  Future<void> _send() async {
    final email = _email.text.trim();
    if (!RegExp(r'^\S+@\S+\.\S+$').hasMatch(email)) {
      setState(() => _error = 'Escribe un correo válido.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final detail = await widget.api.requestPasswordReset(email);
      if (mounted) setState(() => _sent = detail);
    } on ReferenceException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final sent = _sent;
    return AlertDialog(
      title: const Text('Recuperar contraseña'),
      content: sent != null
          ? Text(
              '$sent\n\nAbre el enlace en este teléfono, elige la contraseña '
              'nueva y vuelve a ingresar aquí. El correo también te recuerda '
              'tu usuario.',
            )
          : Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Te enviaremos un enlace para elegir una contraseña nueva.',
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _email,
                  enabled: !_busy,
                  autofocus: true,
                  keyboardType: TextInputType.emailAddress,
                  decoration: InputDecoration(
                    labelText: 'Correo de tu cuenta',
                    errorText: _error,
                  ),
                  onSubmitted: (_) => _send(),
                ),
              ],
            ),
      actions: sent != null
          ? [
              FilledButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Entendido'),
              ),
            ]
          : [
              TextButton(
                onPressed: _busy ? null : () => Navigator.of(context).pop(),
                child: const Text('Cancelar'),
              ),
              FilledButton(
                onPressed: _busy ? null : _send,
                child: Text(_busy ? 'Enviando…' : 'Enviar enlace'),
              ),
            ],
    );
  }
}
