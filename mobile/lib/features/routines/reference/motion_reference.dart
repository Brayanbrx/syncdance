import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import '../../training/pose/body_features.dart';
import '../../training/pose/pose_frame.dart';

const maxReferenceBytes = 8 * 1024 * 1024;
const maxExpandedBytes = 16 * 1024 * 1024;

class ReferenceException implements Exception {
  const ReferenceException(this.message);
  final String message;
  @override
  String toString() => message;
}

Map<String, dynamic> object(Object? value) {
  if (value is! Map<String, dynamic>) {
    throw const FormatException('Objeto inválido.');
  }
  return value;
}

int positiveInt(Object? value) {
  if (value is! int || value <= 0) {
    throw const FormatException('Entero inválido.');
  }
  return value;
}

String hashValue(Object? value) {
  if (value is! String || !RegExp(r'^[a-f0-9]{64}$').hasMatch(value)) {
    throw const FormatException('Checksum inválido.');
  }
  return value;
}

/// Counted beats of a generated routine (`scoring_profile.beat_grid`): the
/// dance game rates one move every [beatsPerMove] beats, on the music.
class BeatGrid {
  const BeatGrid({
    required this.bpm,
    required this.firstBeatMs,
    required this.beatsPerMove,
  });
  static const version = 'beat-grid-v1';
  final double bpm;
  final int firstBeatMs, beatsPerMove;
  double get beatMs => 60000 / bpm;

  /// A missing or malformed grid only disables beat timing: never the download.
  static BeatGrid? tryParse(Object? profile, int durationMs) {
    if (profile is! Map<String, dynamic>) return null;
    final grid = profile['beat_grid'];
    if (grid is! Map<String, dynamic> || grid['version'] != version) {
      return null;
    }
    final bpm = grid['bpm'];
    final first = grid['first_beat_ms'];
    final perMove = grid['beats_per_move'];
    if (bpm is! num || !bpm.isFinite || bpm < 60 || bpm > 180) return null;
    if (first is! int || first < 0 || first >= durationMs) return null;
    if (perMove is! int || perMove < 1 || perMove > 8) return null;
    return BeatGrid(
      bpm: bpm.toDouble(),
      firstBeatMs: first,
      beatsPerMove: perMove,
    );
  }

  Map<String, dynamic> toJson() => {
    'beat_grid': {
      'version': version,
      'bpm': bpm,
      'first_beat_ms': firstBeatMs,
      'beats_per_move': beatsPerMove,
    },
  };
}

class ReferenceMetadata {
  ReferenceMetadata.fromJson(Map<String, dynamic> json)
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
        json['pose_schema_version'] != 'pose-v1' ||
        json['feature_schema'] != 'motion-features-v1' ||
        json['algorithm_version'] != 'reference-body-v1' ||
        json['sample_rate_hz'] != 12 ||
        durationMs > 300000 ||
        engine.isEmpty) {
      throw const ReferenceException(
        'La referencia no está lista o su versión no es compatible.',
      );
    }
  }
  final int routineId, version, durationMs;
  final String checksum, sourceHash, engine, downloadUrl;

  /// Present for generated choreographies; stock videos have no known tempo.
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
    'pose_schema_version': 'pose-v1',
    'feature_schema': 'motion-features-v1',
    'algorithm_version': 'reference-body-v1',
    'sample_rate_hz': 12,
    if (beatGrid != null) 'scoring_profile': beatGrid!.toJson(),
  };
}

typedef ReferencePoint = ({double x, double y});

class MotionSample {
  MotionSample(
    this.timestampMs,
    Map<BodyAngle, double> angles,
    this.quality, {
    Map<Joint, ReferencePoint> normalized = const {},
  }) : angles = Map.unmodifiable(angles),
       normalized = Map.unmodifiable(normalized);
  final int timestampMs;
  final Map<BodyAngle, double> angles;
  final String quality;
  final Map<Joint, ReferencePoint> normalized;
}

class MotionReference {
  MotionReference(this.metadata, List<MotionSample> samples, this.coverage)
    : samples = List.unmodifiable(samples);
  final ReferenceMetadata metadata;
  final List<MotionSample> samples;
  final double coverage;
}

