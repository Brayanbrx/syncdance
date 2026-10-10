import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/catalog_session.dart';
import '../../routines/reference/motion_reference.dart';
import '../game/dance_game.dart';
import '../history/routine_progress.dart';
import '../history/saved_session.dart';
import '../history/session_store.dart';
import '../history/session_sync.dart';
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
  bool _syncing = false;
  String? _error;
  String? _syncMessage;

  @override
  void initState() {
    super.initState();
    _session = widget.session ?? catalogSession;
    _scope = _session.account == null ? null : _session.cacheScope;
    _load(sync: true);
  }

  /// Uploads pending summaries; the list stays usable while it runs.
  Future<void> _sync() async {
    final store = _store;
    if (_syncing || store == null) return;
    setState(() {
      _syncing = true;
      _syncMessage = null;
    });
    try {
      final report = await SessionSync(store: store, session: _session).run();
      final history = await store.readAll();
      if (mounted) {
        setState(() {
          _history = history;
          _syncMessage = _describe(report);
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _syncMessage = 'No se pudo sincronizar el historial.');
      }
    } finally {
      if (mounted) setState(() => _syncing = false);
    }
  }

  /// Brings practices synced from another phone or before a reinstall.
  Future<void> _restore() async {
    final store = _store;
    if (_syncing || store == null) return;
    setState(() {
      _syncing = true;
      _syncMessage = null;
    });
    try {
      final report = await SessionSync(
        store: store,
        session: _session,
      ).restore();
      final history = await store.readAll();
      if (mounted) {
        setState(() {
          _history = history;
          _syncMessage = [
            if (report.restored == 0 && report.skipped == 0)
              'Este teléfono ya tiene todas tus prácticas del servidor.'
            else
              'Se recuperaron ${report.restored} prácticas del servidor.',
            if (report.skipped > 0)
              '${report.skipped} en formatos antiguos no se pudieron leer.',
          ].join(' ');
        });
      }
    } catch (error) {
      if (mounted) {
        setState(
          () => _syncMessage = error is ReferenceException
              ? error.message
              : 'No se pudo traer el historial del servidor.',
        );
      }
    } finally {
      if (mounted) setState(() => _syncing = false);
    }
  }

  String? _describe(SessionSyncReport report) {
    final text = [
      if (report.synced > 0)
        'Se enviaron ${report.synced} prácticas al servidor.',
      if (report.rejected > 0)
        '${report.rejected} prácticas no fueron aceptadas por el servidor.',
      if (report.stoppedBy != null) report.stoppedBy!,
    ].join(' ');
    return text.isEmpty ? null : text;
  }

  String _status(SyncStatus status) => switch (status.state) {
    SyncState.synced => 'Sincronizada con el servidor',
    SyncState.pending => 'Pendiente de enviar al servidor',
    SyncState.rejected => 'No aceptada por el servidor',
  };

  Future<void> _retry(SavedSession record) async {
    await _store!.clearSync(record.id);
    if (!mounted) return;
    Navigator.of(context).pop();
    await _load(sync: true);
  }

  Future<void> _load({bool sync = false}) async {
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
    if (sync && mounted && _error == null) unawaited(_sync());
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

  List<RoutineProgress> get _progress =>
      const RoutineProgressCalculator().compute(_history?.sessions ?? const []);

  String _score(double value) => value.toStringAsFixed(0);

  String _stars(GameSummary game) => '★' * game.stars + '☆' * (5 - game.stars);

  String _describeProgress(RoutineProgress progress) {
    final best = progress.best;
    final lines = <String>[
      if (best == null)
        'Sin prácticas comparables todavía (se requiere al menos '
            '${(RoutineProgressCalculator.minimumCoverage * 100).round()} % de cobertura).'
      else ...[
        'Mejor marca: ${_score(best.summary.score!)} · '
            'Última: ${_score(progress.latest!.summary.score!)}'
            '${progress.change == null ? '' : ' (${progress.change! >= 0 ? '+' : '−'}${_score(progress.change!.abs())} respecto a la anterior)'}',
        'Últimas: ${progress.recentScores().map(_score).join(' · ')}',
      ],
      if (progress.bestGame?.game case final game?)
        'Modo juego: mejor ${_stars(game)} · ${game.points} de '
            '${game.maxPoints} pts',
      if (progress.excluded > 0)
        '${progress.excluded} prácticas no comparables: sin evidencia, poca '
            'cobertura u otra versión.',
    ];
    return lines.join('\n');
  }

  bool _isBest(SavedSession record) =>
      _progress.any((progress) => identical(progress.best, record));

  String _header() {
    final sessions = _history?.sessions ?? const <SavedSession>[];
    final pending = sessions
        .where((s) => _history!.syncOf(s.id).state == SyncState.pending)
        .length;
    if (sessions.isEmpty) return 'Guardado en este dispositivo.';
    return pending == 0
        ? 'Guardado en este dispositivo. Nada pendiente de enviar.'
        : 'Guardado en este dispositivo. $pending pendientes de enviar al servidor.';
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Historial de prácticas'),
      actions: [
        if (_scope != null)
          IconButton(
            tooltip: 'Sincronizar ahora',
            onPressed: _busy || _syncing ? null : _sync,
            icon: const Icon(Icons.cloud_upload_outlined),
          ),
        if (_scope != null)
          IconButton(
            tooltip: 'Traer prácticas del servidor',
            onPressed: _busy || _syncing ? null : _restore,
            icon: const Icon(Icons.cloud_download_outlined),
          ),
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
              Text(_header()),
              if (_busy || _syncing) const LinearProgressIndicator(),
              if (_syncMessage != null) Text(_syncMessage!),
              if (_error != null) Text(_error!),
              if ((_history?.unreadable ?? 0) > 0)
                Text(
                  '${_history!.unreadable} resúmenes dañados o incompatibles no se pudieron leer.',
                ),
              if (!_busy &&
                  _error == null &&
                  _history?.sessions.isEmpty == true)
                const Text('Todavía no hay prácticas guardadas.'),
              if (!_busy &&
                  _error == null &&
                  _history?.sessions.isEmpty == true)
                TextButton.icon(
                  onPressed: _syncing ? null : _restore,
                  icon: const Icon(Icons.cloud_download_outlined),
                  label: const Text('Recuperar mis prácticas del servidor'),
                ),
              if (_history?.sessions.isNotEmpty == true) ...[
                const SizedBox(height: 16),
                Text(
                  'Progreso por rutina',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                for (final progress in _progress)
                  ListTile(
                    title: Text(
                      '${progress.routineName} · referencia v${progress.referenceVersion}',
                    ),
                    subtitle: Text(_describeProgress(progress)),
                  ),
                const Divider(),
              ],
              for (final record in _history?.sessions ?? <SavedSession>[])
                ListTile(
                  title: Text(record.routineName),
                  subtitle: Text(
                    '${_date(record.startedAt)} · referencia v${record.reference.version}\n'
                    '${record.game == null ? '' : '${_stars(record.game!)} · ${record.game!.points} pts · '}'
                    'Similitud: ${record.summary.score?.toStringAsFixed(0) ?? '—'} · '
                    'Cobertura: ${(record.summary.coverage * 100).toStringAsFixed(1)} %\n'
                    '${_status(_history!.syncOf(record.id))}',
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
                              if (record.game != null)
                                Text(
                                  'Modo juego: ${_stars(record.game!)} · '
                                  '${record.game!.points} de ${record.game!.maxPoints} pts · '
                                  'combo máximo ×${record.game!.maxCombo}',
                                ),
                              if (_isBest(record))
                                const Text(
                                  'Mejor marca personal en esta rutina',
                                ),
                              Text(_status(_history!.syncOf(record.id))),
                              if (_history!.syncOf(record.id).reason != null)
                                Text(_history!.syncOf(record.id).reason!),
                              if (_history!.syncOf(record.id).state ==
                                  SyncState.rejected)
                                TextButton(
                                  onPressed: () => _retry(record),
                                  child: const Text(
                                    'Volver a intentar el envío',
                                  ),
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
