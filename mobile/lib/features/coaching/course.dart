import '../routines/reference/motion_reference.dart' show object, positiveInt;

String _text(Object? value) => value is String ? value.trim() : '';

DateTime? _time(Object? value) =>
    value is String ? DateTime.tryParse(value)?.toLocal() : null;

/// `YYYY-MM-DD` as a local calendar day (no time zone shift).
DateTime? _day(Object? value) {
  if (value is! String) return null;
  final parsed = DateTime.tryParse(value);
  return parsed == null
      ? null
      : DateTime(parsed.year, parsed.month, parsed.day);
}

int? _stars(Object? value) =>
    value is int && value >= 0 && value <= 5 ? value : null;

/// A routine the instructor assigned, with this student's progress as the
/// server sees it: only practices already synced count.
class CourseAssignment {
  const CourseAssignment({
    required this.id,
    required this.routineId,
    required this.routineName,
    required this.targetStars,
    this.available = true,
    this.dueDate,
    this.instructions = '',
    this.bestStars,
    this.practices = 0,
    this.lastPracticeAt,
    this.completed = false,
    this.overdue = false,
  });

  final int id, routineId, targetStars, practices;
  final String routineName, instructions;

  /// False when the routine left the catalog: it cannot be danced.
  final bool available;
  final DateTime? dueDate, lastPracticeAt;

  /// Best game stars at normal speed; null without any game (not zero).
  final int? bestStars;
  final bool completed, overdue;

  factory CourseAssignment.fromJson(Map<String, dynamic> json) =>
      CourseAssignment(
        id: positiveInt(json['id']),
        routineId: positiveInt(json['routine']),
        routineName: _text(json['routine_name']),
        targetStars: _stars(json['target_stars']) ?? 3,
        available: json['routine_available'] != false,
        dueDate: _day(json['due_date']),
        instructions: _text(json['instructions']),
        bestStars: _stars(json['best_stars']),
        practices: json['practices'] is int ? json['practices'] as int : 0,
        lastPracticeAt: _time(json['last_practice_at']),
        completed: json['completed'] == true,
        overdue: json['overdue'] == true,
      );
}

class Course {
  const Course({
    required this.id,
    required this.name,
    required this.instructor,
    this.assignments = const [],
  });

  final int id;
  final String name, instructor;
  final List<CourseAssignment> assignments;

  int get pending => assignments.where((a) => !a.completed).length;

  factory Course.fromJson(Map<String, dynamic> json) => Course(
    id: positiveInt(json['id']),
    name: _text(json['name']),
    instructor: _text(json['instructor']),
    assignments: [
      for (final raw
          in json['assignments'] is List
              ? json['assignments'] as List
              : const [])
        CourseAssignment.fromJson(object(raw)),
    ],
  );
}

/// An observation the instructor wrote on one of this student's practices.
class InstructorNote {
  const InstructorNote({
    required this.id,
    required this.text,
    required this.author,
    required this.routineName,
    this.practicedAt,
    this.writtenAt,
  });

  final int id;
  final String text, author, routineName;
  final DateTime? practicedAt, writtenAt;

  factory InstructorNote.fromJson(Map<String, dynamic> json) => InstructorNote(
    id: positiveInt(json['id']),
    text: _text(json['text']),
    author: _text(json['author']),
    routineName: _text(json['routine_name']),
    practicedAt: _time(json['session_started_at']),
    writtenAt: _time(json['created_at']),
  );
}
