import 'reference/catalog_api.dart';

/// A step of the path counts as passed with three stars or more in game mode.
const passStars = 3;

class LevelProgress {
  const LevelProgress(this.label, this.passed, this.total);
  final String label;
  final int passed, total;
}

/// The teaching path (generated standard) over the catalog and the best stars
/// per routine id from the local history. Free-practice routines are not part
/// of it. Without positions (older servers) there is no path.
class LearningPath {
  LearningPath(List<RoutineItem> catalog, this.bestStars)
    : steps = [
        for (final routine in catalog)
          if (routine.curriculumPosition != null) routine,
      ]..sort((a, b) => a.curriculumPosition!.compareTo(b.curriculumPosition!));

  final List<RoutineItem> steps;
  final Map<int, int> bestStars;

  int starsOf(RoutineItem routine) => bestStars[routine.id] ?? 0;
  bool passed(RoutineItem routine) => starsOf(routine) >= passStars;

  /// The first step not passed yet; once all are passed, the one with the
  /// fewest stars below five; null when every step has five stars.
  RoutineItem? get next {
    for (final step in steps) {
      if (!passed(step)) return step;
    }
    RoutineItem? weakest;
    for (final step in steps) {
      if (starsOf(step) < 5 &&
          (weakest == null || starsOf(step) < starsOf(weakest))) {
        weakest = step;
      }
    }
    return weakest;
  }

  bool get completed => steps.isNotEmpty && steps.every(passed);

  /// Passed steps per level, in path order.
  List<LevelProgress> get levels {
    final order = <String>[];
    final passedBy = <String, int>{}, totalBy = <String, int>{};
    for (final step in steps) {
      final label = step.difficultyLabel.isEmpty
          ? 'Otro nivel'
          : step.difficultyLabel;
      if (!totalBy.containsKey(label)) order.add(label);
      totalBy[label] = (totalBy[label] ?? 0) + 1;
      passedBy[label] = (passedBy[label] ?? 0) + (passed(step) ? 1 : 0);
    }
    return [
      for (final label in order)
        LevelProgress(label, passedBy[label]!, totalBy[label]!),
    ];
  }
}
