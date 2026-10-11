import 'package:flutter_test/flutter_test.dart';
import 'package:syncdance_mobile/features/routines/learning_path.dart';
import 'package:syncdance_mobile/features/routines/reference/catalog_api.dart';

RoutineItem step(int id, int position, String level) => RoutineItem(
  id,
  'Paso $id',
  difficulty: level,
  curriculumPosition: position,
);

void main() {
  // Catalog order on purpose: stock routines and steps mixed.
  final catalog = [
    step(3, 2, 'INTERMEDIATE'),
    const RoutineItem(9, 'Video libre', difficulty: 'BEGINNER'),
    step(1, 0, 'BEGINNER'),
    step(2, 1, 'BEGINNER'),
  ];

  test('the path holds only curriculum steps, in their order', () {
    final path = LearningPath(catalog, const {});
    expect(path.steps.map((s) => s.id), [1, 2, 3]);
    expect(path.next!.id, 1);
    expect(path.completed, isFalse);
  });

  test('the next step is the first one below three stars', () {
    final path = LearningPath(catalog, const {1: 4, 2: 2, 9: 5});
    expect(path.next!.id, 2);
    expect(path.levels.map((l) => (l.label, l.passed, l.total)), [
      ('Principiante', 1, 2),
      ('Intermedio', 0, 1),
    ]);
  });

  test('once everything is passed, review the step with fewest stars', () {
    final review = LearningPath(catalog, const {1: 5, 2: 3, 3: 4});
    expect(review.completed, isTrue);
    expect(review.next!.id, 2);
    expect(LearningPath(catalog, const {1: 5, 2: 5, 3: 5}).next, isNull);
  });

  test('without positions (older server) there is no path', () {
    final path = LearningPath(const [RoutineItem(9, 'Video libre')], const {});
    expect(path.steps, isEmpty);
    expect(path.next, isNull);
    expect(path.completed, isFalse);
  });

  test('catalog order: level, then the path, then free practice by name', () {
    final items = [
      RoutineItem.fromJson({
        'id': 5,
        'name': 'Alfa libre',
        'difficulty': 'BEGINNER',
        'description': '  ',
      }),
      RoutineItem.fromJson({
        'id': 6,
        'name': 'Zeta paso',
        'difficulty': 'BEGINNER',
        'curriculum_position': 1,
        'description': 'Paso a un lado.',
      }),
      RoutineItem.fromJson({
        'id': 7,
        'name': 'Marcha',
        'difficulty': 'BEGINNER',
        'curriculum_position': 0,
      }),
      RoutineItem.fromJson({
        'id': 8,
        'name': 'Avanzada',
        'difficulty': 'ADVANCED',
        'curriculum_position': -3,
      }),
    ]..sort(RoutineItem.byLevel);
    expect(items.map((i) => i.id), [7, 6, 5, 8]);
    expect(items[1].description, 'Paso a un lado.');
    expect(items[2].description, isEmpty);
    // A negative position is not a path step.
    expect(items[3].curriculumPosition, isNull);
  });
}
