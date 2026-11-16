import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/network/catalog_session.dart';
import '../routines/reference/motion_reference.dart' show ReferenceException;
import '../training/history/session_sync.dart';
import 'course.dart';

String stars(int count) => '${'★' * count}${'☆' * (5 - count)}';

String _date(DateTime value) {
  String two(int number) => number.toString().padLeft(2, '0');
  return '${two(value.day)}/${two(value.month)}/${value.year}';
}

/// The student's courses: join with the instructor's code, see each
/// assignment against its goal, dance it, and read the instructor's notes.
class CoursesScreen extends StatefulWidget {
  const CoursesScreen({this.session, this.syncPractices, super.key});
  final CatalogSession? session;

  /// Uploads practices saved offline so the progress is current; defaults to
  /// the account's queue. Injectable for tests without storage plugins.
  final Future<void> Function()? syncPractices;

  @override
  State<CoursesScreen> createState() => _CoursesScreenState();
}

class _CoursesScreenState extends State<CoursesScreen> {
  late final CatalogSession _session = widget.session ?? catalogSession;
  final _code = TextEditingController();
  List<Course> _courses = [];
  List<InstructorNote> _notes = [];
  bool _loaded = false;
  bool _busy = false;
  String? _message;

  @override
  void initState() {
    super.initState();
    if (_session.account != null) _load(sync: true);
  }

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  String _error(Object error) => error is ReferenceException
      ? error.message
      : 'No se pudo completar la operación.';

  Future<void> _sync() async {
    try {
      await (widget.syncPractices ?? () => SessionSync.forSession(_session))();
    } catch (_) {
      // Offline or no storage: the server shows what it already has.
    }
  }

