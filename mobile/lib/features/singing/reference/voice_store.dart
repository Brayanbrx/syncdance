import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../../../core/storage/file_hash.dart';
import '../../../core/storage/temporary_files.dart';
import '../../routines/reference/motion_reference.dart'
    show ReferenceException, object;
import '../practice/vocal_practice.dart';
import 'pitch_reference.dart';

/// A singing routine kept on this phone: its melody and its guide audio.
class SavedVoiceRoutine {
  SavedVoiceRoutine(this.name, this.reference, this.audio);
  final String name;
  final PitchReference reference;
  final File audio;
}

/// One finished singing practice, kept only on this phone.
class VocalRecord {
  VocalRecord({
    required this.routineId,
    required this.routineName,
    required this.version,
    required this.finishedAt,
    required this.overall,
    required this.tuning,
    required this.coverage,
    required this.outOfTune,
    required this.reachedEnd,
  });

  factory VocalRecord.of(
    String name,
    PitchReference reference,
    VocalSummary summary,
    DateTime finishedAt,
  ) => VocalRecord(
    routineId: reference.metadata.routineId,
    routineName: name,
    version: reference.metadata.version,
    finishedAt: finishedAt,
    overall: summary.overall,
    tuning: summary.tuning,
    coverage: summary.coverage,
    outOfTune: summary.outOfTune,
    reachedEnd: summary.reachedEnd,
  );

  factory VocalRecord.fromJson(Map<String, dynamic> json) {
    int? score(Object? value) =>
        value is int && value >= 0 && value <= 100 ? value : null;
    if (json['summary_version'] != VocalSummary.version) {
      throw const FormatException('Versión de resumen desconocida.');
    }
    return VocalRecord(
      routineId: json['routine'] as int,
      routineName: json['routine_name'] as String,
      version: json['version'] as int,
      finishedAt: DateTime.parse(json['finished_at'] as String),
      overall: score(json['overall']),
      tuning: score(json['tuning']),
      coverage: score(json['coverage']),
      outOfTune: json['out_of_tune'] as int,
      reachedEnd: json['reached_end'] == true,
    );
  }

  final int routineId, version, outOfTune;
  final String routineName;
  final DateTime finishedAt;
  final int? overall, tuning, coverage;
  final bool reachedEnd;

  Map<String, dynamic> toJson() => {
    'summary_version': VocalSummary.version,
    'routine': routineId,
    'routine_name': routineName,
    'version': version,
    'finished_at': finishedAt.toUtc().toIso8601String(),
    'overall': overall,
    'tuning': tuning,
    'coverage': coverage,
    'out_of_tune': outOfTune,
    'reached_end': reachedEnd,
  };
}

/// Private files per server and account, like the dance references.
/// Every file is checked by hash when read; a failed write never replaces
/// a good file.
class VoiceStore {
  VoiceStore(Directory root, String accountScope)
    : directory = Directory(
        '${root.path}/${sha256.convert(utf8.encode(accountScope))}',
      );

  static Future<VoiceStore> open(String accountScope) async => VoiceStore(
    Directory('${(await getApplicationSupportDirectory()).path}/voice-v1'),
    accountScope,
  );

  final Directory directory;
  static const maxAudioBytes = 50 * 1024 * 1024;
  static const maxTotalBytes = 256 * 1024 * 1024;
  static const maxHistory = 200;
  static final _validName = RegExp(r'^\d+-\d+-[a-f0-9]{64}\.json$');

  String _stem(PitchReferenceMetadata m) =>
      '${m.routineId}-${m.version}-${m.checksum}';
  File _referenceFile(PitchReferenceMetadata m) =>
      File('${directory.path}/${_stem(m)}.json');
  File _audioFile(PitchReferenceMetadata m) => File(
    '${directory.path}/audio/${m.routineId}-${m.version}-${m.sourceHash}.m4a',
  );
  File get _history => File('${directory.path}/history.json');

  Future<void> _publish(File target, List<int> bytes) async {
    await target.parent.create(recursive: true);
    final pending = await target.parent.createTemp('pending-');
    final temp = File('${pending.path}/publish.tmp');
    try {
      await temp.writeAsBytes(bytes, flush: true);
      await temp.rename(target.path);
    } finally {
      if (await temp.exists()) await temp.delete();
      await pending.delete();
    }
  }

  Future<int> _used() async {
    if (!await directory.exists()) return 0;
    var used = 0;
    await for (final entry in directory.list(
      recursive: true,
      followLinks: false,
    )) {
      if (entry is File) used += await entry.length();
    }
    return used;
  }

