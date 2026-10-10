import '../../features/routines/reference/catalog_api.dart';
import '../config/api_config.dart';

/// This increment keeps credentials in memory only; no passwords/tokens on disk.
class CatalogSession {
  CatalogSession(this.api);
  final CatalogApi api;
  Account? account;
  String get cacheScope => '${api.base}|${account!.id}';
  void signOut() => account = null;
}

final catalogSession = CatalogSession(CatalogApi(ApiConfig.baseUrl));
