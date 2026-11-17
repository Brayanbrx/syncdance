import 'package:flutter/material.dart';

import '../config/web_links.dart';
import 'app_update.dart';

/// Tells the student a newer APK exists and downloads it in the browser.
/// Installing it over the current app keeps their practices and routines.
class UpdateBanner extends StatefulWidget {
  const UpdateBanner({this.check, this.openPage, super.key});

  /// Defaults to [UpdateChecker.session] (one request per app run).
  final Future<AppRelease?> Function()? check;

  /// Opens a path of the SyncDance web; defaults to [openWebPage].
  final Future<bool> Function(String path)? openPage;

  @override
  State<UpdateBanner> createState() => _UpdateBannerState();
}

class _UpdateBannerState extends State<UpdateBanner> {
  AppRelease? _release;
  bool _dismissed = false;

  @override
  void initState() {
    super.initState();
    (widget.check ?? UpdateChecker.session)().then((release) {
      if (mounted) setState(() => _release = release);
    });
  }

  Future<void> _download(AppRelease release) async {
    final opened = await (widget.openPage ?? openWebPage)(release.downloadPath);
    if (!opened && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No se pudo abrir el navegador.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final release = _release;
    if (release == null || _dismissed) return const SizedBox.shrink();
    final size = release.sizeBytes == null
        ? ''
        : ' (${(release.sizeBytes! / (1024 * 1024)).toStringAsFixed(0)} MB)';
    final scheme = Theme.of(context).colorScheme;
    return Card(
      color: scheme.tertiaryContainer,
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Hay una versión nueva: ${release.versionName}',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            Text(
              'Descárgala$size e instálala encima de esta: tus prácticas y '
              'rutinas guardadas se conservan.',
            ),
            if (release.notes.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(release.notes),
            ],
            OverflowBar(
              alignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => setState(() => _dismissed = true),
                  child: const Text('Ahora no'),
                ),
                FilledButton(
                  onPressed: () => _download(release),
                  child: const Text('Descargar'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
