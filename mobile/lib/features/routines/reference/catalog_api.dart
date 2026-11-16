import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../coaching/course.dart';
import 'motion_reference.dart';

class Account {
  const Account(this.id, this.username, this.accessToken);
  final int id;
  final String username, accessToken;
}

/// The access token was rejected; the caller may renew it once and retry.
class SessionExpiredException extends ReferenceException {
  const SessionExpiredException()
    : super('Tu sesión caducó. Vuelve a ingresar con conexión.');
}

/// The server refused a sign-up; [fields] holds its messages per field
/// (`username`, `email`, `password`), already in Spanish.
class RegistrationException extends ReferenceException {
  const RegistrationException(super.message, [this.fields = const {}]);
  final Map<String, String> fields;
}

class LoginResult {
  const LoginResult(this.account, this.refreshToken);
  final Account account;

  /// Absent when the server does not issue one; the session is then memory-only.
  final String? refreshToken;
}

/// Server answer to a summary upload; transient failures throw instead.
class UploadResult {
  const UploadResult.stored() : stored = true, reason = null;
  const UploadResult.rejected(this.reason) : stored = false;
  final bool stored;
  final String? reason;
}

class RoutineItem {
  const RoutineItem(
    this.id,
    this.name, {
    this.style = '',
    this.difficulty = '',
    this.durationMs = 0,
    this.credit = '',
    this.description = '',
    this.curriculumPosition,
  });
  final int id;
  final String name, style, difficulty, credit;

  /// How the step is done, for the learner (may be empty).
  final String description;

  /// Step of the teaching path (generated standard); null for free practice.
  final int? curriculumPosition;

  /// Zero until the master reference has been processed.
  final int durationMs;

  static String _text(Object? value) => value is String ? value.trim() : '';

  factory RoutineItem.fromJson(Map<String, dynamic> json) => RoutineItem(
    positiveInt(json['id']),
    json['name'] as String,
    style: _text(json['style']),
    difficulty: _text(json['difficulty']),
    durationMs: json['duration_ms'] is int && (json['duration_ms'] as int) > 0
        ? json['duration_ms'] as int
        : 0,
    credit: _text(json['credit']),
    description: _text(json['description']),
    curriculumPosition:
        json['curriculum_position'] is int &&
            (json['curriculum_position'] as int) >= 0
        ? json['curriculum_position'] as int
        : null,
  );

  /// Beginner first, unknown levels last.
  int get difficultyRank => switch (difficulty) {
    'BEGINNER' => 0,
    'INTERMEDIATE' => 1,
    'ADVANCED' => 2,
    _ => 3,
  };

  /// Catalog order: by level; inside a level the teaching path in its own
  /// order first, then free practice by name.
  static int byLevel(RoutineItem a, RoutineItem b) {
    final level = a.difficultyRank.compareTo(b.difficultyRank);
    if (level != 0) return level;
    final pa = a.curriculumPosition, pb = b.curriculumPosition;
    if (pa != null && pb != null) return pa.compareTo(pb);
    if (pa != null) return -1;
    if (pb != null) return 1;
    return a.name.compareTo(b.name);
  }

  String get difficultyLabel => switch (difficulty) {
    'BEGINNER' => 'Principiante',
    'INTERMEDIATE' => 'Intermedio',
    'ADVANCED' => 'Avanzado',
    _ => '',
  };

  /// Catalog line: style, level, length and the video credit when known.
  String get details => [
    if (style.isNotEmpty) style,
    if (difficultyLabel.isNotEmpty) difficultyLabel,
    if (durationMs > 0)
      '${(durationMs / 1000).toStringAsFixed(durationMs < 10000 ? 1 : 0)} s',
    if (credit.isNotEmpty) 'Video: $credit',
  ].join(' · ');
}

class CatalogApi {
  CatalogApi(String baseUrl, {http.Client? client})
    : base = Uri.parse('${baseUrl.replaceFirst(RegExp(r'/+$'), '')}/'),
      _client = client ?? http.Client();
  final Uri base;
  final http.Client _client;

  Uri _trusted(String path) {
    final uri = base.resolve(path);
    if (!['http', 'https'].contains(uri.scheme) ||
        uri.origin != base.origin ||
        uri.userInfo.isNotEmpty ||
        !uri.path.startsWith(base.path)) {
      throw const ReferenceException(
        'El servidor devolvió una dirección de descarga no válida.',
      );
    }
    return uri;
  }