class _LimitedSink implements Sink<List<int>> {
  final bytes = BytesBuilder(copy: false);
  @override
  void add(List<int> data) {
    if (bytes.length + data.length > maxExpandedBytes) {
      throw const ReferenceException(
        'La referencia descomprimida es demasiado grande.',
      );
    }
    bytes.add(data);
  }

  @override
  void close() {}
}

/// SHA is over the original gzip bytes, before decompression or JSON parsing.
MotionReference decodeReference(List<int> bytes, ReferenceMetadata metadata) {
  if (bytes.length > maxReferenceBytes ||
      sha256.convert(bytes).toString() != metadata.checksum) {
    throw const ReferenceException(
      'La referencia está dañada o no coincide con su checksum.',
    );
  }
  final output = _LimitedSink();
  final decoder = gzip.decoder.startChunkedConversion(output);
  for (var start = 0; start < bytes.length; start += 4096) {
    decoder.add(bytes.sublist(start, (start + 4096).clamp(0, bytes.length)));
  }
  decoder.close();
  final data = object(jsonDecode(utf8.decode(output.bytes.takeBytes())));
  if (data['schema'] != 'motion-features-v1' ||
      data['pose_schema'] != 'pose-v1' ||
      data['feature_schema'] != 'body-features-v1' ||
      data['normalization'] != 'body-normalized-v1' ||
      data['algorithm_version'] != 'reference-body-v1' ||
      data['timeline'] != 'video-start-cfr-v1' ||
      data['smoothing'] != 'none' ||
      data['sample_rate_hz'] != 12 ||
      data['duration_ms'] != metadata.durationMs ||
      data['engine'] != metadata.engine ||
      data['source_sha256'] != metadata.sourceHash) {
    throw const ReferenceException(
      'El contenido no coincide con la versión de referencia esperada.',
    );
  }
  hashValue(data['model_sha256']);
  final frames = data['frames'];
  if (frames is! List ||
      frames.isEmpty ||
      frames.length > 3600 ||
      (frames.length * 1000 / 12 - metadata.durationMs).abs() > 0.51) {
    throw const FormatException('Duración o cantidad de muestras inválida.');
  }
  final samples = <MotionSample>[];
  var valid = 0;
  for (var i = 0; i < frames.length; i++) {
    final frame = object(frames[i]);
    final time = frame['t'];
    final quality = frame['quality'];
    if (time is! int ||
        time < 0 ||
        time >= metadata.durationMs ||
        (time - i * 1000 / 12).abs() > 0.51 ||
        ![
          'SINGLE_PERSON',
          'NO_USABLE_POSE',
          'MULTIPLE_PEOPLE',
        ].contains(quality)) {
      throw const FormatException('Timeline o calidad inválida.');
    }
    final angles = <BodyAngle, double>{};
    for (final entry in object(frame['angles']).entries) {
      final value = entry.value;
      if (value is! num || !value.isFinite || value < 0 || value > 180) {
        throw const FormatException('Ángulo inválido.');
      }
      angles[BodyAngle.values.byName(entry.key)] = value.toDouble();
    }
    final normalized = object(frame['normalized']);
    final points = <Joint, ReferencePoint>{};
    for (final entry in normalized.entries) {
      final joint = Joint.values.byName(entry.key);
      final xy = entry.value;
      if (xy is! List ||
          xy.length != 2 ||
          xy.any((v) => v is! num || !v.isFinite)) {
        throw const FormatException('Coordenadas inválidas.');
      }
      points[joint] = (
        x: (xy[0] as num).toDouble(),
        y: (xy[1] as num).toDouble(),
      );
    }
    // Python can normalize a visible torso without enough joints for angles.
    // Such samples remain NO_USABLE_POSE and must not count toward coverage.
    if ((quality == 'SINGLE_PERSON') != angles.isNotEmpty ||
        (quality == 'MULTIPLE_PEOPLE' && normalized.isNotEmpty)) {
      throw const FormatException('Calidad inconsistente.');
    }
    if (angles.isNotEmpty) valid++;
    samples.add(
      MotionSample(time, angles, quality as String, normalized: points),
    );
  }
  final coverage = data['valid_frame_ratio'];
  if (valid == 0 ||
      coverage is! num ||
      !coverage.isFinite ||
      (coverage - valid / samples.length).abs() > 1e-9) {
    throw const FormatException('Cobertura inválida.');
  }
  return MotionReference(metadata, samples, coverage.toDouble());
}
