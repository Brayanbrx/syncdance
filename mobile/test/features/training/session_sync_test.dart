import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:syncdance_mobile/core/network/catalog_session.dart';
import 'package:syncdance_mobile/core/network/credential_store.dart';
import 'package:syncdance_mobile/features/routines/reference/catalog_api.dart';
import 'package:syncdance_mobile/features/training/game/dance_game.dart';
import 'package:syncdance_mobile/features/training/history/calibration_log.dart';
import 'package:syncdance_mobile/features/training/history/saved_session.dart';
import 'package:syncdance_mobile/features/training/history/session_store.dart';
import 'package:syncdance_mobile/features/training/history/session_sync.dart';

import '../../core/catalog_session_test.dart' show MemoryCredentialStore;
import 'session_store_test.dart' show savedPractice, stepProfile;

/// [record] as `GET training/sessions/` returns it: La Paz offsets, read-only
/// context fields and the server's stars.
Map<String, dynamic> asServer(SavedSession record) {
  String laPaz(DateTime at) => at
      .toUtc()
      .subtract(const Duration(hours: 4))
      .toIso8601String()
      .replaceFirst('Z', '-04:00');
  final upload = record.toUpload();
  return {
    ...upload,
    'started_at': laPaz(record.startedAt),
    'finished_at': laPaz(record.finishedAt),
    'routine_name': record.routineName,
    'reference_metadata': record.reference.toJson(),
    'quality_ratio': record.summary.coverage,
    if (record.game != null)
      'game': {...record.game!.toJson(), 'stars': record.game!.stars},
  };
}

/// Records uploads; [answer] decides the status for each one.
class FakeSessionsServer {
  final uploads = <Map<String, dynamic>>[];
  int Function(Map<String, dynamic> body) answer = (_) => 201;
  bool online = true;
  bool expireNextAccess = false;
  Completer<void>? gate;

  /// What `GET training/sessions/` lists (one page).
  List<Map<String, dynamic>> listed = [];

  late final client = MockClient((request) async {
    if (!online) throw http.ClientException('offline');
    final path = request.url.path;
    if (path.endsWith('auth/token/refresh/')) {
      return http.Response('{"access":"renewed","refresh":"r2"}', 200);
    }
    if (path.endsWith('training/sessions/') && request.method == 'GET') {
      return http.Response(jsonEncode({'results': listed, 'next': null}), 200);
    }
    if (path.endsWith('training/sessions/')) {
      if (expireNextAccess) {
        expireNextAccess = false;
        return http.Response('{}', 401);
      }
      await gate?.future;
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      uploads.add(body);
      return http.Response('{}', answer(body));
    }
    return http.Response('{}', 404);
  });
}

