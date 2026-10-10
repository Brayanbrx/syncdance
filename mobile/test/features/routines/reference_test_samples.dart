import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:syncdance_mobile/features/routines/reference/motion_reference.dart';

List<int> referenceBytes() =>
    File('test/fixtures/references/reference_v1.json.gz').readAsBytesSync();
Map<String, dynamic> referenceDocument() =>
    jsonDecode(
          File('test/fixtures/references/reference_v1.json').readAsStringSync(),
        )
        as Map<String, dynamic>;
Map<String, dynamic> metadataJson({List<int>? bytes, int version = 1}) => {
  'routine': 7,
  'version': version,
  'status': 'READY',
  'checksum_sha256': sha256.convert(bytes ?? referenceBytes()).toString(),
  'source_sha256': 'b' * 64,
  'duration_ms': 250,
  'engine_name': 'fixture',
  'download_url':
      'http://localhost:8000/api/routines/7/references/$version/download/',
  'pose_schema_version': 'pose-v1',
  'feature_schema': 'motion-features-v1',
  'algorithm_version': 'reference-body-v1',
  'sample_rate_hz': 12,
};
ReferenceMetadata metadata({List<int>? bytes, int version = 1}) =>
    ReferenceMetadata.fromJson(metadataJson(bytes: bytes, version: version));
