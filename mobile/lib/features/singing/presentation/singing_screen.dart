import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/network/catalog_session.dart';
import '../../routines/reference/catalog_api.dart';
import '../../routines/reference/master_video_cache.dart' show downloadProgress;
import '../../routines/reference/motion_reference.dart' show ReferenceException;
import '../practice/vocal_practice.dart' show PracticeMode;
import '../reference/voice_store.dart';
import 'singing_practice_screen.dart';
import 'tuner_screen.dart';

/// "Cantar": the singing exercises and the instructor's songs.
/// Online it lists the catalog; offline, what is saved on this phone, so a
/// downloaded exercise is always one tap away.
class SingingScreen extends StatefulWidget {
  const SingingScreen({
    this.session,
    this.store,
    this.openPractice,
    this.openTuner,
    this.startRoutineId,
    super.key,
  });

  final CatalogSession? session;
  final VoiceStore? store;

  /// Defaults to [SingingPracticeScreen]; injectable for tests.
  final Widget Function(SavedVoiceRoutine routine, VoiceStore store)?
  openPractice;

  /// Defaults to [TunerScreen]; injectable for tests.
  final Widget Function()? openTuner;

  /// Opened from a course task: sing this routine as soon as it is listed.
  final int? startRoutineId;

  @override
  State<SingingScreen> createState() => _SingingScreenState();
}

class _SingingScreenState extends State<SingingScreen> {
  late final CatalogSession _session;
  VoiceStore? _store;
  List<RoutineItem> _routines = [];
  List<SavedVoiceRoutine> _saved = [];
  Map<int, int> _best = {};
  bool _catalogLoaded = false, _busy = true;
  String? _message;
  double? _progress;
  final _closed = Completer<void>();

  @override
  void initState() {
    super.initState();
    _session = widget.session ?? catalogSession;
    _initialize();
  }

  @override
  void dispose() {
    if (!_closed.isCompleted) _closed.complete();
    super.dispose();
  }

  Future<void> _initialize() async {
    if (_session.account == null) {
      setState(() => _busy = false);
      return;
    }
    try {
      _store = widget.store ?? await VoiceStore.open(_session.cacheScope);
      await _reloadLocal();
    } catch (_) {
      if (mounted) {
        setState(() => _message = 'No se pudo abrir el almacenamiento local.');
      }
    }
    await _refresh();
    final start = widget.startRoutineId;
    if (start != null && mounted) {
      final listed = _catalogLoaded ? _routines : _offline;
      final routine = listed.where((r) => r.id == start).firstOrNull;
      if (routine == null) {
        setState(
          () => _message = 'La rutina de canto asignada no está disponible.',
        );
      } else {
        await _sing(routine);
      }
    }
  }

  Future<void> _reloadLocal() async {
    final store = _store;
    if (store == null) return;
    final saved = await store.readAll();
    final best = <int, int>{};
    final basis = <int, (PracticeMode, double)>{};
    // Newest first: the way the last practice was sung sets what to compare
    // with. Repeating after the guide slowly is not singing with it at full
    // speed, as with the dance follow modes and speeds.
    for (final record in await store.history()) {
      final overall = record.overall;
      // A score from older rules is not a mark to beat.
      if (overall == null || !record.isCurrent) continue;
      final kind = (record.mode, record.speed);
      if ((basis[record.routineId] ??= kind) != kind) continue;
      if (overall > (best[record.routineId] ?? -1)) {
        best[record.routineId] = overall;
      }
    }
    if (mounted) {
      setState(() {
        _saved = saved;
        _best = best;
      });
    }
  }