void main() {
  late Directory root;
  late SessionStore store;
  late FakeSessionsServer server;
  late CatalogSession session;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('session-sync-test-');
    store = SessionStore(root, 'http://localhost/api|1');
    server = FakeSessionsServer();
    final api = CatalogApi('http://localhost/api', client: server.client);
    session = CatalogSession(api)..account = const Account(1, 'ana', 'token');
  });
  tearDown(() => root.delete(recursive: true));

  SessionSync sync() => SessionSync(store: store, session: session);

  test('upload payload matches the shared backend contract fixture', () {
    final record = savedPractice(id: '3f2b8c1e-5d4a-4b6f-9a7e-2c1d0e9f8a7b');
    final fixture = jsonDecode(
      File('test/fixtures/sessions/upload_v1.json').readAsStringSync(),
    );
    expect(record.toUpload(), fixture);
  });

  test('a game practice uploads its game block (shared fixture)', () {
    final record = savedPractice(
      id: '9c4e7a21-0b3d-4f58-8e6a-1d2c3b4a5f60',
      game: const GameSummary(
        points: 175,
        maxPoints: 400,
        maxCombo: 2,
        counts: {'perfect': 1, 'great': 1, 'good': 0, 'miss': 1, 'unrated': 1},
      ),
    );
    final fixture = jsonDecode(
      File('test/fixtures/sessions/upload_game_v1.json').readAsStringSync(),
    );
    expect(record.toUpload(), fixture);
    // The phone parses what it uploads with the same rules as the server.
    expect(
      GameSummary.fromJson(fixture['game']).toJson(),
      record.game!.toJson(),
    );
  });

  test('steps and calibration upload as the shared fixture', () {
    final record = savedPractice(
      id: '5b1d3c2a-7e4f-4a8b-9c6d-0e1f2a3b4c5d',
      withSteps: true,
      calibration: const CalibrationCount(3, 2),
    );
    // The backend test sets the reference's steps from this key.
    final expected = jsonDecode(
      jsonEncode({
        '_reference_scoring_profile': stepProfile,
        ...record.toUpload(),
      }),
    );
    final file = File('test/fixtures/sessions/upload_steps_v1.json');
    if (Platform.environment['UPDATE_FIXTURES'] == '1') {
      file.writeAsStringSync(
        '${const JsonEncoder.withIndent('  ').convert(expected)}\n',
      );
    }
    expect(jsonDecode(file.readAsStringSync()), expected);
    expect(record.toUpload()['step_summary_version'], 'step-summary-v1');
  });

  test('a server record rebuilds the same local practice', () {
    for (final record in [
      savedPractice(),
      savedPractice(withSteps: true, calibration: const CalibrationCount(3, 2)),
      savedPractice(evidence: false),
      savedPractice(
        game: const GameSummary(
          points: 175,
          maxPoints: 400,
          maxCombo: 2,
          counts: {
            'perfect': 1,
            'great': 1,
            'good': 0,
            'miss': 1,
            'unrated': 1,
          },
        ),
      ),
    ]) {
      final rebuilt = SavedSession.fromServer(asServer(record));
      expect(rebuilt.toJson(), record.toJson());
    }
  });

  test('restore brings only missing practices, marked as synced', () async {
    final mine = savedPractice(at: DateTime.utc(2026, 10, 1));
    await store.save(mine);
    final other = savedPractice(at: DateTime.utc(2026, 10, 2));
    final broken = asServer(savedPractice())..['duration_ms'] = 999;
    server.listed = [
      {...asServer(mine), 'routine_name': 'Renombrada'},
      asServer(other),
      broken,
    ];
    final report = await sync().restore();
    expect((report.restored, report.skipped), (1, 1));
    final history = await store.readAll();
    expect(history.sessions.map((s) => s.id).toSet(), {mine.id, other.id});
    // Local records are never overwritten by the server copy.
    expect(
      history.sessions.firstWhere((s) => s.id == mine.id).routineName,
      'Mi rutina',
    );
    expect(history.syncOf(other.id).state, SyncState.synced);
    // Restored practices are not uploaded again.
    expect((await sync().run()).synced, 1);
    expect(server.uploads.map((u) => u['id']), [mine.id]);
  });

  test('summary without evidence uploads nulls, never zero', () {
    final upload = savedPractice(evidence: false).toUpload();
    for (final name in [
      'pose_score',
      'angle_score',
      'position_score',
      'mean_error_degrees',
      'mean_position_error',
    ]) {
      expect(upload[name], isNull, reason: name);
    }
    expect(upload['evaluated_ms'], 0);
    expect(upload['feedback_counts'], isEmpty);
  });

  test('pending summaries upload oldest first and are marked synced', () async {
    final older = savedPractice(at: DateTime.utc(2026, 10, 1));
    final newer = savedPractice(at: DateTime.utc(2026, 10, 2));
    await store.save(newer);
    await store.save(older);
    server.answer = (body) => body['id'] == older.id ? 201 : 200;
    final report = await sync().run();
    expect(report.synced, 2);
    expect(server.uploads.map((u) => u['id']), [older.id, newer.id]);
    final history = await SessionStore(
      root,
      'http://localhost/api|1',
    ).readAll();
    expect(history.syncOf(older.id).state, SyncState.synced);
    expect(history.syncOf(newer.id).state, SyncState.synced);
    expect((await sync().run()).synced, 0);
    expect(server.uploads, hasLength(2));
  });

  test(
    'rejections are kept with a reason and never retried automatically',
    () async {
      final record = savedPractice();
      await store.save(record);
      server.answer = (_) => 400;
      final report = await sync().run();
      expect(report.rejected, 1);
      final status = (await store.readAll()).syncOf(record.id);
      expect(status.state, SyncState.rejected);
      expect(status.reason, contains('no aceptó'));
      await sync().run();
      expect(server.uploads, hasLength(1));
      await store.clearSync(record.id);
      server.answer = (_) => 201;
      expect((await sync().run()).synced, 1);
    },
  );

  test('offline stops the queue and keeps everything pending', () async {
    await store.save(savedPractice(at: DateTime.utc(2026, 10, 1)));
    await store.save(savedPractice(at: DateTime.utc(2026, 10, 2)));
    server.online = false;
    final report = await sync().run();
    expect(report.pending, 2);
    expect(report.stoppedBy, contains('Sin conexión'));
    server.online = true;
    expect((await sync().run()).synced, 2);
  });

  test('server errors are transient', () async {
    await store.save(savedPractice());
    server.answer = (_) => 503;
    final report = await sync().run();
    expect(report.pending, 1);
    expect(report.rejected, 0);
  });

  test('a rejected token is renewed and the upload retried', () async {
    final api = CatalogApi('http://localhost/api', client: server.client);
    final credentials = MemoryCredentialStore();
    await credentials.write(
      api.base.toString(),
      const StoredCredentials(5, 'ana', 'r1'),
    );
    final persisted = CatalogSession(api, store: credentials);
    expect(await persisted.restore(), isTrue);
    final store2 = SessionStore(root, persisted.cacheScope);
    await store2.save(savedPractice());
    server.expireNextAccess = true;
    final report = await SessionSync(store: store2, session: persisted).run();
    expect(report.synced, 1);
    expect(server.uploads, hasLength(1));
    expect(persisted.account!.accessToken, 'renewed');
    expect(credentials.values.values.single.refreshToken, 'r2');
  });

  test('concurrent runs share one pass over the queue', () async {
    await store.save(savedPractice());
    server.gate = Completer<void>();
    final first = sync().run();
    final second = sync().run();
    server.gate!.complete();
    final reports = await Future.wait([first, second]);
    expect(identical(reports.first, reports.last), isTrue);
    expect(server.uploads, hasLength(1));
  });

  test(
    'markers survive reopening and unreadable ones count as pending',
    () async {
      final record = savedPractice();
      await store.save(record);
      await store.markSync(record.id, SyncState.synced);
      expect(
        (await SessionStore(
          root,
          'http://localhost/api|1',
        ).readAll()).syncOf(record.id).state,
        SyncState.synced,
      );
      await File(
        '${store.directory.path}/${record.id}.sync',
      ).writeAsString('{');
      final history = await store.readAll();
      expect(history.syncOf(record.id).state, SyncState.pending);
      expect(history.sessions, hasLength(1));
      await store.remove(record.id);
      expect(
        File('${store.directory.path}/${record.id}.sync').existsSync(),
        isFalse,
      );
    },
  );
}
