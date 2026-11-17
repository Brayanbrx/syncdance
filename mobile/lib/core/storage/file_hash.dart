import 'dart:io';
import 'dart:isolate';

import 'package:crypto/crypto.dart';

/// SHA-256 of a file, computed outside the UI isolate. A master video is
/// checked every time a routine opens; hashing 100 MB takes a second or more
/// on a modest phone, and the screen would freeze meanwhile.
Future<String> fileSha256(File file) {
  final path = file.path;
  return Isolate.run(
    () async => (await sha256.bind(File(path).openRead()).first).toString(),
  );
}
