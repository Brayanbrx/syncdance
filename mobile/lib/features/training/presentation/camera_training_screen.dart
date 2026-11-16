import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../camera/camera_capture.dart';
import '../camera/camera_frame.dart';
import '../pose/pose_benchmark.dart';
import '../pose/pose_estimator.dart';
import '../pose/pose_frame.dart';
import 'camera_pose_preview.dart';
import '../pose/pose_measurements.dart';
import 'pose_measurements_panel.dart';

class CameraTrainingScreen extends StatefulWidget {
  const CameraTrainingScreen({
    this.capture,
    this.createPoseEstimator,
    this.embedded = false,
    this.onFrameCaptured,
    this.onMeasurements,
    this.onInvalidated,
    this.highlightedJoints = const {},
    this.showDetails = true,
    this.onPoseError,
    super.key,
  });

  /// The screen owns and disposes the supplied capture, if provided.
  final CameraCapture? capture;
  final PoseEstimator Function(CameraCapture)? createPoseEstimator;
  final bool embedded;
  final void Function(CameraFrame)? onFrameCaptured;
  final void Function(PoseFrame, PoseMeasurements)? onMeasurements;
  final VoidCallback? onInvalidated;
  final Set<Joint> highlightedJoints;

  /// Embedded hosts with their own guidance (the dance game) hide the side text.
  final bool showDetails;

  /// Lets hosts that hide the details explain a failed detector.
  final ValueChanged<String>? onPoseError;

  @override
  State<CameraTrainingScreen> createState() => _CameraTrainingScreenState();
}

