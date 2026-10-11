import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:path_provider/path_provider.dart';

import '../../core/network/catalog_session.dart';
import '../training/game/dance_game.dart';
import '../training/history/routine_progress.dart';
import '../training/history/session_store.dart';
import '../training/history/session_sync.dart';
import '../training/presentation/dance_game_screen.dart';
import '../training/presentation/master_playback_screen.dart';
import 'learning_path.dart';
import 'reference/catalog_api.dart';
import 'reference/master_video_cache.dart';
import 'reference/motion_reference.dart';
import 'reference/reference_cache.dart';

class RoutinesScreen extends StatefulWidget {
  const RoutinesScreen({
    this.session,
    this.cache,
    this.videos,
    this.openGame,
    this.sessions,
    super.key,
  });
  final CatalogSession? session;
  final ReferenceCache? cache;

  /// Defaults to a cache beside the references; injectable for tests.
  final MasterVideoCache? videos;

  /// Defaults to [DanceGameScreen]; injectable for tests without plugins.
  final Widget Function(SavedReference saved, File video)? openGame;

  /// Local practice history for the best stars; defaults to the account's.
  final SessionStore? sessions;
  @override
  State<RoutinesScreen> createState() => _RoutinesScreenState();
}

class _RoutinesScreenState extends State<RoutinesScreen> {
  late final CatalogSession _session;
  late final Account? _account;
  ReferenceCache? _cache;
  List<RoutineItem> _routines = [];

  /// False until the server catalog loads: then the routines saved on this
  /// phone are listed instead, so dancing offline is still one tap.
  bool _catalogLoaded = false;
  List<SavedReference> _saved = [];

  /// Best game per routine id, from the local history.
  Map<int, GameSummary> _bestGames = {};
  bool _busy = true;
  String? _message;

  /// Fraction of the master video downloaded; null when unknown or idle.
  double? _progress;
  final _closed = Completer<void>();

  @override
  void dispose() {
    // Cancels a master video download still streaming to disk.
    if (!_closed.isCompleted) _closed.complete();
    super.dispose();
  }

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
      unawaited(_loadBestGames());
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