  /// Checks the melody, then the audio against its hash, then keeps both.
  Future<SavedVoiceRoutine> save(
    String name,
    PitchReferenceMetadata metadata,
    List<int> reference,
    Stream<List<int>> audio,
  ) async {
    final checked = await compute(_decode, (reference, metadata));
    // A download cut by a killed app would count against the space forever,
    // and this section has no button to free it.
    await removeStaleTemporaries(directory);
    final used = await _used();
    final pending = await (await directory.create(
      recursive: true,
    )).createTemp('download-');
    final partial = File('${pending.path}/audio.tmp');
    try {
      final sink = partial.openWrite();
      var received = 0;
      try {
        await for (final chunk in audio) {
          received += chunk.length;
          if (received > maxAudioBytes || used + received > maxTotalBytes) {
            throw const ReferenceException(
              'No hay espacio para este audio. Elimina otros guardados.',
            );
          }
          sink.add(chunk);
        }
      } finally {
        await sink.close();
      }
      if (received == 0 || await fileSha256(partial) != metadata.sourceHash) {
        throw const ReferenceException(
          'El audio no coincide con esta versión. Descárgalo otra vez.',
        );
      }
      final target = _audioFile(metadata);
      await target.parent.create(recursive: true);
      await partial.rename(target.path);
      await _publish(
        _referenceFile(metadata),
        utf8.encode(
          jsonEncode({
            'name': name,
            'metadata': metadata.toJson(),
            'gzip': base64Encode(reference),
          }),
        ),
      );
      await _removeOtherVersions(metadata);
      return SavedVoiceRoutine(name, checked, target);
    } finally {
      if (await partial.exists()) await partial.delete();
      await pending.delete(recursive: true);
    }
  }

  /// Only the newest version of a routine is practiced, and this section has
  /// no button to delete downloads: older versions go as soon as a new one is
  /// kept, so the space never fills up with them.
  Future<void> _removeOtherVersions(PitchReferenceMetadata kept) async {
    final melody = '${_stem(kept)}.json';
    final sound = _audioFile(kept).uri.pathSegments.last;
    final prefix = '${kept.routineId}-';
    for (final folder in [directory, Directory('${directory.path}/audio')]) {
      if (!await folder.exists()) continue;
      await for (final entry in folder.list(followLinks: false)) {
        final name = entry.uri.pathSegments.last;
        if (entry is File &&
            name.startsWith(prefix) &&
            name != melody &&
            name != sound) {
          try {
            await entry.delete();
          } on FileSystemException {
            // Left for the next save; the newest version is already safe.
          }
        }
      }
    }
  }

  /// Saved routines whose melody and audio still match their hashes.
  Future<List<SavedVoiceRoutine>> readAll() async {
    if (!await directory.exists()) return [];
    final saved = <SavedVoiceRoutine>[];
    await for (final entry in directory.list(followLinks: false)) {
      if (entry is! File || !_validName.hasMatch(entry.uri.pathSegments.last)) {
        continue;
      }
      try {
        final data = object(jsonDecode(await entry.readAsString()));
        final metadata = PitchReferenceMetadata.fromJson(
          object(data['metadata']),
        );
        if (entry.uri.pathSegments.last != '${_stem(metadata)}.json') continue;
        final reference = await compute(_decode, (
          base64Decode(data['gzip'] as String),
          metadata,
        ));
        final audio = _audioFile(metadata);
        if (!await audio.exists() ||
            await fileSha256(audio) != metadata.sourceHash) {
          continue;
        }
        saved.add(SavedVoiceRoutine(data['name'] as String, reference, audio));
      } on Object {
        // A damaged entry is not offered; the others survive.
      }
    }
    saved.sort(
      (a, b) =>
          b.reference.metadata.version.compareTo(a.reference.metadata.version),
    );
    return saved;
  }

  Future<List<VocalRecord>> history() async {
    try {
      if (!await _history.exists()) return [];
      final raw = jsonDecode(await _history.readAsString());
      if (raw is! List) return [];
      final records = <VocalRecord>[];
      for (final item in raw) {
        try {
          records.add(VocalRecord.fromJson(object(item)));
        } on Object {
          // Skip one unreadable record, keep the rest.
        }
      }
      return records;
    } on Object {
      return [];
    }
  }

  /// Newest first; the oldest leave after [maxHistory].
  Future<void> addRecord(VocalRecord record) async {
    final records = [record, ...await history()].take(maxHistory).toList();
    await _publish(
      _history,
      utf8.encode(jsonEncode([for (final r in records) r.toJson()])),
    );
  }
}

PitchReference _decode((List<int>, PitchReferenceMetadata) args) =>
    decodePitchReference(args.$1, args.$2);
