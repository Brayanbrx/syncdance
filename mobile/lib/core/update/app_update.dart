import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';

import '../config/api_config.dart';

/// The version installed on this phone: `versionName` and `versionCode`.
class InstalledVersion {
  const InstalledVersion(this.name, this.code);
  final String name;
  final int code;

  /// Null when the platform cannot tell (tests, unusual builds): then the
  /// app never claims an update it cannot prove.
  static Future<InstalledVersion?> read() async {
    try {
      final info = await PackageInfo.fromPlatform();
      final code = int.tryParse(info.buildNumber);
      return code == null ? null : InstalledVersion(info.version, code);
    } catch (_) {
      return null;
    }
  }
}

/// The newest APK the server publishes (`GET /api/app/latest/`). Outside
/// Google Play nothing updates the app: it asks the server and offers the
/// download, which installs over the current one with the same signing key.
class AppRelease {
  const AppRelease({
    required this.versionName,
    required this.versionCode,
    required this.downloadPath,
    this.sizeBytes,
    this.notes = '',
  });
  final String versionName, downloadPath, notes;
  final int versionCode;
  final int? sizeBytes;

  /// Null for anything unexpected; the download must be a path of this server.
  static AppRelease? tryParse(Object? json) {
    if (json is! Map<String, dynamic>) return null;
    final name = json['version_name'];
    final code = json['version_code'];
    final path = json['download_url'];
    final size = json['size_bytes'];
    final notes = json['notes'] ?? '';
    if (name is! String ||
        name.isEmpty ||
        name.length > 32 ||
        code is! int ||
        code < 1 ||
        path is! String ||
        !path.startsWith('/') ||
        path.startsWith('//') ||
        notes is! String) {
      return null;
    }
    return AppRelease(
      versionName: name,
      versionCode: code,
      downloadPath: path,
      sizeBytes: size is int && size > 0 ? size : null,
      notes: notes.length > 500 ? '${notes.substring(0, 500)}…' : notes,
    );
  }
}

/// Asks the server once whether a newer APK than the installed one exists.
class UpdateChecker {
  UpdateChecker({
    String? apiBase,
    this.client,
    Future<InstalledVersion?> Function()? installed,
  }) : _apiBase = apiBase ?? ApiConfig.baseUrl,
       _installed = installed ?? InstalledVersion.read;
  final String _apiBase;

  /// Injected in tests; otherwise one client per check, closed after it.
  final http.Client? client;
  final Future<InstalledVersion?> Function() _installed;

  static Future<AppRelease?>? _session;
  static http.Client _newClient() => http.Client();

  /// Once per app run: every screen that asks shares the same answer.
  static Future<AppRelease?> session() => _session ??= UpdateChecker().newer();

  /// The published release when it is newer than this phone's; null when it
  /// is not, or when anything fails (offline, no release, unknown version).
  Future<AppRelease?> newer() async {
    final installed = await _installed();
    if (installed == null) return null;
    final web = client ?? _newClient();
    try {
      final base = _apiBase.replaceFirst(RegExp(r'/+$'), '');
      final response = await web
          .get(Uri.parse('$base/app/latest/'))
          .timeout(const Duration(seconds: 10));
      if (response.statusCode != 200) return null;
      final release = AppRelease.tryParse(jsonDecode(response.body));
      return release != null && release.versionCode > installed.code
          ? release
          : null;
    } catch (_) {
      return null;
    } finally {
      if (client == null) web.close();
    }
  }
}