  Future<void> _load({bool sync = false, String? done}) async {
    setState(() {
      _busy = true;
      _message = null;
    });
    if (sync) await _sync();
    try {
      final courses = await _session.authorized(_session.api.courses);
      final notes = await _session.authorized(_session.api.instructorNotes);
      if (!mounted) return;
      setState(() {
        _courses = courses;
        _notes = notes;
        _loaded = true;
        _message = done;
      });
    } catch (error) {
      if (mounted) setState(() => _message = _error(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _join() async {
    final code = _code.text.trim();
    if (code.isEmpty) {
      setState(() => _message = 'Escribe el código que te dio tu instructor.');
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final course = await _session.authorized(
        (account) => _session.api.joinCourse(account, code),
      );
      _code.clear();
      await _load(done: 'Te uniste a «${course.name}».');
    } catch (error) {
      if (mounted) {
        setState(() {
          _busy = false;
          _message = _error(error);
        });
      }
    }
  }

  Future<void> _leave(Course course) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Salir del curso'),
        content: Text(
          'Dejarás de ver las tareas de «${course.name}». Tus prácticas no se '
          'borran. Para volver necesitarás el código otra vez.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Salir'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _busy = true);
    try {
      await _session.authorized(
        (account) => _session.api.leaveCourse(account, course.id),
      );
      await _load(done: 'Saliste de «${course.name}».');
    } catch (error) {
      if (mounted) {
        setState(() {
          _busy = false;
          _message = _error(error);
        });
      }
    }
  }

  Future<void> _dance(CourseAssignment assignment) async {
    // The catalog's one-tap Bailar: reference, video and game.
    await context.push('/routines?start=${assignment.routineId}');
    if (mounted) await _load(sync: true);
  }

  Widget _assignmentTile(CourseAssignment assignment) {
    final theme = Theme.of(context);
    final best = assignment.bestStars;
    final due = assignment.dueDate;
    final lines = [
      'Objetivo: ${stars(assignment.targetStars)}'
          '${best == null ? '' : ' · Tu mejor: ${stars(best)}'}',
      if (best == null) 'Todavía sin partidas enviadas.',
      if (due != null)
        assignment.overdue
            ? 'Venció el ${_date(due)}'
            : 'Hasta el ${_date(due)}',
      if (!assignment.available) 'Esta rutina ya no está en el catálogo.',
      if (assignment.instructions.isNotEmpty) assignment.instructions,
    ];
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(
        assignment.completed
            ? Icons.check_circle
            : assignment.overdue
            ? Icons.error_outline
            : Icons.radio_button_unchecked,
        color: assignment.completed
            ? Colors.green.shade700
            : assignment.overdue
            ? theme.colorScheme.error
            : null,
        semanticLabel: assignment.completed
            ? 'Cumplida'
            : assignment.overdue
            ? 'Vencida'
            : 'Pendiente',
      ),
      title: Text(assignment.routineName),
      subtitle: Text(lines.join('\n')),
      isThreeLine: lines.length > 1,
      trailing: IconButton(
        tooltip: 'Bailar «${assignment.routineName}»',
        icon: const Icon(Icons.play_circle_fill),
        onPressed: _busy || !assignment.available
            ? null
            : () => _dance(assignment),
      ),
    );
  }

  Widget _courseCard(Course course) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(course.name, style: theme.textTheme.titleMedium),
                      Text(
                        [
                          if (course.instructor.isNotEmpty)
                            'Instructor: ${course.instructor}',
                          course.assignments.isEmpty
                              ? 'Sin tareas por ahora'
                              : course.pending == 0
                              ? 'Todas las tareas cumplidas'
                              : '${course.pending} de ${course.assignments.length} '
                                    'tareas por cumplir',
                        ].join(' · '),
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Salir de «${course.name}»',
                  icon: const Icon(Icons.logout),
                  onPressed: _busy ? null : () => _leave(course),
                ),
              ],
            ),
            for (final assignment in course.assignments)
              _assignmentTile(assignment),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final account = _session.account;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Mis cursos'),
        actions: [
          if (account != null)
            IconButton(
              tooltip: 'Actualizar',
              icon: const Icon(Icons.refresh),
              onPressed: _busy ? null : () => _load(sync: true),
            ),
        ],
      ),
      body: account == null
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Ingresa con tu cuenta para ver tus cursos.'),
                  FilledButton(
                    onPressed: () => context.go('/login'),
                    child: const Text('Ingresar'),
                  ),
                ],
              ),
            )
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (_busy) const LinearProgressIndicator(),
                if (_message != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Text(_message!),
                  ),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Unirme a un curso',
                          style: theme.textTheme.titleMedium,
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          controller: _code,
                          enabled: !_busy,
                          textCapitalization: TextCapitalization.characters,
                          autocorrect: false,
                          enableSuggestions: false,
                          maxLength: 16,
                          decoration: const InputDecoration(
                            labelText: 'Código del curso',
                            hintText: 'Te lo da tu instructor',
                            counterText: '',
                          ),
                          onSubmitted: (_) => _join(),
                        ),
                        const SizedBox(height: 8),
                        FilledButton(
                          onPressed: _busy ? null : _join,
                          child: const Text('Unirme'),
                        ),
                      ],
                    ),
                  ),
                ),
                if (_loaded && _courses.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 16),
                    child: Text(
                      'Todavía no estás en ningún curso. Pide el código a tu '
                      'instructor.',
                    ),
                  ),
                for (final course in _courses) _courseCard(course),
                if (_loaded) ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(0, 24, 0, 8),
                    child: Text(
                      'Observaciones de tu instructor',
                      style: theme.textTheme.titleMedium,
                    ),
                  ),
                  if (_notes.isEmpty)
                    const Text('Sin observaciones todavía.')
                  else
                    for (final note in _notes)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.chat_bubble_outline),
                        title: Text(note.text),
                        subtitle: Text(
                          [
                            if (note.author.isNotEmpty) note.author,
                            if (note.routineName.isNotEmpty) note.routineName,
                            if (note.practicedAt case final practiced?)
                              'práctica del ${_date(practiced)}',
                          ].join(' · '),
                        ),
                      ),
                  const SizedBox(height: 16),
                  Text(
                    'Cuentan las partidas del modo juego a velocidad normal '
                    'que ya llegaron al servidor. Las guardadas sin conexión '
                    'se envían al abrir esta pantalla.',
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ],
            ),
    );
  }
}