  Future<List<int>> _request(
    String path, {
    Account? account,
    Map<String, String>? body,
    int maxBytes = 1024 * 1024,
    bool expiredOn401 = false,
    Set<int> accept = const {200},
    Map<int, String> errors = const {},
  }) async {
    final abort = Completer<void>();
    final timeout = Timer(const Duration(seconds: 30), () => abort.complete());
    try {
      final request = http.AbortableRequest(
        body == null ? 'GET' : 'POST',
        _trusted(path),
        abortTrigger: abort.future,
      )..followRedirects = false;
      request.headers['Accept-Encoding'] = 'identity';
      if (account != null) {
        request.headers['Authorization'] = 'Bearer ${account.accessToken}';
      }
      if (body != null) {
        request.headers['Content-Type'] = 'application/json';
        request.body = jsonEncode(body);
      }
      final response = await _client.send(request);
      if (!accept.contains(response.statusCode)) {
        await response.stream.listen(null).cancel();
        if (response.statusCode == 401 && (account != null || expiredOn401)) {
          throw const SessionExpiredException();
        }
        final custom = errors[response.statusCode];
        if (custom != null) throw ReferenceException(custom);
        throw ReferenceException(switch (response.statusCode) {
          401 => 'Usuario o contraseña incorrectos.',
          403 => 'No tienes acceso a esta rutina.',
          404 =>
            'Esta rutina todavía no tiene una referencia lista o ya no está disponible.',
          429 => 'Demasiados intentos. Espera un minuto y vuelve a intentar.',
          _ => 'No se pudo completar la solicitud al servidor.',
        });
      }
      if ((response.contentLength ?? 0) > maxBytes) {
        await response.stream.listen(null).cancel();
        throw const ReferenceException('La respuesta es demasiado grande.');
      }
      final bytes = <int>[];
      await for (final chunk in response.stream) {
        if (bytes.length + chunk.length > maxBytes) {
          throw const ReferenceException('La respuesta es demasiado grande.');
        }
        bytes.addAll(chunk);
      }
      return bytes;
    } on http.ClientException {
      throw const ReferenceException(
        'No se pudo conectar. Comprueba la conexión y vuelve a intentar.',
      );
    } finally {
      timeout.cancel();
    }
  }

  Future<Map<String, dynamic>> _json(
    String path, {
    Account? account,
    Map<String, String>? body,
    bool expiredOn401 = false,
    Set<int> accept = const {200},
    Map<int, String> errors = const {},
  }) async => object(
    jsonDecode(
      utf8.decode(
        await _request(
          path,
          account: account,
          body: body,
          expiredOn401: expiredOn401,
          accept: accept,
          errors: errors,
        ),
      ),
    ),
  );

  /// Every page of a DRF list, following `next` (bounded, no loops).
  Future<List<Map<String, dynamic>>> _pages(
    String first,
    Account account,
  ) async {
    String? next = first;
    final visited = <String>{};
    final items = <Map<String, dynamic>>[];
    while (next != null) {
      if (!visited.add(next) || visited.length > 50) {
        throw const FormatException('Paginación inválida.');
      }
      final data = await _json(next, account: account);
      final results = data['results'];
      if (results is! List) throw const FormatException('Lista inválida.');
      items.addAll(results.map(object));
      next = data['next'] as String?;
    }
    return items;
  }

  static String? _token(Object? value) =>
      value is String && value.isNotEmpty ? value : null;

  /// Creates a student account; the server always assigns the student role.
  /// [acceptTerms]: the person ticked the terms and privacy policy box; the
  /// server refuses the account otherwise.
  Future<void> register(
    String username,
    String email,
    String password, {
    required bool acceptTerms,
  }) async {
    final abort = Completer<void>();
    final timeout = Timer(const Duration(seconds: 30), () => abort.complete());
    try {
      final request = http.AbortableRequest(
        'POST',
        _trusted('auth/register/'),
        abortTrigger: abort.future,
      )..followRedirects = false;
      request.headers['Content-Type'] = 'application/json';
      request.headers['Accept-Encoding'] = 'identity';
      request.body = jsonEncode({
        'username': username,
        'email': email,
        'password': password,
        'accept_terms': acceptTerms,
      });
      final response = await _client.send(request);
      if (response.statusCode == 201) {
        await response.stream.listen(null).cancel();
        return;
      }
      if (response.statusCode != 400) {
        await response.stream.listen(null).cancel();
        throw ReferenceException(switch (response.statusCode) {
          429 => 'Demasiados registros desde esta red. Espera y reintenta.',
          _ => 'No se pudo crear la cuenta. Intenta más tarde.',
        });
      }
      final bytes = <int>[];
      await for (final chunk in response.stream) {
        if (bytes.length + chunk.length > 64 * 1024) break;
        bytes.addAll(chunk);
      }
      final fields = <String, String>{};
      try {
        final errors = jsonDecode(utf8.decode(bytes));
        if (errors is Map<String, dynamic>) {
          for (final entry in errors.entries) {
            final messages = entry.value;
            if (messages is List && messages.isNotEmpty) {
              fields[entry.key] = messages.whereType<String>().join(' ');
            }
          }
        }
      } on FormatException {
        // Unreadable details: the generic message below still applies.
      }
      throw RegistrationException(
        fields.isEmpty
            ? 'Revisa los datos de la cuenta.'
            : fields.values.join(' '),
        fields,
      );
    } on http.ClientException {
      throw const ReferenceException(
        'No se pudo conectar. Comprueba la conexión y vuelve a intentar.',
      );
    } finally {
      timeout.cancel();
    }
  }

