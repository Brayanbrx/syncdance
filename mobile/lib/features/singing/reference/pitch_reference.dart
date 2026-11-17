import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import '../../routines/reference/motion_reference.dart'
    show BeatGrid, ReferenceException, hashValue, object, positiveInt;

const _noteNames = [
  'C',
  'C#',
  'D',
  'D#',
  'E',
  'F',
  'F#',
  'G',
  'G#',
  'A',
  'A#',
  'B',
];

/// Nearest equal-tempered note, such as "F#3" (A4 = 440 Hz).
String noteName(double midi) {
  final number = (midi + 0.5).floor();
  return '${_noteNames[number % 12]}${number ~/ 12 - 1}';
}

/// Spanish solfege for the learner: "Do", "Fa#".
String solfege(double midi) {
  const names = [
    'Do',
    'Do#',
    'Re',
    'Re#',
    'Mi',
    'Fa',
    'Fa#',
    'Sol',
    'Sol#',
    'La',
    'La#',
    'Si',
  ];
  return names[(midi + 0.5).floor() % 12];
}

/// One note of the melody, in ms of the guide audio.
class SungNote {
  SungNote(this.startMs, this.endMs, this.midi) {
    if (startMs < 0 || endMs <= startMs || !midi.isFinite) {
      throw const FormatException('Nota inválida.');
    }
    if (midi < 0 || midi > 127) throw const FormatException('Nota inválida.');
  }
  final int startMs, endMs;
  final double midi;
  int get durationMs => endMs - startMs;
  String get name => noteName(midi);
}

/// What the server says about a singing routine's reference
/// (`pitch-reference-v1`); anything else is refused before downloading.
class PitchReferenceMetadata {
  PitchReferenceMetadata.fromJson(Map<String, dynamic> json)
    : routineId = positiveInt(json['routine']),
      version = positiveInt(json['version']),
      checksum = hashValue(json['checksum_sha256']),
      sourceHash = hashValue(json['source_sha256']),
      durationMs = positiveInt(json['duration_ms']),
      engine = json['engine_name'] as String,
      downloadUrl = json['download_url'] as String,
      beatGrid = BeatGrid.tryParse(
        json['scoring_profile'],
        positiveInt(json['duration_ms']),
      ) {
    if (json['status'] != 'READY' ||
        json['feature_schema'] != schema ||
        json['algorithm_version'] != algorithm ||
        durationMs > maxDurationMs ||
        engine.isEmpty) {
      throw const ReferenceException(
        'La referencia de canto no está lista o su versión no es compatible.',
      );
    }
  }

  static const schema = 'pitch-reference-v1';
  static const algorithm = 'voice-pitch-v1+voice-notes-v1';
  static const maxDurationMs = 300000;

  final int routineId, version, durationMs;
  final String checksum, sourceHash, engine, downloadUrl;

  /// Present for the generated exercises: the count-in and the tempo.
  final BeatGrid? beatGrid;

  Map<String, dynamic> toJson() => {
    'routine': routineId,
    'version': version,
    'checksum_sha256': checksum,
    'source_sha256': sourceHash,
    'duration_ms': durationMs,
    'engine_name': engine,
    'download_url': downloadUrl,
    'status': 'READY',
    'feature_schema': schema,
    'algorithm_version': algorithm,
    if (beatGrid != null) 'scoring_profile': beatGrid!.toJson(),
  };
}

/// The instructor's melody, checked and ready to sing against.
class PitchReference {
  PitchReference._(this.metadata, this.hopMs, this.frames, this.notes);

  final PitchReferenceMetadata metadata;
  final int hopMs;

  /// The instructor's pitch every [hopMs]; null where there was no voice.
  final List<double?> frames;
  final List<SungNote> notes;

  int get durationMs => metadata.durationMs;

  /// The note that should sound at [ms]; null in a rest.
  SungNote? noteAt(int ms) {
    var low = 0, high = notes.length - 1;
    while (low <= high) {
      final middle = (low + high) >> 1;
      final note = notes[middle];
      if (ms < note.startMs) {
        high = middle - 1;
      } else if (ms >= note.endMs) {
        low = middle + 1;
      } else {
        return note;
      }
    }
    return null;
  }

