import 'dart:io';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:path_provider/path_provider.dart';

import '../../core/network/catalog_session.dart';
import '../training/presentation/master_playback_screen.dart';
import 'reference/catalog_api.dart';
import 'reference/master_video_cache.dart';
import 'reference/motion_reference.dart';
import 'reference/reference_cache.dart';

class RoutinesScreen extends StatefulWidget {
  const RoutinesScreen({this.session, this.cache, super.key});
  final CatalogSession? session;
  final ReferenceCache? cache;
  @override
  State<RoutinesScreen> createState() => _RoutinesScreenState();
}

class _RoutinesScreenState extends State<RoutinesScreen> {
  late final CatalogSession _session;
  late final Account? _account;
  ReferenceCache? _cache;
  List<RoutineItem> _routines = [];
  List<SavedReference> _saved = [];
  bool _busy = true;
  String? _message;

  @override
  void initState() {
    super.initState();
    _session = widget.session ?? catalogSession;
    _account = _session.account;
    _initialize();
  }

  Future<void> _initialize() async {
    if (_account == null) {
      setState(() => _busy = false);
      return;
    }
    try {
      _cache =
          widget.cache ??
          ReferenceCache(
            Directory(
              '${(await getApplicationSupportDirectory()).path}/references-v1',
            ),
            '${_session.api.base}|${_account.id}',
          );
      await _reloadSaved();
      await _refresh();
    } catch (_) {
      if (mounted) {
        setState(() {
          _busy = false;
          _message = 'No se pudo abrir el almacenamiento local.';
        });
      }
    }
  }

  Future<void> _reloadSaved() async {
    final saved = await _cache!.readAll();
    if (mounted) setState(() => _saved = saved);
  }

  Future<void> _refresh() async {
    if (!mounted) return;
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final routines = await _session.authorized(_session.api.routines);
      if (mounted) setState(() => _routines = routines);
    } catch (error) {
      if (mounted) {
        setState(
          () => _message =
              '${_error(error)} Puedes consultar las versiones guardadas.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _error(Object error) => error is ReferenceException
      ? error.message
      : 'No se pudo completar la operación.';

  Future<void> _download(RoutineItem routine) async {
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final metadata = await _session.authorized(
        (account) => _session.api.metadata(account, routine.id),
      );
      final bytes = await _session.authorized(
        (account) => _session.api.download(account, metadata),
      );
      await _cache!.save(routine.name, metadata, bytes);
      await _reloadSaved();
      if (mounted) {
        setState(
          () =>
              _message = 'Referencia de ${routine.name} guardada y verificada.',
        );
      }
    } catch (error) {
      if (mounted) setState(() => _message = _error(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _remove(SavedReference saved) async {
    setState(() => _busy = true);
    try {
      await _cache!.remove(saved.reference.metadata);
      await _reloadSaved();
    } catch (error) {
      if (mounted) setState(() => _message = _error(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _show(SavedReference saved) {
    final reference = saved.reference;
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(saved.name),
        content: Text(
          'Versión ${reference.metadata.version}\n'
          '${(reference.metadata.durationMs / 1000).toStringAsFixed(1)} segundos\n'
          '${reference.samples.length} muestras\n'
          '${(reference.coverage * 100).toStringAsFixed(0)} % con medidas utilizables\n\n'
          'Referencia técnica disponible sin conexión en esta sesión. '
          'Abre el maestro para descargar su video y seguir las medidas de esta versión.',
        ),
        actions: [
          FilledButton(
            onPressed: () {
              Navigator.pop(context);
              Navigator.of(this.context).push(
                MaterialPageRoute<void>(
                  builder: (_) => MasterPlaybackScreen(
                    saved: saved,
                    api: _session.api,
                    account: _account!,
                    renewAccount: _session.freshAccount,
                    cache: MasterVideoCache(_cache!.directory),
                  ),
                ),
              );
            },
            child: const Text('Abrir maestro'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cerrar'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Rutinas'),
      actions: [
        if (_account != null)
          IconButton(
            tooltip: 'Actualizar catálogo',
            onPressed: _busy || _cache == null ? null : _refresh,
            icon: const Icon(Icons.refresh),
          ),
      ],
    ),
    body: _account == null
        ? Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Ingresa con tu cuenta para descargar rutinas.'),
                FilledButton(
                  onPressed: () => context.go('/login'),
                  child: const Text('Ingresar'),
                ),
              ],
            ),
          )
        : ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text('Cuenta: ${_account.username}'),
              if (_busy) const LinearProgressIndicator(),
              if (_message != null)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Text(_message!),
                ),
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Text('Referencias guardadas'),
              ),
              if (_saved.isEmpty)
                const Text('Todavía no hay referencias guardadas válidas.'),
              for (final saved in _saved)
                ListTile(
                  title: Text(saved.name),
                  subtitle: Text(
                    'Versión ${saved.reference.metadata.version} · guardada en este dispositivo',
                  ),
                  onTap: () => _show(saved),
                  trailing: IconButton(
                    tooltip: 'Eliminar versión guardada',
                    onPressed: _busy ? null : () => _remove(saved),
                    icon: const Icon(Icons.delete_outline),
                  ),
                ),
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Text('Catálogo del servidor'),
              ),
              if (_routines.isEmpty && !_busy)
                const Text('No hay rutinas cargadas del servidor.'),
              for (final routine in _routines)
                ListTile(
                  title: Text(routine.name),
                  trailing: IconButton(
                    tooltip: 'Descargar referencia',
                    onPressed: _busy || _cache == null
                        ? null
                        : () => _download(routine),
                    icon: const Icon(Icons.download_outlined),
                  ),
                ),
            ],
          ),
  );
}