  Future<LoginResult> login(String username, String password) async {
    final tokens = await _json(
      'auth/login/',
      body: {'username': username, 'password': password},
    );
    final token = _token(tokens['access']);
    if (token == null) throw const FormatException('Sesión inválida.');
    final user = await _json('auth/me/', account: Account(0, username, token));
    return LoginResult(
      Account(positiveInt(user['id']), user['username'] as String, token),
      _token(tokens['refresh']),
    );
  }

  /// Exchanges a refresh token. With rotation the server also returns a new one.
  Future<({String access, String? refresh})> refresh(
    String refreshToken,
  ) async {
    final tokens = await _json(
      'auth/token/refresh/',
      body: {'refresh': refreshToken},
      expiredOn401: true,
    );
    final access = _token(tokens['access']);
    if (access == null) throw const FormatException('Sesión inválida.');
    return (access: access, refresh: _token(tokens['refresh']));
  }

  /// Revokes the refresh token on the server; callers treat it as best effort.
  Future<void> logout(String refreshToken) async {
    await _request('auth/logout/', body: {'refresh': refreshToken});
  }

  /// Deletes the signed-in account on the server after it types its password
  /// again; its refresh tokens stop working at once.
  Future<void> deleteAccount(Account account, String password) async {
    await _request(
      'auth/me/delete/',
      account: account,
      body: {'password': password},
      accept: const {204},
      errors: const {
        400: 'La contraseña no es correcta.',
        409:
            'Esta cuenta tiene cursos, rutinas u observaciones a cargo. Pide '
            'a un administrador que los transfiera antes de borrarla.',
        429: 'Demasiados intentos. Espera un momento y vuelve a intentar.',
      },
    );
  }

  /// Emails a link to the web page that sets a new password. The answer is
  /// the same whether or not an account uses [email].
  Future<String> requestPasswordReset(String email) async {
    final data = await _json(
      'auth/password-reset/',
      body: {'email': email},
      accept: const {202},
      errors: const {
        400: 'Escribe un correo válido.',
        429: 'Ya se pidieron varios enlaces para este correo. Espera una hora.',
      },
    );
    final detail = data['detail'];
    return detail is String && detail.isNotEmpty
        ? detail
        : 'Revisa tu correo para cambiar la contraseña.';
  }

  Future<List<RoutineItem>> routines(Account account) async {
    String? next = 'routines/';
    final visited = <String>{};
    final routines = <int, RoutineItem>{};
    while (next != null) {
      if (!visited.add(next) || visited.length > 50) {
        throw const FormatException('Paginación inválida.');
      }
      final data = await _json(next, account: account);
      for (final raw in data['results'] as List) {
        final item = RoutineItem.fromJson(object(raw));
        routines[item.id] = item;
      }
      next = data['next'] as String?;
    }
    return routines.values.toList();
  }

  /// The account's synced practices as the server lists them (all pages).
  Future<List<Map<String, dynamic>>> sessions(Account account) async {
    String? next = 'training/sessions/';
    final visited = <String>{};
    final sessions = <Map<String, dynamic>>[];
    while (next != null) {
      if (!visited.add(next) || visited.length > 50) {
        throw const FormatException('Paginación inválida.');
      }
      final data = await _json(next, account: account);
      final results = data['results'];
      if (results is! List) throw const FormatException('Historial inválido.');
      sessions.addAll(results.map(object));
      next = data['next'] as String?;
    }
    return sessions;
  }

  Future<ReferenceMetadata> metadata(Account account, int routineId) async {
    final metadata = ReferenceMetadata.fromJson(
      await _json('routines/$routineId/reference/', account: account),
    );
    if (metadata.routineId != routineId) {
      throw const FormatException('Rutina no coincidente.');
    }
    return metadata;
  }

  Future<List<int>> download(Account account, ReferenceMetadata metadata) =>
      _request(
        metadata.downloadUrl,
        account: account,
        maxBytes: maxReferenceBytes,
      );

