import 'dart:async';

import 'package:camera_platform_interface/camera_platform_interface.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:syncdance_mobile/features/training/camera/camera_capture.dart';

import 'fake_camera_platform.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late CameraPlatform original;
  late FakeCameraPlatform platform;
  late CameraCapture capture;
  late List<bool> screenAwakeChanges;

  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    original = CameraPlatform.instance;
    platform = FakeCameraPlatform();
    CameraPlatform.instance = platform;
    screenAwakeChanges = [];
    capture = CameraCapture(
      setScreenAwake: (enabled) async {
        screenAwakeChanges.add(enabled);
      },
    );
  });

  tearDown(() async {
    capture.dispose();
    await capture.settled;
    await platform.close();
    CameraPlatform.instance = original;
    debugDefaultTargetPlatformOverride = null;
  });

  test(
    'front camera streams with audio disabled and releases on stop',
    () async {
      await capture.start();
      expect(platform.selected, FakeCameraPlatform.front);
      expect(platform.settings!.enableAudio, isFalse);
      expect(platform.format, ImageFormatGroup.nv21);
      expect(capture.status, CaptureStatus.streaming);
      expect(screenAwakeChanges, [true]);
      platform.emitFrame();
      await Future<void>.delayed(Duration.zero);
      expect(capture.receivedFrames, 1);
      expect(capture.frameWidth, 640);
      await capture.stop();
      expect(screenAwakeChanges, [true, false]);
      expect(platform.disposed, platform.created);
      expect(platform.frames.values.single.hasListener, isFalse);
      await capture.stop();
      expect(platform.disposed, hasLength(1));
    },
  );

  test(
    'background during initialization does not start a stale stream',
    () async {
      platform.initializeGate = Completer<void>();
      final opening = capture.start();
      await platform.initializationStarted.future;
      final pausing = capture.setForeground(false);
      platform.initializeGate!.complete();
      await opening;
      await pausing;
      expect(capture.status, CaptureStatus.paused);
      expect(platform.streamsStarted, 0);
      expect(platform.disposed, platform.created);
      await capture.setForeground(true);
      expect(capture.status, CaptureStatus.streaming);
      expect(platform.maxActive, 1);
    },
  );

  test(
    'rapid background/resume reopens once and accepts fresh frames',
    () async {
      await capture.start();
      final pausing = capture.setForeground(false);
      final resuming = capture.setForeground(true);
      await pausing;
      await resuming;
      expect(capture.status, CaptureStatus.streaming);
      expect(platform.created, hasLength(2));
      expect(platform.disposed, hasLength(1));
      expect(platform.maxActive, 1);
      platform.emitFrame();
      expect(screenAwakeChanges, [true, false, true]);
      await Future<void>.delayed(Duration.zero);
      expect(capture.receivedFrames, 1);
    },
  );

  test(
    'leaving during initialization disposes without opening a stream',
    () async {
      platform.initializeGate = Completer<void>();
      unawaited(capture.start());
      await platform.initializationStarted.future;
      capture.dispose();
      platform.initializeGate!.complete();
      await capture.settled;
      expect(platform.disposed, platform.created);
      expect(platform.streamsStarted, 0);
      expect(capture.controller, isNull);
    },
  );

  for (final code in [
    'CameraAccessDenied',
    'CameraAccessDeniedWithoutPrompt',
    'CameraAccessRestricted',
  ]) {
    test('$code survives resume and allows an explicit retry', () async {
      platform.permissionError = code;
      await capture.start();
      expect(capture.status, CaptureStatus.failed);
      expect(capture.errorCode, code);
      platform.permissionError = null;
      await capture.setForeground(false);
      await capture.setForeground(true);
      expect(capture.status, CaptureStatus.failed);
      expect(platform.created, isEmpty);
      await capture.start();
      expect(capture.status, CaptureStatus.streaming);
    });
  }

  test(
    'missing front camera is an actionable error, not a rear fallback',
    () async {
      platform.cameras = [FakeCameraPlatform.back];
      await capture.start();
      expect(capture.errorCode, 'NoFrontCamera');
      expect(platform.created, isEmpty);
    },
  );

  test('runtime interruption closes the camera and reports an error', () async {
    await capture.start();
    platform.errors.add(
      CameraErrorEvent(platform.created.last, 'disconnected'),
    );
    await Future<void>.delayed(Duration.zero);
    await capture.settled;
    expect(capture.status, CaptureStatus.failed);
    expect(capture.controller, isNull);
    expect(platform.disposed, platform.created);
  });

  test('desktop does not invoke a missing native plugin', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    await capture.start();
    expect(capture.status, CaptureStatus.unsupported);
    expect(platform.created, isEmpty);
  });

  test('iOS requests BGRA frames without audio', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    await capture.start();
    expect(platform.format, ImageFormatGroup.bgra8888);
    expect(platform.settings!.enableAudio, isFalse);
  });
}
