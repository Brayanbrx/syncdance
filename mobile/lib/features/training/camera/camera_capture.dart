import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import 'camera_frame.dart';

enum CaptureStatus { idle, starting, streaming, paused, failed, unsupported }

/// Owns native camera resources. Transitions are serialized so a background
/// event, retry or route disposal cannot race an unfinished initialization.
class CameraCapture extends ChangeNotifier {
  CameraCapture({Future<void> Function(bool)? setScreenAwake})
    : _setScreenAwake = setScreenAwake ?? _toggleScreenAwake;

  final Future<void> Function(bool) _setScreenAwake;
  bool _screenAwake = false;

  static Future<void> _toggleScreenAwake(bool enabled) =>
      WakelockPlus.toggle(enable: enabled);

  CameraController? _controller;
  CameraController? get controller => _controller;

  CaptureStatus _status = CaptureStatus.idle;
  CaptureStatus get status => _status;
  String? _errorCode;
  String? get errorCode => _errorCode;

  int receivedFrames = 0;
  int? frameWidth;
  int? frameHeight;
  double framesPerSecond = 0;

  bool _requested = false;
  bool _foreground = true;
  bool _disposed = false;
  int _generation = 0;
  int? _controllerGeneration;
  final _frames = StreamController<CameraFrame>.broadcast(sync: true);
  final _captureClock = Stopwatch();
  Stream<CameraFrame> get frames => _frames.stream;

  bool isFrameCurrent(CameraFrame frame) =>
      _isCurrent(frame.generation) &&
      _controller?.value.deviceOrientation == frame.orientation;
  Future<void> _pending = Future<void>.value();
  Timer? _metricsTimer;
  final Stopwatch _window = Stopwatch();
  int _windowFrames = 0;

  bool get _shouldRun => _requested && _foreground && !_disposed;
  bool get isSupported =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  Future<void> start() {
    if (_disposed) return _pending;
    if (!isSupported) {
      _status = CaptureStatus.unsupported;
      _notify();
      return Future<void>.value();
    }
    _requested = true;
    _errorCode = null;
    if (!_foreground) _status = CaptureStatus.paused;
    return _enqueue();
  }

  Future<void> setForeground(bool foreground) {
    if (_disposed || _foreground == foreground) return _pending;
    _foreground = foreground;
    _generation++;
    if (!foreground && _requested) {
      _status = CaptureStatus.paused;
      _notify();
    }
    return _enqueue();
  }

  Future<void> stop() {
    _requested = false;
    _generation++;
    if (!_disposed) {
      _status = CaptureStatus.idle;
      _notify();
    }
    return _enqueue();
  }

  Future<void> _enqueue() {
    _pending = _pending.then((_) => _reconcile());
    return _pending;
  }

  Future<void> _reconcile() async {
    try {
      if (!_shouldRun) {
        await _release();
        return;
      }
      if (_controller != null) {
        if (_controllerGeneration == _generation &&
            _controller!.value.isStreamingImages) {
          return;
        }
        await _release();
      }
      final generation = _generation;
      _status = CaptureStatus.starting;
      _notify();

      final cameras = await availableCameras();
      if (!_isCurrent(generation)) return;
      final front = cameras.where(
        (camera) => camera.lensDirection == CameraLensDirection.front,
      );
      if (front.isEmpty) {
        throw CameraException('NoFrontCamera', 'No front camera available.');
      }

      final camera = CameraController(
        front.first,
        ResolutionPreset.medium,
        enableAudio: false,
        imageFormatGroup: defaultTargetPlatform == TargetPlatform.iOS
            ? ImageFormatGroup.bgra8888
            : ImageFormatGroup.nv21,
      );
      _controller = camera;
      _controllerGeneration = generation;
      await camera.initialize();
      if (!_isCurrent(generation)) {
        await _release();
        return;
      }
      if (!camera.supportsImageStreaming()) {
        throw CameraException('StreamUnsupported', 'Image stream unavailable.');
      }
      camera.addListener(_cameraChanged);
      _screenAwake = true;
      await _setScreenAwake(true);
      if (!_isCurrent(generation)) {
        await _release();
        return;
      }
      _resetMetrics();
      _captureClock.start();
      await camera.startImageStream((image) {
        if (!_isCurrent(generation)) return;
        // No buffers are retained by capture or sent to the backend.
        receivedFrames++;
        _windowFrames++;
        frameWidth = image.width;
        frameHeight = image.height;
        if (_frames.hasListener) {
          _frames.add(
            CameraFrame(
              image: image,
              camera: camera.description,
              orientation: camera.value.deviceOrientation,
              timestampMs: _captureClock.elapsedMilliseconds,
              generation: generation,
            ),
          );
        }
      });
      if (!_isCurrent(generation)) {
        await _release();
        return;
      }
      _status = CaptureStatus.streaming;
      _window.start();
      _metricsTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        final elapsed = _window.elapsedMicroseconds;
        framesPerSecond = elapsed == 0 ? 0 : _windowFrames * 1000000 / elapsed;
        _windowFrames = 0;
        _window.reset();
        _notify();
      });
      _notify();
    } catch (error) {
      debugPrint('Camera capture failed: $error');
      _fail(error is CameraException ? error.code : 'CameraUnavailable');
      try {
        await _release();
      } catch (_) {
        // Preserve the original error if native cleanup also fails.
      }
    }
  }

  bool _isCurrent(int generation) => _shouldRun && generation == _generation;

  void _cameraChanged() {
    if (_controller?.value.hasError ?? false) {
      _fail('CameraUnavailable');
      unawaited(_enqueue());
    }
  }

  void _fail(String code) {
    _requested = false; // Resume must not repeatedly prompt after a denial.
    _generation++;
    _errorCode = code;
    _status = CaptureStatus.failed;
    _notify();
  }

  Future<void> _release() async {
    _metricsTimer?.cancel();
    _metricsTimer = null;
    _window.stop();
    final camera = _controller;
    _controller = null;
    _controllerGeneration = null;
    try {
      if (_screenAwake) {
        _screenAwake = false;
        await _setScreenAwake(false);
      }
    } finally {
      if (camera != null) {
        camera.removeListener(_cameraChanged);
        try {
          if (camera.value.isStreamingImages) await camera.stopImageStream();
        } finally {
          await camera.dispose();
        }
      }
    }
  }

  void _resetMetrics() {
    receivedFrames = 0;
    frameWidth = null;
    frameHeight = null;
    framesPerSecond = 0;
    _windowFrames = 0;
    _window.reset();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  /// Lets owners/tests await completion of pending native cleanup.
  Future<void> get settled => _pending;

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _requested = false;
    _generation++;
    _metricsTimer?.cancel();
    _captureClock.stop();
    unawaited(_enqueue().whenComplete(() => _frames.close()));
    super.dispose();
  }
}
