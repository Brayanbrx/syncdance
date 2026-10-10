import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../../routines/reference/catalog_api.dart';
import '../../routines/reference/master_video_cache.dart';
import '../../routines/reference/motion_reference.dart';
import '../../routines/reference/reference_cache.dart';
import '../playback/reference_timeline.dart';
import '../comparison/follow_mode.dart';
import '../comparison/session_summary.dart';
import '../history/saved_session.dart';
import '../history/session_store.dart';
import 'body_features_panel.dart';
import 'dance_game_screen.dart';
import 'live_comparison_panel.dart';
import 'session_summary_panel.dart';

class MasterPlaybackScreen extends StatefulWidget {
  const MasterPlaybackScreen({
    required this.saved,
    required this.api,
    required this.account,
    required this.cache,
    this.renewAccount,
    this.createController,
    this.sessionStore,
    this.onSessionSaved,
    super.key,
  });
  final SavedReference saved;
  final CatalogApi api;
  final Account account;

  /// Returns a valid token before streaming; the stream cannot retry midway.
  final Future<Account> Function()? renewAccount;
  final MasterVideoCache cache;
  final VideoPlayerController Function(File)? createController;
  final SessionStore? sessionStore;

  /// Background follow-up after a durable save (the sync queue); errors ignored.
  final Future<void> Function()? onSessionSaved;

  @override
  State<MasterPlaybackScreen> createState() => _MasterPlaybackScreenState();
}

