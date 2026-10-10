import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:syncdance_mobile/features/training/pose/pose_frame.dart';
import 'package:syncdance_mobile/features/training/presentation/pose_overlay.dart';

PoseFrame frame(List<PoseLandmark> points) => PoseFrame(
  timestampMs: 100,
  imageAspectRatio: 0.75,
  landmarks: points,
  poseConfidence: 0.9,
);

PoseLandmark point(Joint joint, double x, double y, {double confidence = 1}) =>
    PoseLandmark(joint: joint, x: x, y: y, confidence: confidence);

void main() {
  test(
    'highlight changes repaint even for the same pose and input set is copied',
    () {
      final pose = frame([point(Joint.leftWrist, 0.2, 0.3)]);
      final targets = {Joint.leftWrist};
      final marked = PoseOverlayPainter(
        pose: pose,
        mirrored: true,
        highlightedJoints: targets,
      );
      targets.clear();
      expect(marked.highlightedJoints, {Joint.leftWrist});
      final plain = PoseOverlayPainter(pose: pose, mirrored: true);
      expect(plain.shouldRepaint(marked), isTrue);
      expect(marked.shouldRepaint(plain), isTrue);
      expect(
        marked.shouldRepaint(
          PoseOverlayPainter(
            pose: pose,
            mirrored: true,
            highlightedJoints: {Joint.leftWrist},
          ),
        ),
        isFalse,
      );
    },
  );
  testWidgets(
    'rings mirror with anatomical joints and omit hidden or unusable targets',
    (tester) async {
      Future<void> draw({
        bool mirrored = true,
        double confidence = 1,
        double x = 0.2,
        Set<Joint> targets = const {Joint.leftWrist},
      }) => tester.pumpWidget(
        MaterialApp(
          home: Center(
            child: SizedBox(
              width: 300,
              height: 400,
              child: CustomPaint(
                painter: PoseOverlayPainter(
                  pose: frame([
                    point(Joint.leftWrist, x, 0.3, confidence: confidence),
                    point(Joint.rightWrist, 0.8, 0.6),
                  ]),
                  mirrored: mirrored,
                  highlightedJoints: targets,
                ),
              ),
            ),
          ),
        ),
      );
      final painter = find.byWidgetPredicate(
        (w) => w is CustomPaint && w.painter is PoseOverlayPainter,
      );
      PaintPattern yellowRing([Offset? center]) => paints
        ..something(
          (method, arguments) =>
              method == #drawCircle &&
              (center == null || arguments[0] == center) &&
              arguments[1] == 8.5 &&
              (arguments[2] as Paint).color.toARGB32() ==
                  Colors.yellowAccent.toARGB32() &&
              (arguments[2] as Paint).style == PaintingStyle.stroke,
        );
      await draw();
      expect(painter, yellowRing(const Offset(240, 120)));
      expect(painter, paintsExactlyCountTimes(#drawCircle, 6));
      await draw(mirrored: false);
      expect(painter, yellowRing(const Offset(60, 120)));
      await draw(confidence: 0.1);
      expect(painter, isNot(yellowRing()));
      await draw(x: 1.2);
      expect(painter, isNot(yellowRing()));
      await draw(targets: {Joint.leftHip});
      expect(painter, isNot(yellowRing()));
      await draw(targets: {});
      expect(painter, isNot(yellowRing()));
    },
  );
  test('front mirror changes display x only, retaining anatomical sides', () {
    final pose = frame([
      point(Joint.leftWrist, 0.2, 0.3),
      point(Joint.rightWrist, 0.8, 0.6),
    ]);
    final front = projectPose(pose, const Size(300, 400), mirrored: true);
    final rear = projectPose(pose, const Size(300, 400), mirrored: false);
    expect(front[Joint.leftWrist], const Offset(240, 120));
    expect(front[Joint.rightWrist]!.dx, closeTo(60, 1e-9));
    expect(rear[Joint.leftWrist], const Offset(60, 120));
    expect(pose.landmark(Joint.leftWrist)!.x, 0.2);
  });

  test('missing, low confidence and out of frame joints are never drawn', () {
    final projected = projectPose(
      frame([
        point(Joint.nose, 0, 0),
        point(Joint.leftWrist, 0.2, 0.3, confidence: 0.49),
        point(Joint.rightWrist, 1.1, 0.3),
        point(Joint.leftAnkle, 0.3, -0.1),
        point(Joint.rightAnkle, 1, 1, confidence: 0.5),
      ]),
      const Size(300, 400),
      mirrored: false,
    );
    expect(projected.keys, [Joint.nose, Joint.rightAnkle]);
    expect(projected[Joint.nose], Offset.zero);
    expect(projected[Joint.rightAnkle], const Offset(300, 400));
    expect(projected.containsKey(Joint.leftHip), isFalse);
  });

  testWidgets('painter draws a limb only when both endpoints are usable', (
    tester,
  ) async {
    Future<void> draw(PoseFrame pose) => tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: SizedBox(
            width: 300,
            height: 400,
            child: CustomPaint(
              painter: PoseOverlayPainter(pose: pose, mirrored: false),
            ),
          ),
        ),
      ),
    );
    final shoulder = point(Joint.leftShoulder, 0.2, 0.3);
    await draw(frame([shoulder, point(Joint.leftElbow, 0.4, 0.5)]));
    final painter = find.byWidgetPredicate(
      (w) => w is CustomPaint && w.painter is PoseOverlayPainter,
    );
    expect(
      painter,
      paints..line(
        p1: const Offset(60, 120),
        p2: const Offset(120, 200),
        color: Colors.orangeAccent,
      ),
    );
    await draw(
      frame([shoulder, point(Joint.leftElbow, 0.4, 0.5, confidence: 0.1)]),
    );
    expect(painter, isNot(paints..line()));
    await draw(frame([]));
    expect(painter, isNot(paints..circle()));
  });
}
