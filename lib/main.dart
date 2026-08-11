import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'data/app_database.dart';
import 'data/backup_service.dart';
import 'state/providers.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Opened before the first frame so no screen ever has to render an
  // "is the database ready" state.
  final database = await AppDatabase.open();

  // At most one automatic backup per calendar month. Runs at startup rather
  // than on a background schedule -- budget Android phones kill background
  // work aggressively, and the app is opened most days anyway.
  await BackupService(database).runMonthlyBackupIfDue();

  runApp(
    ProviderScope(
      overrides: [databaseProvider.overrideWithValue(database)],
      child: const BentaGoApp(),
    ),
  );
}
