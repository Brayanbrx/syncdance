import 'package:flutter/material.dart';

import '../../routines/reference/motion_reference.dart';

/// The count being danced, the way instructors call it: the "5" of the
/// second eight. Nothing before the first counted "1". Hidden from screen
/// readers: a new announcement every beat would drown everything else.
class BeatCount extends StatelessWidget {
  const BeatCount({
    required this.grid,
    required this.positionMs,
    this.color,
    this.size = 40,
    super.key,
  });

  final BeatGrid grid;
  final int positionMs;
  final Color? color;
  final double size;

  @override
  Widget build(BuildContext context) {
    final beat = grid.beatAt(positionMs);
    if (beat == null) return const SizedBox.shrink();
    final style = TextStyle(
      color: color,
      fontWeight: FontWeight.bold,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    return ExcludeSemantics(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('${beat % 8 + 1}', style: style.copyWith(fontSize: size)),
          Text(
            'ocho ${beat ~/ 8 + 1}',
            style: style.copyWith(
              fontSize: size * 0.3,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}