  Future<void> _refresh() async {
    if (!mounted) return;
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final routines =
          await _session.authorized(
              (account) =>
                  _session.api.routines(account, kind: RoutineItem.sing),
            )
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
          () => _message = _saved.isEmpty
              ? _error(error)
              : '${_error(error)} Se muestran los ejercicios guardados en '
                    'este teléfono.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _error(Object error) => error is ReferenceException
      ? error.message
      : 'No se pudo completar la operación.';

  /// Newest saved version of each routine on this phone.
  List<RoutineItem> get _offline {
    final latest = <int, SavedVoiceRoutine>{};
    for (final saved in _saved) {
      final id = saved.reference.metadata.routineId;
      final current = latest[id];
      if (current == null ||
          saved.reference.metadata.version >
              current.reference.metadata.version) {
        latest[id] = saved;
      }
    }
    return [
      for (final saved in latest.values)
        RoutineItem(
          saved.reference.metadata.routineId,
          saved.name,
          kind: RoutineItem.sing,
        ),
    ]..sort((a, b) => a.name.compareTo(b.name));
  }

  SavedVoiceRoutine? _savedFor(int routineId, {String? checksum}) {
    SavedVoiceRoutine? best;
    for (final saved in _saved) {
      final m = saved.reference.metadata;
      if (m.routineId != routineId) continue;
      if (checksum != null && m.checksum != checksum) continue;
      if (best == null || m.version > best.reference.metadata.version) {
        best = saved;
      }
    }
    return best;
  }

  /// One tap: melody and guide (downloaded once), then the practice.
  Future<void> _sing(RoutineItem routine) async {
    final store = _store;
    if (store == null) {
      setState(
        () => _message =
            'No se pudo abrir el almacenamiento del teléfono. Cierra la app '
            'y vuelve a abrirla.',
      );
      return;
    }
    setState(() {
      _busy = true;
      _progress = null;
      _message = 'Preparando ${routine.name}…';
    });
    SavedVoiceRoutine? ready;
    try {
      try {
        final metadata = await _session.authorized(
          (account) => _session.api.pitchMetadata(account, routine.id),
        );
        ready = _savedFor(routine.id, checksum: metadata.checksum);
        if (ready == null) {
          final melody = await _session.authorized(
            (account) => _session.api.downloadPitch(account, metadata),
          );
          final account = await _session.freshAccount();
          ready = await store.save(
            routine.name,
            metadata,
            melody,
            _session.api.audio(
              account,
              metadata,
              cancelled: _closed.future,
              onProgress: (received, total) {
                if (mounted) {
                  setState(() {
                    final progress = downloadProgress(received, total);
                    _progress = progress.fraction;
                    _message = 'Descargando la guía… ${progress.label}';
                  });
                }
              },
            ),
          );
          await _reloadLocal();
        }
      } on ReferenceException {
        // Offline or the server refused: a saved version still works.
        ready = _savedFor(routine.id);
        if (ready == null) rethrow;
      }
      if (!mounted) return;
      setState(() {
        _busy = false;
        _progress = null;
        _message = null;
      });
      final practice =
          widget.openPractice ??
          (SavedVoiceRoutine routine, VoiceStore store) =>
              SingingPracticeScreen(routine: routine, store: store);
      await Navigator.of(
        context,
      ).push(MaterialPageRoute<void>(builder: (_) => practice(ready!, store)));
      await _reloadLocal();
    } catch (error) {
      if (mounted) {
        setState(() {
          _busy = false;
          _progress = null;
          _message = _error(error);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final listed = _catalogLoaded ? _routines : _offline;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Cantar'),
        actions: [
          IconButton(
            tooltip: 'Actualizar',
            icon: const Icon(Icons.refresh),
            onPressed: _busy ? null : _refresh,
          ),
        ],
      ),
      body: RefreshIndicator(
        // Pulling during a download would end it as "not busy": the buttons
        // came back and a second download could start over the first.
        onRefresh: () async {
          if (!_busy) await _refresh();
        },
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Card(
              color: theme.colorScheme.secondaryContainer,
              child: const ListTile(
                leading: Icon(Icons.hearing),
                title: Text('Escucha y repite'),
                subtitle: Text(
                  'La guía canta una frase y luego la cantas tú: funciona sin '
                  'audífonos. Para cantar al mismo tiempo que la guía, '
                  'conecta audífonos.',
                ),
              ),
            ),
            Card(
              child: ListTile(
                leading: const Icon(Icons.tune),
                title: const Text('Afinador'),
                subtitle: const Text(
                  'Calienta sosteniendo una nota y comprueba que el micrófono '
                  'te oye.',
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) =>
                        widget.openTuner?.call() ?? const TunerScreen(),
                  ),
                ),
              ),
            ),
            if (_busy) LinearProgressIndicator(value: _progress),
            if (_message != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(_message!),
              ),
            if (_session.account == null)
              const Text('Ingresa con tu cuenta para ver los ejercicios.')
            else if (listed.isEmpty && !_busy)
              const Padding(
                padding: EdgeInsets.only(top: 24),
                child: Text(
                  'Todavía no hay ejercicios de canto. Pide a tu instructor '
                  'que publique uno o vuelve a intentar con conexión.',
                ),
              ),
            for (final routine in listed)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.graphic_eq),
                title: Text(routine.name),
                subtitle: Text(
                  [
                    if (routine.details.isNotEmpty) routine.details,
                    if (routine.description.isNotEmpty) routine.description,
                  ].join('\n'),
                ),
                isThreeLine: routine.description.isNotEmpty,
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_best[routine.id] case final best?)
                      Chip(label: Text('$best %')),
                    IconButton(
                      tooltip: 'Cantar «${routine.name}»',
                      icon: const Icon(Icons.play_circle_fill),
                      onPressed: _busy ? null : () => _sing(routine),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
