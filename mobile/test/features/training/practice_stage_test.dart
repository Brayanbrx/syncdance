import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:syncdance_mobile/features/training/presentation/practice_stage.dart';

/// Counts how many times it was mounted: a remount would restart the camera.
class _Probe extends StatefulWidget {
  const _Probe(this.label);
  final String label;
  static var mounts = <String, int>{};
  @override
  State<_Probe> createState() => _ProbeState();
}

class _ProbeState extends State<_Probe> {
  @override
  void initState() {
    super.initState();
    _Probe.mounts.update(widget.label, (n) => n + 1, ifAbsent: () => 1);
  }

  @override
  Widget build(BuildContext context) => SizedBox.expand(
    child: ColoredBox(color: Colors.grey, child: Text(widget.label)),
  );
}

void main() {
  setUp(() {
    _Probe.mounts = {};
    PracticeStage.lastView = PracticeView.both;
  });

  Future<void> pump(WidgetTester tester) async {
    var view = PracticeStage.lastView;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 400,
            height: 600,
            child: StatefulBuilder(
              builder: (context, setState) => PracticeStage(
                view: view,
                onViewChanged: (next) => setState(() => view = next),
                master: const _Probe('master'),
                camera: const _Probe('camera'),
                overlays: const [Text('3')],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Rect rectOf(WidgetTester tester, String label) => tester.getRect(
    find.byWidgetPredicate((w) => w is _Probe && w.label == label),
  );

  testWidgets('switching views moves the camera without restarting it', (
    tester,
  ) async {
    await pump(tester);
    expect(rectOf(tester, 'master').height, closeTo(420, 0.5));
    expect(rectOf(tester, 'camera').top, closeTo(420, 0.5));

    await tester.tap(find.byTooltip('Maestro grande'));
    await tester.pumpAndSettle();
    final corner = rectOf(tester, 'camera');
    expect(corner.width, lessThan(200));
    expect(rectOf(tester, 'master').height, closeTo(600, 0.5));

    await tester.tap(find.byTooltip('Solo cámara'));
    await tester.pumpAndSettle();
    expect(rectOf(tester, 'camera').height, closeTo(600, 0.5));
    final masterOpacity = tester.widget<AnimatedOpacity>(
      find.ancestor(
        of: find.text('master'),
        matching: find.byType(AnimatedOpacity),
      ),
    );
    expect(masterOpacity.opacity, 0);
    expect(find.text('3'), findsOneWidget);

    expect(_Probe.mounts, {'master': 1, 'camera': 1});
    expect(PracticeStage.lastView, PracticeView.camera);
  });

  testWidgets('the next practice opens with the last view', (tester) async {
    PracticeStage.lastView = PracticeView.master;
    await pump(tester);
    expect(rectOf(tester, 'master').height, closeTo(600, 0.5));
    expect(rectOf(tester, 'camera').width, lessThan(200));
  });
}