class _CameraTrainingScreenState extends State<CameraTrainingScreen>
    with WidgetsBindingObserver {
  late final CameraCapture _capture;
  PoseEstimator? _estimator;
  StreamSubscription<PoseFrame>? _poseSubscription;
  StreamSubscription<CameraFrame>? _frameSubscription;
  PoseFrame? _pose;
  String? _poseError;
  Timer? _poseExpiry;
  CameraController? _poseCamera;
  DeviceOrientation? _poseOrientation;
  bool _showSkeleton = true;
  final _measurementProcessor = PoseMeasurementProcessor();
  PoseMeasurements? _measurements;

  /// Running device benchmark (Phase 1 record); null when idle.
  PoseBenchmark? _benchmark;
  Timer? _benchmarkTicker;
  int _benchmarkSeconds = 0;

  @override
  void initState() {
    super.initState();
    _capture = widget.capture ?? CameraCapture();
    _capture.addListener(_captureChanged);
    // Register before inference so the video position belongs to capture time.
    _frameSubscription = _capture.frames.listen(
      (frame) => widget.onFrameCaptured?.call(frame),
    );
    WidgetsBinding.instance.addObserver(this);
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    if (lifecycle != null && lifecycle != AppLifecycleState.resumed) {
      unawaited(_capture.setForeground(false));
    }
    unawaited(_capture.start());
    _estimator = widget.createPoseEstimator?.call(_capture);
    _poseSubscription = _estimator?.start().listen(
      (pose) {
        if (mounted && _capture.status == CaptureStatus.streaming) {
          if (!identical(_poseCamera, _capture.controller)) {
            _measurementProcessor.reset();
          }
          _benchmark?.sample(pose, _estimator!.stats);
          final measurements = _measurementProcessor.process(pose);
          if (measurements == null) return;
          _poseExpiry?.cancel();
          setState(() {
            _pose = pose;
            _measurements = measurements;
            _poseCamera?.removeListener(_clearRotatedPose);
            _poseCamera = _capture.controller;
            _poseOrientation = _poseCamera?.value.deviceOrientation;
            _poseCamera?.addListener(_clearRotatedPose);
          });
          widget.onMeasurements?.call(pose, measurements);
          // A frozen result must not look like a live skeleton.
          _poseExpiry = Timer(const Duration(milliseconds: 500), () {
            if (mounted) setState(_resetMeasurements);
          });
        }
      },
      onError: (Object error) {
        if (!mounted) return;
        setState(() {
          _resetMeasurements();
          _poseError = error is UnsupportedError
              ? 'La detección de postura de este paso está disponible en Android.'
              : 'No se pudo analizar la postura. Vuelve a abrir esta pantalla para reintentar.';
        });
        widget.onPoseError?.call(_poseError!);
      },
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      _poseExpiry?.cancel();
      _resetMeasurements();
      // A paused camera would make the 60 s meaningless.
      if (_benchmark != null) setState(_cancelBenchmark);
    }
    unawaited(_capture.setForeground(state == AppLifecycleState.resumed));
  }

  @override
  void dispose() {
    _poseExpiry?.cancel();
    _cancelBenchmark();
    _poseCamera?.removeListener(_clearRotatedPose);
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_poseSubscription?.cancel());
    unawaited(_frameSubscription?.cancel());
    _capture.removeListener(_captureChanged);
    unawaited(_estimator?.stop());
    _capture.dispose();
    super.dispose();
  }

  void _clearRotatedPose() {
    if (mounted &&
        _pose != null &&
        _poseOrientation != _poseCamera?.value.deviceOrientation) {
      _poseExpiry?.cancel();
      setState(_resetMeasurements);
    }
  }

  void _resetMeasurements() {
    _pose = null;
    _measurements = null;
    _measurementProcessor.reset();
    widget.onInvalidated?.call();
  }

  void _captureChanged() {
    if (_capture.status != CaptureStatus.streaming && mounted) {
      _poseExpiry?.cancel();
      setState(() {
        _resetMeasurements();
        _cancelBenchmark();
      });
    }
  }

  void _cancelBenchmark() {
    _benchmarkTicker?.cancel();
    _benchmarkTicker = null;
    _benchmark = null;
  }

  void _startBenchmark() {
    final estimator = _estimator;
    if (estimator == null || _benchmark != null) return;
    setState(() {
      _benchmarkSeconds = 0;
      _benchmark = PoseBenchmark(
        stats: estimator.stats,
        capturedFrames: _capture.receivedFrames,
      );
    });
    _benchmarkTicker = Timer.periodic(const Duration(seconds: 1), (timer) {
      final benchmark = _benchmark;
      if (!mounted || benchmark == null) return timer.cancel();
      _benchmarkSeconds++;
      if (_benchmarkSeconds < PoseBenchmark.duration.inSeconds) {
        setState(() {});
        return;
      }
      final report = benchmark.finish(
        elapsedMs: _benchmarkSeconds * 1000,
        stats: estimator.stats,
        capturedFrames: _capture.receivedFrames,
      );
      setState(_cancelBenchmark);
      unawaited(_showBenchmark(report));
    });
  }

  Future<void> _showBenchmark(PoseBenchmarkReport report) => showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Rendimiento en este teléfono'),
      content: SingleChildScrollView(child: SelectableText(report.text)),
      actions: [
        TextButton(
          onPressed: () async {
            await Clipboard.setData(ClipboardData(text: report.text));
            if (dialogContext.mounted) Navigator.pop(dialogContext);
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text(
                    'Copiado. Pégalo en el registro de validación física.',
                  ),
                ),
              );
            }
          },
          child: const Text('Copiar'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(dialogContext),
          child: const Text('Cerrar'),
        ),
      ],
    ),
  );

  Widget get _benchmarkControl {
    if (_benchmark == null) {
      return TextButton.icon(
        onPressed: _poseError == null ? _startBenchmark : null,
        icon: const Icon(Icons.speed),
        label: const Text('Medir rendimiento 60 s'),
      );
    }
    final left = PoseBenchmark.duration.inSeconds - _benchmarkSeconds;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Flexible(child: Text('Midiendo rendimiento… $left s')),
        TextButton(
          onPressed: () => setState(_cancelBenchmark),
          child: const Text('Cancelar'),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.embedded) {
      return AnimatedBuilder(
        animation: _capture,
        builder: (context, _) => _buildCapture(compact: true),
      );
    }
    return Scaffold(
      appBar: AppBar(
        title: Text(
          _estimator == null ? 'Preparar cámara' : 'Detectar postura',
        ),
        actions: [
          if (_estimator != null)
            IconButton(
              tooltip: _showSkeleton
                  ? 'Ocultar esqueleto'
                  : 'Mostrar esqueleto',
              onPressed: () => setState(() => _showSkeleton = !_showSkeleton),
              icon: Icon(
                _showSkeleton ? Icons.visibility : Icons.visibility_off,
              ),
            ),
        ],
      ),
      body: SafeArea(
        child: AnimatedBuilder(
          animation: _capture,
          builder: (context, _) => LayoutBuilder(
            builder: (context, constraints) => Column(
              children: [
                if (constraints.maxHeight >= 450)
                  const Padding(
                    padding: EdgeInsets.all(16),
                    child: Text(
                      'Coloca el teléfono en un soporte y aléjate hasta ver '
                      'todo tu cuerpo. Esta prueba utiliza solo la cámara.',
                      textAlign: TextAlign.center,
                    ),
                  ),
                Expanded(
                  child: _buildCapture(compact: constraints.maxHeight < 450),
                ),
                if (constraints.maxHeight >= 450)
                  Padding(
                    padding: EdgeInsets.all(16),
                    child: Text(
                      'Vista previa local. No se graba ni se sube video.\n'
                      '${_estimator == null ? 'Comprueba el encuadre antes de entrenar.' : 'Lado anatómico: izquierdo naranja · derecho celeste.\nDetección experimental; todavía no calcula puntuaciones.'}',
                      textAlign: TextAlign.center,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCapture({required bool compact}) {
    switch (_capture.status) {
      case CaptureStatus.idle:
      case CaptureStatus.starting:
        return const Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text('Abriendo cámara…'),
            ],
          ),
        );
      case CaptureStatus.paused:
        return const Center(child: Text('Cámara pausada'));
      case CaptureStatus.unsupported:
        return const Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              'Abre esta prueba en un teléfono Android o iPhone.',
              textAlign: TextAlign.center,
            ),
          ),
        );
      case CaptureStatus.failed:
        return Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.no_photography_outlined, size: 48),
                const SizedBox(height: 16),
                Text(_errorMessage, textAlign: TextAlign.center),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: () => unawaited(_capture.start()),
                  child: const Text('Reintentar'),
                ),
              ],
            ),
          ),
        );
      case CaptureStatus.streaming:
        final camera = _capture.controller!;
        return ValueListenableBuilder<CameraValue>(
          valueListenable: camera,
          builder: (context, value, _) {
            final preview = CameraPosePreview(
              camera: camera,
              pose: _showSkeleton ? _visiblePose : null,
              highlightedJoints: _measurements?.canMeasure == true
                  ? widget.highlightedJoints
                  : const {},
            );
            final details = SingleChildScrollView(
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.all(8),
                    child: Text(
                      _capture.frameWidth == null
                          ? 'Esperando imágenes de la cámara…'
                          : '${_capture.framesPerSecond.toStringAsFixed(1)} imágenes/s'
                                ' · ${_capture.frameWidth} × ${_capture.frameHeight}'
                                ' · ${_capture.receivedFrames} recibidas',
                      textAlign: TextAlign.center,
                    ),
                  ),
                  if (_estimator != null)
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 4,
                      ),
                      child: Text(_poseStatus, textAlign: TextAlign.center),
                    ),
                  if (_estimator != null && !widget.embedded) _benchmarkControl,
                  if (_estimator != null &&
                      _visiblePose != null &&
                      _measurements != null)
                    Padding(
                      padding: const EdgeInsets.all(8),
                      child: PoseMeasurementsPanel(
                        measurements: _measurements!,
                        onRecalibrate: () => setState(_resetMeasurements),
                      ),
                    ),
                ],
              ),
            );
            if (!widget.showDetails) return preview;
            if (compact) {
              return Row(
                children: [
                  Expanded(flex: 3, child: preview),
                  Expanded(flex: 2, child: details),
                ],
              );
            }
            return Column(
              children: [
                Expanded(child: preview),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 200),
                  child: details,
                ),
              ],
            );
          },
        );
    }
  }

  String get _poseStatus {
    if (_poseError != null) return _poseError!;
    final pose = _visiblePose;
    if (pose == null) return 'Iniciando detección corporal…';
    final stats = _estimator!.stats;
    final detection = pose.landmarks.isEmpty
        ? 'No se detecta una persona. Colócate frente a la cámara.'
        : '${pose.landmarks.length} puntos · confianza media '
              '${(pose.poseConfidence * 100).toStringAsFixed(0)} %';
    return '$detection\n'
        '${stats.lastInferenceMs.toStringAsFixed(0)} ms/inferencia · '
        '${stats.processedFrames} analizadas · ${stats.droppedFrames} descartadas';
  }

  PoseFrame? get _visiblePose =>
      identical(_poseCamera, _capture.controller) &&
          _poseOrientation == _capture.controller?.value.deviceOrientation
      ? _pose
      : null;

  String get _errorMessage => switch (_capture.errorCode) {
    'CameraAccessDenied' || 'CameraAccessDeniedWithoutPrompt' =>
      'Necesitamos permiso para mostrar la cámara. Si el aviso ya no aparece, '
          'habilita Cámara para SyncDance en los ajustes del teléfono y reintenta.',
    'CameraAccessRestricted' =>
      'El dispositivo restringe el acceso a la cámara. Revisa sus restricciones.',
    'NoFrontCamera' =>
      'Este dispositivo no tiene una cámara frontal disponible.',
    'StreamUnsupported' =>
      'Esta cámara no permite analizar imágenes en vivo. Prueba en otro teléfono.',
    _ =>
      'No se pudo utilizar la cámara. Cierra otras aplicaciones que la usen '
          'y vuelve a intentar.',
  };
}
