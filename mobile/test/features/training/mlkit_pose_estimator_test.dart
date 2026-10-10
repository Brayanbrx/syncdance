import 'dart:async';

import 'package:camera_platform_interface/camera_platform_interface.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:syncdance_mobile/features/training/camera/camera_capture.dart';
import 'package:syncdance_mobile/features/training/pose/adapters/mlkit_pose_estimator.dart';
import 'package:syncdance_mobile/features/training/pose/pose_frame.dart';

import 'fake_camera_platform.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('google_mlkit_pose_detector');
  late CameraPlatform original;
  late FakeCameraPlatform platform;
  late CameraCapture capture;
  late MlKitPoseEstimator estimator;
  late StreamSubscription<PoseFrame> subscription;
  late List<PoseFrame> received;
  late List<Object> errors;
  late Completer<List<dynamic>> result;
  late Completer<void> submitted;
  late int calls;
  late int closes;

  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    original = CameraPlatform.instance;
    platform = FakeCameraPlatform();
    CameraPlatform.instance = platform;
    capture = CameraCapture(setScreenAwake: (_) async {});
    estimator = MlKitPoseEstimator(capture);
    result = Completer<List<dynamic>>();
    submitted = Completer<void>();
    received = [];
    errors = [];
    calls = 0;
    closes = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'vision#closePoseDetector') {
            closes++;
            return null;
          }
          calls++;
          expect(call.arguments['options'], {
            'model': 'base',
            'mode': 'stream',
          });
          if (!submitted.isCompleted) submitted.complete();
          return result.future;
        });
    subscription = estimator.start().listen(received.add, onError: errors.add);
  });

  tearDown(() async {
    if (!result.isCompleted) result.complete([]);
    await subscription.cancel();
    await estimator.stop();
    capture.dispose();
    await capture.settled;
    await platform.close();
    CameraPlatform.instance = original;
    debugDefaultTargetPlatformOverride = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test(
    'busy input is dropped without queuing another native inference',
    () async {
      await capture.settled;
      platform.emitFrame();
      await submitted.future;
      platform.emitFrame();
      platform.emitFrame();
      await Future<void>.delayed(Duration.zero);
      expect(calls, 1);
      expect(estimator.stats.droppedFrames, 2);
      result.complete([]);
      await Future<void>.delayed(Duration.zero);
      expect(received.single.landmarks, isEmpty);
      expect(estimator.stats.processedFrames, 1);
    },
  );

  test(
    'background invalidates pending output and releases the detector',
    () async {
      await capture.settled;
      platform.emitFrame();
      await submitted.future;
      await capture.setForeground(false);
      result.complete([]);
      await Future<void>.delayed(Duration.zero);
      expect(received, isEmpty);
      expect(closes, 1);
      expect(estimator.stats.processedFrames, 0);
    },
  );

  test('native failure is surfaced once and the model is closed', () async {
    await capture.settled;
    platform.emitFrame();
    await submitted.future;
    result.completeError(PlatformException(code: 'model-error'));
    await Future<void>.delayed(Duration.zero);
    platform.emitFrame();
    await Future<void>.delayed(Duration.zero);
    expect(errors, hasLength(1));
    expect(calls, 1);
    expect(closes, 1);
  });

  test(
    'stop waits for inference, drops its output and is safe to repeat',
    () async {
      await capture.settled;
      platform.emitFrame();
      await submitted.future;
      final stopping = estimator.stop();
      result.complete([]);
      await stopping;
      await estimator.stop();
      expect(received, isEmpty);
      expect(closes, 1);
      expect(platform.disposed, platform.created);
    },
  );
}
