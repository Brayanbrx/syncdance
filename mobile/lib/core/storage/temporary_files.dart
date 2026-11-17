import 'dart:io';

/// Folders the caches write into before publishing a file.
const temporaryPrefixes = ['pending-', 'download-'];

/// Removes the write folders an app killed midway left behind: a partial
/// master video can weigh 200 MB, and nothing else ever deletes it.
///
/// A folder's date is when its partial file was created. Downloads stop
/// after a minute without data, so a folder [olderThan] old belongs to no
/// running download. Best effort: what cannot be deleted waits for the next
/// call.
Future<void> removeStaleTemporaries(
  Directory directory, {
  Duration olderThan = const Duration(hours: 2),
  DateTime? now,
}) async {
  if (!await directory.exists()) return;
  final limit = (now ?? DateTime.now()).subtract(olderThan);
  await for (final entry in directory.list(followLinks: false)) {
    if (entry is! Directory) continue;
    final name = entry.uri.pathSegments.lastWhere(
      (segment) => segment.isNotEmpty,
      orElse: () => '',
    );
    if (!temporaryPrefixes.any(name.startsWith)) continue;
    try {
      if ((await entry.stat()).modified.isBefore(limit)) {
        await entry.delete(recursive: true);
      }
    } on FileSystemException {
      // In use or already gone: the next call tries again.
    }
  }
}
