import 'package:flutter/material.dart';

/// What the learner wants to look at while dancing. Only the layout changes:
/// the master keeps playing (its audio and clock drive the evaluation) and the
/// camera keeps analysing in every view.
enum PracticeView {
  both('Maestro y cámara', Icons.view_agenda_outlined),
  master('Maestro grande', Icons.ondemand_video),
  camera('Solo cámara', Icons.videocam_outlined);

  const PracticeView(this.label, this.icon);
  final String label;
  final IconData icon;
}

/// Shared stage of the game and the step drill.
///
/// Both [master] and [camera] stay mounted in the same order whatever the
/// [view], so switching never restarts the camera or the pose detector: only
/// their rectangles move. In [PracticeView.master] the camera shrinks to a
/// corner (it still checks the framing); in [PracticeView.camera] the master is
/// hidden but keeps playing underneath for the music and the timing.
class PracticeStage extends StatelessWidget {
  const PracticeStage({
    required this.view,
    required this.onViewChanged,
    required this.master,
    required this.camera,
    this.overlays = const [],
    super.key,
  });

  /// Last view picked in this app run; the next practice opens with it.
  static PracticeView lastView = PracticeView.both;

  final PracticeView view;
  final ValueChanged<PracticeView> onViewChanged;
  final Widget master;
  final Widget camera;

  /// Banners, countdown and ratings; drawn over the main area of the view.
  final List<Widget> overlays;

  static const _duration = Duration(milliseconds: 250);

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      final full = Offset.zero & box.biggest;
      final split = box.maxHeight * 0.7;
      final pip = Rect.fromLTWH(
        box.maxWidth * 0.64 - 12,
        box.maxHeight * 0.66 - 12,
        box.maxWidth * 0.36,
        box.maxHeight * 0.34,
      );
      final (Rect masterRect, Rect cameraRect, Rect main) = switch (view) {
        PracticeView.both => (
          Rect.fromLTWH(0, 0, box.maxWidth, split),
          Rect.fromLTWH(0, split, box.maxWidth, box.maxHeight - split),
          Rect.fromLTWH(0, 0, box.maxWidth, split),
        ),
        PracticeView.master => (full, pip, full),
        PracticeView.camera => (full, full, full),
      };
      final cornerCamera = view == PracticeView.master;
      return Stack(
        children: [
          _place(
            masterRect,
            AnimatedOpacity(
              opacity: view == PracticeView.camera ? 0 : 1,
              duration: _duration,
              child: Center(child: master),
            ),
          ),
          _place(
            cameraRect,
            AnimatedContainer(
              duration: _duration,
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                color: Colors.black,
                borderRadius: BorderRadius.circular(cornerCamera ? 14 : 0),
                border: cornerCamera
                    ? Border.all(color: Colors.white70, width: 2)
                    : null,
              ),
              child: camera,
            ),
          ),
          _place(main, Stack(alignment: Alignment.center, children: overlays)),
          Positioned(
            left: 8,
            top: 8,
            child: PracticeViewSelector(
              view: view,
              onChanged: (next) {
                PracticeStage.lastView = next;
                onViewChanged(next);
              },
            ),
          ),
        ],
      );
    },
  );

  Widget _place(Rect rect, Widget child) => AnimatedPositioned.fromRect(
    rect: rect,
    duration: _duration,
    curve: Curves.easeOutCubic,
    child: child,
  );
}

/// Compact three-way switch drawn over dark video.
class PracticeViewSelector extends StatelessWidget {
  const PracticeViewSelector({
    required this.view,
    required this.onChanged,
    super.key,
  });
  final PracticeView view;
  final ValueChanged<PracticeView> onChanged;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: Colors.black54,
      borderRadius: BorderRadius.circular(24),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final option in PracticeView.values)
          IconButton(
            tooltip: option.label,
            isSelected: option == view,
            onPressed: option == view ? null : () => onChanged(option),
            color: Colors.white70,
            selectedIcon: Icon(option.icon, color: Colors.black),
            style: IconButton.styleFrom(
              disabledForegroundColor: Colors.black,
              backgroundColor: option == view ? Colors.white : null,
              disabledBackgroundColor: Colors.white,
            ),
            icon: Icon(option.icon),
          ),
      ],
    ),
  );
}