  /// Stars are a convenience: an unreadable history just hides them.
  Future<void> _loadBestGames() async {
    try {
      final store =
          widget.sessions ?? await SessionStore.open(_session.cacheScope);
      final history = await store.readAll();
      final best = {
        for (final progress in const RoutineProgressCalculator().compute(
          history.sessions,
        ))
          if (progress.bestGame case final session?)
            session.reference.routineId: session.game!,
      };
      if (mounted) setState(() => _bestGames = best);
    } catch (_) {}
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
      final routines = await _session.authorized(_session.api.routines)
        ..sort(RoutineItem.byLevel);
      if (mounted) {
        setState(() {
          _routines = routines;
          _catalogLoaded = true;
        });
      }
    } catch (error) {
      if (mounted) {
        setState(
          () => _message = _catalogLoaded
              ? _error(error)
              : '${_error(error)} Se muestran las rutinas guardadas en este '
                    'teléfono.',
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

  /// One entry per routine saved on this phone, its newest version.
  List<RoutineItem> get _offlineRoutines {
    final latest = <int, SavedReference>{};
    for (final saved in _saved) {
      final id = saved.reference.metadata.routineId;
      latest[id] = _latestSaved(id)!;
    }
    return [
      for (final saved in latest.values)
        RoutineItem(saved.reference.metadata.routineId, saved.name),
    ]..sort((a, b) => a.name.compareTo(b.name));
  }

  SavedReference? _latestSaved(int routineId, {int? version}) {
    SavedReference? best;
    for (final saved in _saved) {
      final metadata = saved.reference.metadata;
      if (metadata.routineId != routineId) continue;
      if (version != null && metadata.version != version) continue;
      if (best == null || metadata.version > best.reference.metadata.version) {
        best = saved;
      }
    }
    return best;
  }

  /// One tap from the catalog to the game: reference, master video, dance.
  /// Offline, the newest version already on this phone is used.
  Future<void> _dance(RoutineItem routine) async {
    setState(() {
      _busy = true;
      _message = 'Preparando ${routine.name}…';
    });
    try {
      SavedReference? saved;
      try {
        final metadata = await _session.authorized(
          (account) => _session.api.metadata(account, routine.id),
        );
        saved = _latestSaved(routine.id, version: metadata.version);
        if (saved == null) {
          final bytes = await _session.authorized(
            (account) => _session.api.download(account, metadata),
          );
          await _cache!.save(routine.name, metadata, bytes);
          await _reloadSaved();
          saved = _latestSaved(routine.id, version: metadata.version);
        }
      } on ReferenceException {
        saved = _latestSaved(routine.id);
        if (saved == null) rethrow;
      }
      if (saved == null) {
        throw const ReferenceException('No se pudo guardar la referencia.');
      }
      final metadata = saved.reference.metadata;
      final videos = widget.videos ?? MasterVideoCache(_cache!.directory);
      var video = await videos.read(metadata);
      if (video == null) {
        final account = await _session.freshAccount();
        var shown = '';
        video = await videos.save(
          metadata,
          _session.api.video(
            account,
            metadata,
            cancelled: _closed.future,
            onProgress: (received, total) {
              final progress = downloadProgress(received, total);
              // One rebuild per visible change, not per network chunk.
              if (!mounted || progress.label == shown) return;
              shown = progress.label;
              setState(() {
                _progress = progress.fraction;
                _message =
                    'Descargando el video de ${routine.name}… ${progress.label}';
              });
            },
          ),
        );
      }
      await _pruneOlder(saved, videos);
      if (!mounted) return;
      setState(() {
        _busy = false;
        _message = null;
      });
      final chosen = saved;
      final file = video;
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) =>
              widget.openGame?.call(chosen, file) ??
              DanceGameScreen(
                instructions: routine.description,
                saved: chosen,
                videoFile: file,
                storeScope: _session.cacheScope,
                onSessionSaved: () => SessionSync.forSession(_session),
              ),
        ),
      );
      await _loadBestGames();
    } catch (error) {
      if (mounted) setState(() => _message = _error(error));
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _progress = null;
        });
      }
    }
  }

  /// Once a version is fully on the phone (reference and video), older ones of
  /// the same routine only take space: the history keeps its own metadata.
  /// Best effort; whatever fails is reclaimed on the next dance.
  Future<void> _pruneOlder(
    SavedReference current,
    MasterVideoCache videos,
  ) async {
    final metadata = current.reference.metadata;
    final older = [
      for (final saved in _saved)
        if (saved.reference.metadata.routineId == metadata.routineId &&
            saved.reference.metadata.version < metadata.version)
          saved.reference.metadata,
    ];
    if (older.isEmpty) return;
    try {
      for (final stale in older) {
        await videos.remove(stale);
        await _cache!.remove(stale);
      }
    } catch (_) {
    } finally {
      await _reloadSaved();
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
                    onSessionSaved: () => SessionSync.forSession(_session),
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

  /// The teaching path: the next step to dance and how far each level goes.
  Widget? _nextStepCard(BuildContext context) {
    final path = LearningPath(_routines, {
      for (final entry in _bestGames.entries) entry.key: entry.value.stars,
    });
    if (path.steps.isEmpty) return null;
    final next = path.next;
    final theme = Theme.of(context);
    return Card(
      color: theme.colorScheme.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              next == null
                  ? '¡Camino completo con 5 estrellas!'
                  : path.completed
                  ? 'Repaso recomendado'
                  : 'Tu siguiente paso',
              style: theme.textTheme.labelLarge,
            ),
            if (next != null) ...[
              const SizedBox(height: 4),
              Text(next.name, style: theme.textTheme.titleMedium),
              if (next.description.isNotEmpty) Text(next.description),
              const SizedBox(height: 4),
              Text(
                path.completed
                    ? 'Sube sus estrellas hasta 5.'
                    : 'Se supera con $passStars estrellas o más en el juego.',
                style: theme.textTheme.bodySmall,
              ),
            ],
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                for (final level in path.levels)
                  Chip(
                    visualDensity: VisualDensity.compact,
                    label: Text(
                      '${level.label}: ${level.passed}/${level.total}',
                    ),
                  ),
              ],
            ),
            if (next != null) ...[
              const SizedBox(height: 8),
              FilledButton.icon(
                onPressed: _busy || _cache == null ? null : () => _dance(next),
                icon: const Icon(Icons.play_arrow),
                label: Text('Bailar «${next.name}»'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget? _subtitle(RoutineItem routine) {
    final game = _bestGames[routine.id];
    final lines = [
      if (routine.details.isNotEmpty) routine.details,
      if (game != null)
        'Mejor marca: ${'★' * game.stars}${'☆' * (5 - game.stars)}',
    ];
    return lines.isEmpty ? null : Text(lines.join('\n'));
  }

  @override
  Widget build(BuildContext context) {
    final routines = _catalogLoaded ? _routines : _offlineRoutines;
    return Scaffold(
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
                if (_busy) LinearProgressIndicator(value: _progress),
                if (_message != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Text(_message!),
                  ),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Text(
                    _catalogLoaded
                        ? 'Catálogo del servidor'
                        : 'Rutinas guardadas en este teléfono',
                  ),
                ),
                if (routines.isEmpty && !_busy)
                  Text(
                    _catalogLoaded
                        ? 'No hay rutinas en el servidor.'
                        : 'No hay rutinas cargadas del servidor.',
                  ),
                if (_catalogLoaded) ?_nextStepCard(context),
                for (final (index, routine) in routines.indexed) ...[
                  if (_catalogLoaded &&
                      routine.difficultyLabel.isNotEmpty &&
                      (index == 0 ||
                          routines[index - 1].difficultyLabel !=
                              routine.difficultyLabel))
                    Padding(
                      padding: const EdgeInsets.only(top: 12, bottom: 4),
                      child: Text(
                        routine.difficultyLabel,
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                    ),
                  ListTile(
                    title: Text(routine.name),
                    subtitle: _subtitle(routine),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          tooltip: 'Bailar',
                          onPressed: _busy || _cache == null
                              ? null
                              : () => _dance(routine),
                          icon: const Icon(Icons.play_circle_fill),
                        ),
                        if (_catalogLoaded)
                          IconButton(
                            tooltip: 'Descargar referencia',
                            onPressed: _busy || _cache == null
                                ? null
                                : () => _download(routine),
                            icon: const Icon(Icons.download_outlined),
                          ),
                      ],
                    ),
                  ),
                ],
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
              ],
            ),
    );
  }
}
