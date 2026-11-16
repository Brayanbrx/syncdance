import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path_provider/path_provider.dart';

/// What one account keeps on this phone: practices and their sync markers
/// (SessionStore), downloaded references and master videos (ReferenceCache,
/// MasterVideoCache). Each lives in a folder named after the hashed scope
/// `server|account id`, so erasing an account touches no other account.
class AccountData {
  AccountData(this.root);
  final Directory root;

  static Future<AccountData> open() async =>
      AccountData(await getApplicationSupportDirectory());

  List<Directory> foldersOf(String scope) {
    final hash = sha256.convert(utf8.encode(scope)).toString();
    return [
      Directory('${root.path}/sessions-v1/$hash'),
      Directory('${root.path}/references-v1/$hash'),
    ];
  }

  Future<void> erase(String scope) async {
    for (final folder in foldersOf(scope)) {
      if (await folder.exists()) await folder.delete(recursive: true);
    }
  }
}
