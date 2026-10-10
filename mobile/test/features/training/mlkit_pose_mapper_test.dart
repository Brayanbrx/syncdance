import 'package:camera/camera.dart';
import 'package:camera_platform_interface/camera_platform_interface.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart'
    as ml;
import 'package:syncdance_mobile/features/training/camera/camera_frame.dart';
import 'package:syncdance_mobile/features/training/pose/adapters/mlkit_pose_mapper.dart';
import 'package:syncdance_mobile/features/training/pose/pose_frame.dart';

CameraFrame sampleFrame({
  DeviceOrientation orientation = DeviceOrientation.portraitUp,
  ImageFormatGroup format = ImageFormatGroup.nv21,
  int byteCount = 12,
}) => CameraFrame(
  image: CameraImage.fromPlatformInterface(
    CameraImageData(
      format: CameraImageFormat(
        format,
        raw: format == ImageFormatGroup.nv21 ? 17 : 35,
      ),
      planes: [CameraImagePlane(bytes: Uint8List(byteCount), bytesPerRow: 2)],
      height: 4,
      width: 2,
    ),
  ),
  camera: const CameraDescription(
    name: 'front',
    lensDirection: CameraLensDirection.front,
    sensorOrientation: 270,
  ),
  orientation: orientation,
  timestampMs: 100,
  generation: 0,
);

void main() {
  test('compensates front sensor orientation for every device orientation', () {
    final expected = {
      DeviceOrientation.portraitUp: 270,
      DeviceOrientation.landscapeLeft: 0,
      DeviceOrientation.portraitDown: 90,
      DeviceOrientation.landscapeRight: 180,
    };
    for (final entry in expected.entries) {
      expect(
        androidImageRotation(sampleFrame(orientation: entry.key)),
        entry.value,
      );
    }
    final image = androidInputImage(sampleFrame());
    expect(image.metadata!.rotation, ml.InputImageRotation.rotation270deg);
    expect(image.metadata!.format, ml.InputImageFormat.nv21);
  });

  group('compactNv21 (camera_android_camerax 0.7.5+1 padded buffers)', () {
    // 4x2 frame: 8 Y bytes + 4 interleaved VU bytes.
    final frame = Uint8List.fromList(List.generate(12, (i) => i + 1));

    test('a tight buffer is used as is', () {
      expect(identical(compactNv21(frame, 4, 2), frame), isTrue);
    });

    test('rows copied without padding leave a zero tail that is dropped', () {
      final padded = Uint8List(16)..setRange(0, 12, frame);
      expect(compactNv21(padded, 4, 2), frame);
    });

    test('a whole padded Y plane keeps the chroma at the end', () {
      final whole = Uint8List.fromList([
        ...frame.sublist(0, 8),
        99, 99, 99, 99, // Y padding copied with the plane
        ...frame.sublist(8),
      ]);
      expect(compactNv21(whole, 4, 2), frame);
    });

    test('the geometry measured on the Xiaomi 2311DRK48G is accepted', () {
      // 720x480 with a 768 Y row stride: 768 * 479 + 720 + 720 * 480 / 2.
      final device = Uint8List(541392)..[0] = 7;
      final compact = compactNv21(device, 720, 480);
      expect(compact.length, 720 * 480 * 3 ~/ 2);
      expect(compact[0], 7);
    });

    test('short or implausibly long buffers are rejected', () {
      expect(() => compactNv21(Uint8List(11), 4, 2), throwsFormatException);
      expect(() => compactNv21(Uint8List(25), 4, 2), throwsFormatException);
    });
  });

  test('rejects YUV masquerading as NV21 and truncated buffers', () {
    expect(
      () => androidInputImage(sampleFrame(format: ImageFormatGroup.yuv420)),
      throwsFormatException,
    );
    expect(
      () => androidInputImage(sampleFrame(byteCount: 11)),
      throwsFormatException,
    );
  });

  test(
    'all 33 joints preserve anatomical names in rotation-corrected space',
    () {
      final pose = ml.Pose(
        landmarks: {
          for (final type in ml.PoseLandmarkType.values)
            type: ml.PoseLandmark(
              type: type,
              x: 3,
              y: 1,
              z: 0,
              likelihood: 0.8,
            ),
        },
      );
      final frame = canonicalAndroidPose(sampleFrame(), pose);
      expect(frame.landmarks, hasLength(33));
      expect(frame.landmark(Joint.leftShoulder)!.x, 0.75);
      expect(frame.landmark(Joint.leftShoulder)!.y, 0.5);
      expect(frame.imageAspectRatio, 2);
      expect(frame.poseConfidence, closeTo(0.8, 0.00001));
      expect(frame.timestampMs, 100);
      expect(frame.landmark(Joint.leftShoulder)!.z, isNull);
    },
  );

  test(
    'no person remains absent instead of inventing zero-coordinate joints',
    () {
      final frame = canonicalAndroidPose(sampleFrame(), null);
      expect(frame.landmarks, isEmpty);
      expect(frame.poseConfidence, 0);
      expect(frame.landmark(Joint.leftKnee), isNull);
    },
  );
}