  /// 201 new and 200 already stored are both success (idempotent per UUID).
  /// Rejections are permanent; network, 5xx and other errors throw to retry later.
  Future<UploadResult> uploadSession(
    Account account,
    Map<String, Object?> payload,
  ) async {
    final abort = Completer<void>();
    final timeout = Timer(const Duration(seconds: 30), () => abort.complete());
    try {
      final request = http.AbortableRequest(
        'POST',
        _trusted('training/sessions/'),
        abortTrigger: abort.future,
      )..followRedirects = false;
      request.headers['Authorization'] = 'Bearer ${account.accessToken}';
      request.headers['Content-Type'] = 'application/json';
      request.headers['Accept-Encoding'] = 'identity';
      request.body = jsonEncode(payload);
      final response = await _client.send(request);
      await response.stream.listen(null).cancel();
      return switch (response.statusCode) {
        200 || 201 => const UploadResult.stored(),
        401 => throw const SessionExpiredException(),
        409 => const UploadResult.rejected(
          'El identificador pertenece a otra cuenta.',
        ),
        400 || 403 || 404 => const UploadResult.rejected(
          'El servidor no aceptó el resumen: la rutina o su referencia ya no '
          'están disponibles, o los datos no son compatibles.',
        ),
        _ => throw const ReferenceException(
          'El servidor no pudo guardar el resumen. Se reintentará.',
        ),
      };
    } on http.ClientException {
      throw const ReferenceException(
        'Sin conexión. Los resúmenes se enviarán más tarde.',
      );
    } finally {
      timeout.cancel();
    }
  }

  /// The courses this student joined, with assignments and their progress.
  Future<List<Course>> courses(Account account) async => [
    for (final raw in await _pages('coaching/courses/', account))
      Course.fromJson(raw),
  ];

  /// Joins with the instructor's code; joining twice returns the same course.
  Future<Course> joinCourse(Account account, String code) async =>
      Course.fromJson(
        await _json(
          'coaching/courses/join/',
          account: account,
          body: {'code': code},
          accept: const {200, 201},
          errors: const {
            400: 'Escribe el código que te dio tu instructor.',
            404: 'Código no válido o el curso ya no acepta alumnos.',
            429: 'Demasiados intentos con códigos. Espera un rato.',
          },
        ),
      );

  Future<void> leaveCourse(Account account, int courseId) async {
    await _request(
      'coaching/courses/$courseId/leave/',
      account: account,
      body: const {},
      accept: const {204},
      errors: const {404: 'Ya no perteneces a este curso.'},
    );
  }

  /// Observations of the instructor on this student's synced practices.
  Future<List<InstructorNote>> instructorNotes(Account account) async => [
    for (final raw in await _pages('coaching/notes/', account))
      InstructorNote.fromJson(raw),
  ];

  /// Stream to disk: never allocate the whole (up to 200 MiB) master in memory.
  /// [onProgress] gets the bytes received and the announced size (null when
  /// the server does not send `Content-Length`).
  Stream<List<int>> video(
    Account account,
    ReferenceMetadata metadata, {
    required Future<void> cancelled,
    void Function(int received, int? total)? onProgress,
  }) async* {
    final abort = Completer<void>();
    void stop() {
      if (!abort.isCompleted) abort.complete();
    }

    unawaited(cancelled.then((_) => stop()));
    final timeout = Timer(const Duration(minutes: 5), stop);
    try {
      final request = http.AbortableRequest(
        'GET',
        _trusted(
          'routines/${metadata.routineId}/references/${metadata.version}/video/',
        ),
        abortTrigger: abort.future,
      )..followRedirects = false;
      request.headers['Authorization'] = 'Bearer ${account.accessToken}';
      request.headers['Accept-Encoding'] = 'identity';
      final response = await _client.send(request);
      if (response.statusCode != 200 ||
          (response.contentLength ?? 0) > 200 * 1024 * 1024) {
        await response.stream.listen(null).cancel();
        throw const ReferenceException(
          'Video no disponible. Comprueba tu sesión y que el video no supere 200 MiB.',
        );
      }
      final total = response.contentLength;
      var received = 0;
      onProgress?.call(0, total);
      await for (final chunk in response.stream) {
        received += chunk.length;
        if (received > 200 * 1024 * 1024) {
          throw const ReferenceException('El video supera 200 MiB.');
        }
        yield chunk;
        onProgress?.call(received, total);
      }
    } on http.ClientException {
      throw const ReferenceException(
        'Descarga interrumpida. Vuelve a intentar con conexión.',
      );
    } finally {
      timeout.cancel();
      stop();
    }
  }

  void close() => _client.close();
}
