import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/catalog_session.dart';
import '../history/saved_session.dart';
import '../history/session_store.dart';
import 'session_summary_panel.dart';

class SessionHistoryScreen extends StatefulWidget {
  const SessionHistoryScreen({this.session, this.store, super.key});
  final CatalogSession? session;
  final SessionStore? store;
  @override
  State<SessionHistoryScreen> createState() => _SessionHistoryScreenState();
}

class _SessionHistoryScreenState extends State<SessionHistoryScreen> {
  late final CatalogSession _session;
  late final String? _scope;
  SessionStore? _store;
  SessionHistory? _history;
  bool _busy = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _session = widget.session ?? catalogSession;
    _scope = _session.account == null ? null : _session.cacheScope;
    _load();
  }

  Future<void> _load() async {
    if (_scope == null) {
      setState(() => _busy = false);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      _store ??= widget.store ?? await SessionStore.open(_scope);
      final history = await _store!.readAll();
      if (mounted) setState(() => _history = history);
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'No se pudo leer el historial local.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _date(DateTime value) {
    final date = value.toLocal();
    String two(int number) => number.toString().padLeft(2, '0');
    return '${two(date.day)}/${two(date.month)}/${date.year} ${two(date.hour)}:${two(date.minute)}';
  }

  Future<void> _remove(SavedSession record) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Eliminar práctica'),
        content: const Text('Se eliminará este resumen del dispositivo.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _busy = true);
    try {
      await _store!.remove(record.id);
      if (mounted) await _load();
    } catch (_) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = 'No se pudo eliminar la práctica.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Historial de prácticas'),
      actions: [
        if (_scope != null)
          IconButton(
            tooltip: 'Actualizar historial',
            onPressed: _busy ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
      ],
    ),
    body: _scope == null
        ? Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Ingresa con tu cuenta para consultar tu historial.',
                ),
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
              const Text(
                'Guardado en este dispositivo. Sin sincronizar con el servidor.',
              ),
              if (_busy) const LinearProgressIndicator(),
              if (_error != null) Text(_error!),
              if ((_history?.unreadable ?? 0) > 0)
                Text(
                  '${_history!.unreadable} resúmenes dañados o incompatibles no se pudieron leer.',
                ),
              if (!_busy &&
                  _error == null &&
                  _history?.sessions.isEmpty == true)
                const Text('Todavía no hay prácticas guardadas.'),
              for (final record in _history?.sessions ?? <SavedSession>[])
                ListTile(
                  title: Text(record.routineName),
                  subtitle: Text(
                    '${_date(record.startedAt)} · referencia v${record.reference.version}\n'
                    'Similitud: ${record.summary.score?.toStringAsFixed(0) ?? '—'} · '
                    'Cobertura: ${(record.summary.coverage * 100).toStringAsFixed(1)} %',
                  ),
                  trailing: IconButton(
                    tooltip: 'Eliminar práctica',
                    onPressed: _busy ? null : () => _remove(record),
                    icon: const Icon(Icons.delete_outline),
                  ),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => Scaffold(
                        appBar: AppBar(title: Text(record.routineName)),
                        body: SingleChildScrollView(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Text(_date(record.startedAt)),
                              const Text(
                                'Resumen guardado en este dispositivo. Sin sincronizar.',
                              ),
                              SessionSummaryPanel(
                                summary: record.summary,
                                referenceVersion: record.reference.version,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
  );
}
