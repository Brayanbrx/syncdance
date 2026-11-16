import 'package:url_launcher/url_launcher.dart';

import 'api_config.dart';

/// Opens a page of the SyncDance web (privacy policy, terms) in the browser.
/// False when no app could open it.
Future<bool> openWebPage(String path) => launchUrl(
  Uri.parse('${ApiConfig.webBaseUrl}$path'),
  mode: LaunchMode.externalApplication,
);
