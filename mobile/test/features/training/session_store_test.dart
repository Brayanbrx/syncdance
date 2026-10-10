import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:syncdance_mobile/features/training/comparison/follow_mode.dart';
import 'package:syncdance_mobile/features/training/comparison/pose_matcher.dart';
import 'package:syncdance_mobile/features/training/comparison/session_summary.dart';
import 'package:syncdance_mobile/features/training/game/dance_game.dart';
import 'package:syncdance_mobile/features/training/history/saved_session.dart';
import 'package:syncdance_mobile/features/training/history/session_store.dart';

import '../routines/reference_test_samples.dart';
import 'feedback_test.dart' show cue;

SavedSession savedPractice({
  bool evidence = true,
  DateTime? at,
  String? id,
  FollowMode followMode = FollowMode.sameSide,
  GameSummary? game,
}) {
  final accumulator = SessionAccumulator(250, followMode: followMode);
  if (evidence) {
    accumulator.record(0, const PoseMatch(90, 1, 0));
    accumulator.recordFeedback(0, cue('leftElbow_extend'));
  }
  final start = at ?? DateTime.utc(2026, 10, 5, 12);
  return SavedSession(
    id: id ?? newSessionId(),
    routineName: 'Mi rutina',
    reference: metadata(),
    startedAt: start,
    finishedAt: start.add(const Duration(seconds: 10)),
    summary: accumulator.finish(reachedVideoEnd: false),
    game: game,
  );
}

void main() {
  late Directory root;
  late SessionStore store;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('session-store-test-');
    store = SessionStore(root, 'https://server/api|1');
  });
  tearDown(() => root.delete(recursive: true));

  test(
    'round trip after reopening retains real zero, null, versions, feedback and dates',
    () async {
      final first = savedPractice();
      final empty = savedPractice(
        evidence: false,
        at: DateTime.utc(2026, 10, 6),
      );
      await store.save(first);
      await store.save(empty);
      final reopened = SessionStore(root, 'https://server/api|1');
      final history = await reopened.readAll();
      expect(history.unreadable, 0);
      expect(history.sessions.map((s) => s.id), [empty.id, first.id]);
      expect(history.sessions.first.summary.score, isNull);
      final result = history.sessions.last;
      expect(result.summary.score, 0);
      expect(result.summary.coverage, 0.4);
      expect(result.summary.feedback.single.count, 1);
      expect(result.toJson(), first.toJson());
    },
  );

  test(
    'account and server partitions cannot see or delete each other',
    () async {
      final record = savedPractice();
      await store.save(record);
      for (final scope in ['https://server/api|2', 'https://other/api|1']) {
        final other = SessionStore(root, scope);
        expect((await other.readAll()).sessions, isEmpty);
        await other.remove(record.id);
      }
      expect((await store.readAll()).sessions.single.id, record.id);
    },
  );

  test(
    'retry is idempotent; conflicting UUID cannot overwrite original',
    () async {
      final record = savedPractice();
      await store.save(record);
      await store.save(record);
      final data = record.toJson()..['routine_name'] = 'Different';
      await expectLater(
        store.save(SavedSession.fromJson(data)),
        throwsA(isA<FileSystemException>()),
      );
      expect((await store.readAll()).sessions.single.routineName, 'Mi rutina');
      await store.remove(record.id);
      expect((await store.readAll()).sessions, isEmpty);
      await expectLater(store.remove('../escape'), throwsFormatException);
    },
  );

  test(
    'corrupt, mismatched and oversized records are reported; pending files ignored',
    () async {
      final record = savedPractice();
      await store.save(record);
      await File('${store.directory.path}/broken.json').writeAsString('{');
      await File(
        '${store.directory.path}/wrong.json',
      ).writeAsString(jsonEncode(record.toJson()));
      await File(
        '${store.directory.path}/large.json',
      ).writeAsString('x' * (SessionStore.maxFileBytes + 1));
      await File('${store.directory.path}/session.tmp').writeAsString('{');
      final history = await store.readAll();
      expect(history.sessions.single.id, record.id);
      expect(history.unreadable, 3);
    },
  );

  test(
    'rejects unsupported schemas, invalid evidence and incoherent segment totals',
    () {
      for (final corrupt in <void Function(Map<String, dynamic>)>[
        (d) => d['schema'] = 'future',
        (d) => d['finished_at'] = '2020-01-01T00:00:00Z',
        (d) => d['summary']['evaluated_ms'] = 0,
        (d) => d['summary']['score'] = 101,
        (d) => d['summary']['angle_score'] = double.nan,
        (d) => d['summary']['segments'][0]['end_ms'] = 249,
        (d) => d['summary']['feedback'][0]['count'] = -1,
      ]) {
        final data = savedPractice().toJson();
        corrupt(data);
        expect(() => SavedSession.fromJson(data), throwsFormatException);
      }
    },
  );

  test('follow mode round trips and v1 files read as same sides', () {
    final mirror = savedPractice(followMode: FollowMode.mirror);
    final json = mirror.toJson();
    expect(json['schema'], 'local-session-v2');
    expect(SavedSession.fromJson(json).summary.followMode, FollowMode.mirror);
    final legacy =
        jsonDecode(jsonEncode(savedPractice().toJson()))
            as Map<String, dynamic>;
    legacy['schema'] = 'local-session-v1';
    (legacy['summary'] as Map<String, dynamic>).remove('follow_mode');
    expect(
      SavedSession.fromJson(legacy).summary.followMode,
      FollowMode.sameSide,
    );
    final invalid = jsonDecode(jsonEncode(json)) as Map<String, dynamic>;
    (invalid['summary'] as Map<String, dynamic>)['follow_mode'] = 'espejo';
    expect(() => SavedSession.fromJson(invalid), throwsFormatException);
  });

  test('playback speed round trips; files without it are normal speed', () {
    final slow = SavedSession(
      id: newSessionId(),
      routineName: 'Lenta',
      reference: metadata(),
      startedAt: DateTime.utc(2026, 10, 5),
      finishedAt: DateTime.utc(2026, 10, 5, 0, 1),
      summary: SessionAccumulator(
        250,
        playbackSpeed: 0.5,
      ).finish(reachedVideoEnd: true),
    );
    final json = slow.toJson();
    expect(SavedSession.fromJson(json).summary.playbackSpeed, 0.5);
    expect(slow.toUpload()['playback_speed'], 0.5);
    final older = jsonDecode(jsonEncode(json)) as Map<String, dynamic>;
    (older['summary'] as Map<String, dynamic>).remove('playback_speed');
    expect(SavedSession.fromJson(older).summary.playbackSpeed, 1.0);
    (older['summary'] as Map<String, dynamic>)['playback_speed'] = 2.0;
    expect(() => SavedSession.fromJson(older), throwsFormatException);
    expect(
      () => SessionAccumulator(250, playbackSpeed: 0.6),
      throwsArgumentError,
    );
  });
}
