import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'data/app_database.dart';
import 'data/backup_service.dart';
import 'demo/demo_seed.dart';
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

  // Only ever true in the build the demo pipeline makes
  // (--dart-define=BENTAGO_DEMO=true). A const condition, so a normal build
  // drops both the branch and the seeder itself.
  //
  // Deliberately *after* the backup: the seeder deletes every sale, tab and
  // expense in the database. Should a demo build ever be run on a phone holding
  // a real store's records, the month's backup is taken before the wipe rather
  // than of it.
  if (kDemoMode) await DemoSeeder.reset(database);

  runApp(
    ProviderScope(
      overrides: [databaseProvider.overrideWithValue(database)],
      child: const BentaGoApp(),
    ),
  );
}