class _MasterPlaybackScreenState extends State<MasterPlaybackScreen>
    with WidgetsBindingObserver {
  final _cancelled = Completer<void>();
  VideoPlayerController? _controller;
  bool _busy = true;
  bool _active = true;
  bool _hasVideo = false;
  bool _practice = false;
  SessionAccumulator? _session;
  FollowMode _followMode = FollowMode.mirror;
  double _speed = 1.0;
  MotionReference? _practiceReference;
  SessionSummary? _summary;
  SessionStore? _store;
  SavedSession? _record;
  String? _sessionId;
  DateTime? _startedAt;
  bool _saving = false;
  bool _saved = false;
  bool _discarded = false;
  String? _saveError;
  int _comparisonEpoch = 0;
  double? _dragPosition;
  String? _error;

  /// Master download state; null when not downloading.
  ({double? fraction, String label})? _download;
  ReferenceMetadata get _metadata => widget.saved.reference.metadata;
  ReferenceTimeline get _timeline => ReferenceTimeline(widget.saved.reference);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _prepare(download: false);
  }

  Future<void> _prepare({required bool download}) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final previous = _controller;
      _controller = null;
      previous?.removeListener(_changed);
      await previous?.dispose();
      if (!mounted) return;
      var file = await widget.cache.read(_metadata);
      if (!mounted) return;
      _hasVideo = file != null;
      if (file == null && download) {
        final account =
            await (widget.renewAccount?.call() ?? Future.value(widget.account));
        if (!mounted) return;
        file = await widget.cache.save(
          _metadata,
          widget.api.video(
            account,
            _metadata,
            cancelled: _cancelled.future,
            onProgress: (received, total) {
              final progress = downloadProgress(received, total);
              if (!mounted || progress.label == _download?.label) return;
              setState(() => _download = progress);
            },
          ),
        );
      }
      if (!mounted || file == null) return;
      _hasVideo = true;
      final controller =
          widget.createController?.call(file) ??
          VideoPlayerController.file(
            file,
            // This screen handles lifecycle and never auto-resumes after background.
            videoPlayerOptions: VideoPlayerOptions(
              allowBackgroundPlayback: true,
            ),
          );
      _controller = controller;
      await controller.initialize();
      if (!mounted) return;
      if (_speed != 1.0) await controller.setPlaybackSpeed(_speed);
      if (!mounted) return;
      if (!_timeline.acceptsDuration(controller.value.duration)) {
        throw const ReferenceException(
          'La duración del video no coincide con la referencia. Genera una versión nueva.',
        );
      }
      controller.addListener(_changed);
    } catch (error) {
      final controller = _controller;
      _controller = null;
      await controller?.dispose();
      if (mounted) {
        _error = error is ReferenceException
            ? error.message
            : 'No se pudo abrir el video. Reintenta o usa un maestro MP4 compatible.';
      }
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _download = null;
        });
      }
    }
  }

  void _changed() {
    if (!mounted) return;
    if (_practice &&
        (_controller?.value.isCompleted == true ||
            _controller?.value.hasError == true)) {
      _finishPractice(reachedVideoEnd: _controller?.value.isCompleted == true);
    } else {
      setState(() {});
    }
  }

  Future<void> _startPractice() async {
    if (_busy ||
        _saving ||
        (_record != null && !_saved) ||
        _controller == null) {
      return;
    }
    await _command((c) async {
      await c.pause();
      await c.seekTo(Duration.zero);
    });
    if (!mounted ||
        _error != null ||
        _controller?.value.isInitialized != true) {
      return;
    }
    setState(() {
      _session = SessionAccumulator(
        _metadata.durationMs,
        followMode: _followMode,
        playbackSpeed: _speed,
      );
      _practiceReference = referenceFor(widget.saved.reference, _followMode);
      _summary = null;
      _record = null;
      _saved = false;
      _discarded = false;
      _saveError = null;
      _sessionId = newSessionId();
      _startedAt = DateTime.now().toUtc();
      _practice = true;
      _comparisonEpoch++;
    });
  }

  void _finishPractice({bool reachedVideoEnd = false}) {
    if (!_practice || _session == null) return;
    // Freeze before disposing the camera: late inference cannot change the summary.
    setState(() {
      _summary = _session!.finish(reachedVideoEnd: reachedVideoEnd);
      final now = DateTime.now().toUtc();
      _record = SavedSession(
        id: _sessionId!,
        routineName: widget.saved.name,
        reference: _metadata,
        startedAt: _startedAt!,
        finishedAt: now.isBefore(_startedAt!) ? _startedAt! : now,
        summary: _summary!,
      );
      _practice = false;
      _comparisonEpoch++;
    });
    unawaited(_saveSummary());
  }

  Future<void> _saveSummary() async {
    if (_saving || _saved || _record == null) return;
    setState(() {
      _saving = true;
      _saveError = null;
    });
    try {
      _store ??=
          widget.sessionStore ??
          await SessionStore.open('${widget.api.base}|${widget.account.id}');
      await _store!.save(_record!);
      if (mounted) setState(() => _saved = true);
      unawaited(
        widget.onSessionSaved?.call().then((_) {}, onError: (Object _) {}),
      );
    } catch (_) {
      if (mounted) {
        setState(
          () => _saveError =
              'No se pudo guardar el resumen. Libera espacio y reintenta antes de salir.',
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _command(
    Future<void> Function(VideoPlayerController) action,
  ) async {
    final controller = _controller;
    if (_busy || controller == null) return;
    setState(() {
      _busy = true;
      _comparisonEpoch++;
    });
    try {
      await action(controller);
    } catch (_) {
      if (mounted) {
        _finishPractice();
        _error =
            'No se pudo controlar la reproducción. Vuelve a abrir el video.';
      }
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _dragPosition = null;
        });
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _active = state == AppLifecycleState.resumed;
    if (!_active) {
      unawaited(
        _controller?.pause().catchError((Object _) {}) ?? Future<void>.value(),
      );
    }
    if (mounted) setState(() {});
  }

  /// Full-screen hands-free game on the same cached master and follow mode.
  Future<void> _openGame() async {
    final file = await widget.cache.read(_metadata);
    if (file == null || !mounted) return;
    await _command((c) => c.pause());
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => DanceGameScreen(
          saved: widget.saved,
          videoFile: file,
          storeScope: '${widget.api.base}|${widget.account.id}',
          followMode: _followMode,
          sessionStore: widget.sessionStore,
          onSessionSaved: widget.onSessionSaved,
          createController: widget.createController,
        ),
      ),
    );
  }

  /// Deleting the master is never a side effect of a stray tap: it is off
  /// during a practice and always asks first.
  Future<void> _confirmRemove() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Eliminar video del maestro'),
        content: const Text(
          'Se borrará de este dispositivo. Podrás descargarlo de nuevo con conexión.',
        ),
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
    if (confirmed == true && mounted && !_practice) await _remove();
  }

  Future<void> _remove() async {
    _finishPractice();
    setState(() => _busy = true);
    try {
      final controller = _controller;
      _controller = null;
      controller?.removeListener(_changed);
      await controller?.dispose();
      await widget.cache.remove(_metadata);
      if (mounted) {
        setState(() {
          _hasVideo = false;
          _error = null;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _error = 'No se pudo eliminar el video.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _cancelled.complete();
    _controller?.removeListener(_changed);
    unawaited(_controller?.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    final value = controller?.value;
    final ready =
        value?.isInitialized == true && _error == null && !value!.hasError;
    final sample =
        ready &&
            _active &&
            !_busy &&
            _dragPosition == null &&
            !value.isBuffering &&
            !value.isCompleted
        ? _timeline.at(value.position)
        : null;
    return PopScope(
      canPop:
          !_practice && !_saving && (_record == null || _saved || _discarded),
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (_practice) {
          _finishPractice();
          unawaited(_command((c) => c.pause()));
        }
      },
      child: Scaffold(
        appBar: AppBar(title: Text(widget.saved.name)),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Maestro · versión ${_metadata.version}'),
              if (_summary != null)
                SessionSummaryPanel(
                  summary: _summary!,
                  referenceVersion: _metadata.version,
                ),
              if (_saving) const Text('Guardando resumen…'),
              if (_saved)
                const Text(
                  'Resumen guardado en el historial local. Se enviará al servidor cuando haya conexión.',
                ),
              if (_saveError != null) ...[
                Text(_saveError!),
                TextButton(
                  onPressed: _saving ? null : _saveSummary,
                  child: const Text('Reintentar guardado'),
                ),
                TextButton(
                  onPressed: _saving
                      ? null
                      : () async {
                          setState(() => _discarded = true);
                          // Wait for PopScope to publish the new pop disposition.
                          await WidgetsBinding.instance.endOfFrame;
                          if (context.mounted) Navigator.of(context).pop();
                        },
                  child: const Text('Salir sin guardar'),
                ),
              ],
              if (_download != null)
                Text('Descargando video del maestro… ${_download!.label}'),
              if (_busy) LinearProgressIndicator(value: _download?.fraction),
              if (_error != null || value?.hasError == true)
                Text(
                  _error ??
                      'El reproductor no puede leer este formato de video.',
                ),
              if (ready) ...[
                Center(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      maxHeight:
                          MediaQuery.sizeOf(context).height *
                          (_practice ? 0.22 : 0.45),
                    ),
                    child: AspectRatio(
                      aspectRatio: value.aspectRatio,
                      child: VideoPlayer(controller!),
                    ),
                  ),
                ),
                Text(
                  '${(value.position.inMilliseconds / 1000).toStringAsFixed(1)} / '
                  '${(value.duration.inMilliseconds / 1000).toStringAsFixed(1)} s',
                ),
                Slider(
                  value:
                      (_dragPosition ??
                              value.position.inMilliseconds.toDouble())
                          .clamp(0, value.duration.inMilliseconds.toDouble()),
                  max: value.duration.inMilliseconds.toDouble(),
                  onChanged: _busy || !_active
                      ? null
                      : (position) => setState(() {
                          _dragPosition = position;
                          _comparisonEpoch++;
                        }),
                  onChangeEnd: (position) => _command((c) async {
                    await c.pause();
                    await c.seekTo(Duration(milliseconds: position.round()));
                  }),
                ),
                Wrap(
                  spacing: 12,
                  children: [
                    FilledButton.icon(
                      onPressed: _busy || !_active
                          ? null
                          : () => _command((c) async {
                              if (c.value.isPlaying) {
                                await c.pause();
                              } else {
                                if (c.value.position >= c.value.duration) {
                                  await c.seekTo(Duration.zero);
                                }
                                if (mounted && _active) await c.play();
                              }
                            }),
                      icon: Icon(
                        value.isPlaying ? Icons.pause : Icons.play_arrow,
                      ),
                      label: Text(value.isPlaying ? 'Pausar' : 'Reproducir'),
                    ),
                    TextButton(
                      onPressed: _busy
                          ? null
                          : () => _command((c) async {
                              await c.pause();
                              await c.seekTo(Duration.zero);
                            }),
                      child: const Text('Volver al inicio'),
                    ),
                  ],
                ),
                if (value.isBuffering) const Text('Esperando al reproductor…'),
                if (!_practice)
                  FilledButton.icon(
                    onPressed: _busy || _saving ? null : _openGame,
                    icon: const Icon(Icons.music_note),
                    label: const Text('Bailar (modo juego)'),
                  ),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Row(
                    children: [
                      const Text('Velocidad'),
                      const SizedBox(width: 12),
                      Expanded(
                        child: SegmentedButton<double>(
                          segments: const [
                            ButtonSegment(value: 0.5, label: Text('0,5×')),
                            ButtonSegment(value: 0.75, label: Text('0,75×')),
                            ButtonSegment(value: 1.0, label: Text('1×')),
                          ],
                          selected: {_speed},
                          // A practice keeps one speed; summaries never mix them.
                          onSelectionChanged: _practice || _busy
                              ? null
                              : (selection) {
                                  final speed = selection.single;
                                  setState(() => _speed = speed);
                                  unawaited(
                                    _command((c) => c.setPlaybackSpeed(speed)),
                                  );
                                },
                        ),
                      ),
                    ],
                  ),
                ),
                if (_speed != 1.0)
                  const Text(
                    'Modo aprender: el maestro va más lento. Estas prácticas '
                    'se guardan aparte y no cuentan para tu mejor marca a velocidad normal.',
                  ),
                SwitchListTile(
                  title: const Text('Seguir como espejo'),
                  subtitle: Text(
                    _followMode == FollowMode.mirror
                        ? 'Si el maestro te mira de frente: tu derecha sigue a su izquierda.'
                        : 'Mismos lados: para un maestro filmado de espaldas.',
                  ),
                  value: _followMode == FollowMode.mirror,
                  onChanged: _practice
                      ? null
                      : (mirror) => setState(
                          () => _followMode = mirror
                              ? FollowMode.mirror
                              : FollowMode.sameSide,
                        ),
                ),
                TextButton.icon(
                  onPressed:
                      _busy ||
                          _saving ||
                          (!_practice && _record != null && !_saved)
                      ? null
                      : _practice
                      ? () async {
                          _finishPractice();
                          await _command((c) => c.pause());
                        }
                      : _startPractice,
                  icon: Icon(_practice ? Icons.videocam_off : Icons.videocam),
                  label: Text(
                    _practice
                        ? 'Finalizar práctica'
                        : _summary == null
                        ? 'Practicar con cámara'
                        : 'Repetir práctica',
                  ),
                ),
                if (_practice)
                  LiveComparisonPanel(
                    player: controller,
                    reference: _practiceReference!,
                    followMode: _session!.followMode,
                    enabled: !_busy && _active && _dragPosition == null,
                    epoch: _comparisonEpoch,
                    session: _session,
                  ),
                const SizedBox(height: 16),
                if (sample == null)
                  const Text('Sin muestra técnica en esta posición.')
                else if (sample.angles.isEmpty)
                  const Text(
                    'El maestro no tiene medidas utilizables en este tramo.',
                  )
                else ...[
                  const Text('Medidas del maestro'),
                  BodyFeaturesPanel(angles: sample.angles),
                ],
              ] else if (!_busy)
                FilledButton(
                  onPressed: () => _prepare(download: true),
                  child: Text(
                    _hasVideo
                        ? 'Reintentar reproducción'
                        : 'Descargar video y abrir',
                  ),
                ),
              if (_hasVideo)
                TextButton.icon(
                  onPressed: _busy || _practice ? null : _confirmRemove,
                  icon: const Icon(Icons.delete_outline),
                  label: const Text('Eliminar video guardado'),
                ),
              const SizedBox(height: 16),
              const Text(
                'El video descargado se puede reproducir sin conexión en esta sesión. '
                'Practicar con cámara compara seis ángulos y doce posiciones corporales mientras reproduces el maestro. '
                'La similitud es experimental; no es una evaluación técnica validada.',
              ),
            ],
          ),
        ),
      ),
    );
  }
}
