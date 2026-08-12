import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Resolves a folder BentaGo owns, creating it if it does not exist yet.
///
/// On Android this is app-scoped external storage: visible to the user from any
/// file manager, needing no storage permission on any modern version, and it
/// survives app updates. Everywhere else it is the documents directory.
///
/// The trade-off on Android is worth stating plainly: this folder is deleted
/// when the app is uninstalled and it goes with the phone if the phone does.
/// Anything that matters long term has to leave the device.
///
/// [override] is the test seam -- it is returned as-is, without the
/// `BentaGo/<subfolder>` suffix, so a test can point a whole service at a temp
/// directory.
Future<Directory> appOwnedDirectory(
  String subfolder, {
  Directory? override,
}) async {
  if (override != null) {
    if (!await override.exists()) await override.create(recursive: true);
    return override;
  }

  Directory base;
  if (!kIsWeb && Platform.isAndroid) {
    base = await getExternalStorageDirectory() ??
        await getApplicationDocumentsDirectory();
  } else {
    base = await getApplicationDocumentsDirectory();
  }

  final dir = Directory(p.join(base.path, 'BentaGo', subfolder));
  if (!await dir.exists()) {
    await dir.create(recursive: true);
  }
  return dir;
}
