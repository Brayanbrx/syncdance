import 'dart:async';

import 'package:camera_platform_interface/camera_platform_interface.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

class FakeCameraPlatform extends CameraPlatform {
  static const front = CameraDescription(
    name: 'front',
    lensDirection: CameraLensDirection.front,
    sensorOrientation: 270,
  );
  static const back = CameraDescription(
    name: 'back',
    lensDirection: CameraLensDirection.back,
    sensorOrientation: 90,
  );
  List<CameraDescription> cameras = [back, front];
  String? permissionError;
  Completer<void>? initializeGate;
  final initializationStarted = Completer<void>();
  final errors = StreamController<CameraErrorEvent>.broadcast();
  final frames = <int, StreamController<CameraImageData>>{};
  final created = <int>[];
  final disposed = <int>[];
  CameraDescription? selected;
  MediaSettings? settings;
  ImageFormatGroup? format;
  int streamsStarted = 0;
  int maxActive = 0;
  int _nextId = 0;

  @override
  Future<List<CameraDescription>> availableCameras() async => cameras;

  @override
  Future<int> createCameraWithSettings(
    CameraDescription cameraDescription,
    MediaSettings mediaSettings,
  ) async {
    if (permissionError != null) {
      throw PlatformException(code: permissionError!);
    }
    selected = cameraDescription;
    settings = mediaSettings;
    final id = _nextId++;
    created.add(id);
    final active = created.length - disposed.length;
    if (active > maxActive) maxActive = active;
    frames[id] = StreamController<CameraImageData>.broadcast();
    return id;
  }

  @override
  Future<void> initializeCamera(
    int cameraId, {
    ImageFormatGroup imageFormatGroup = ImageFormatGroup.unknown,
  }) async {
    format = imageFormatGroup;
    if (!initializationStarted.isCompleted) initializationStarted.complete();
    await initializeGate?.future;
  }

  @override
  Stream<CameraInitializedEvent> onCameraInitialized(int cameraId) =>
      Stream.value(
        CameraInitializedEvent(
          cameraId,
          640,
          480,
          ExposureMode.auto,
          false,
          FocusMode.auto,
          false,
        ),
      );

  @override
  Stream<CameraErrorEvent> onCameraError(int cameraId) =>
      errors.stream.where((event) => event.cameraId == cameraId);

  @override
  Stream<DeviceOrientationChangedEvent> onDeviceOrientationChanged() =>
      const Stream.empty();

  @override
  bool supportsImageStreaming() => true;

  @override
  Stream<CameraImageData> onStreamedFrameAvailable(
    int cameraId, {
    CameraImageStreamOptions? options,
  }) {
    streamsStarted++;
    return frames[cameraId]!.stream;
  }

  void emitFrame() => frames[created.last]!.add(
    CameraImageData(
      format: const CameraImageFormat(ImageFormatGroup.nv21, raw: 17),
      planes: [
        CameraImagePlane(
          bytes: Uint8List(640 * 480 * 3 ~/ 2),
          bytesPerRow: 640,
        ),
      ],
      height: 480,
      width: 640,
    ),
  );

  @override
  Widget buildPreview(int cameraId) => const SizedBox(key: Key('fake-preview'));

  @override
  Future<void> dispose(int cameraId) async {
    if (cameraId < 0) return; // Creation was denied before a native ID existed.
    disposed.add(cameraId);
    // Satisfy the plugin's one-shot error listener after its controller disposal.
    errors.add(CameraErrorEvent(cameraId, 'disposed'));
  }

  Future<void> close() async {
    await errors.close();
    for (final stream in frames.values) {
      await stream.close();
    }
  }
}