  /// Lowest and highest note, for drawing.
  (double, double) get range => (
    notes.map((n) => n.midi).reduce(math.min),
    notes.map((n) => n.midi).reduce(math.max),
  );
}

const maxPitchReferenceBytes = 4 * 1024 * 1024;
const _maxExpandedBytes = 16 * 1024 * 1024;

/// Verifies the SHA-256 on the gzip bytes before expanding them, then every
/// field. Throws [ReferenceException]; never returns a partial reference.
PitchReference decodePitchReference(
  List<int> bytes,
  PitchReferenceMetadata metadata,
) {
  if (bytes.isEmpty || bytes.length > maxPitchReferenceBytes) {
    throw const ReferenceException('La referencia de canto no es válida.');
  }
  if (sha256.convert(bytes).toString() != metadata.checksum) {
    throw const ReferenceException(
      'La referencia descargada está dañada. Descárgala otra vez.',
    );
  }
  try {
    final expanded = _gunzip(bytes);
    final data = object(jsonDecode(utf8.decode(expanded)));
    return _read(data, metadata);
  } on ReferenceException {
    rethrow;
  } on Object {
    throw const ReferenceException('La referencia de canto no es válida.');
  }
}

List<int> _gunzip(List<int> bytes) {
  final output = _Limited();
  final decoder = gzip.decoder.startChunkedConversion(output);
  // Small chunks: an oversized expansion stops early, not after the fact.
  for (var start = 0; start < bytes.length; start += 4096) {
    decoder.add(bytes.sublist(start, math.min(start + 4096, bytes.length)));
  }
  decoder.close();
  return output.bytes.takeBytes();
}

class _Limited implements Sink<List<int>> {
  final bytes = BytesBuilder(copy: false);

  @override
  void add(List<int> chunk) {
    if (bytes.length + chunk.length > _maxExpandedBytes) {
      throw const FormatException('Referencia demasiado grande.');
    }
    bytes.add(chunk);
  }

  @override
  void close() {}
}

PitchReference _read(Map<String, dynamic> data, PitchReferenceMetadata m) {
  if (data['schema_version'] != PitchReferenceMetadata.schema ||
      data['pitch_algorithm'] != 'voice-pitch-v1' ||
      data['notes_algorithm'] != 'voice-notes-v1' ||
      data['source_sha256'] != m.sourceHash) {
    throw const ReferenceException(
      'La referencia de canto no corresponde a esta versión.',
    );
  }
  final hop = data['hop_ms'];
  if (hop is! int || hop <= 0 || hop > 1000) {
    throw const FormatException('hop');
  }
  final frames = object(data['frames']);
  final midi = frames['midi'], confidence = frames['confidence'];
  if (midi is! List ||
      confidence is! List ||
      midi.length != confidence.length) {
    throw const FormatException('frames');
  }
  if (data['duration_ms'] != m.durationMs ||
      midi.length * hop != m.durationMs) {
    throw const FormatException('duration');
  }
  final values = <double?>[
    for (final value in midi)
      if (value == null)
        null
      else if (value is num && value.isFinite && value >= 0 && value <= 127)
        value.toDouble()
      else
        throw const FormatException('pitch'),
  ];
  final notes = <SungNote>[];
  for (final raw in data['notes'] as List) {
    final item = object(raw);
    final note = SungNote(
      positiveIntOrZero(item['start_ms']),
      positiveInt(item['end_ms']),
      (item['midi'] as num).toDouble(),
    );
    if ((notes.isNotEmpty && note.startMs < notes.last.endMs) ||
        note.endMs > m.durationMs) {
      throw const FormatException('notes');
    }
    notes.add(note);
  }
  if (notes.isEmpty) throw const FormatException('notes');
  return PitchReference._(m, hop, List.unmodifiable(values), notes);
}

int positiveIntOrZero(Object? value) {
  if (value is int && value >= 0) return value;
  throw const FormatException('Entero inválido.');
}
