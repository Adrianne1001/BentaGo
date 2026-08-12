// Prints the schema and row counts of a BentaGo database.
//
//   dart run tool/inspect_db.dart                  # the live database
//   dart run tool/inspect_db.dart path\to\file.db  # a backup
//
// Opens read-only, so it is safe to run while the app is in use. Handy for
// checking a migration landed, or for looking at a backup a user sent over.
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Future<void> main(List<String> args) async {
  sqfliteFfiInit();
  final factory = databaseFactoryFfi;

  final path = args.isNotEmpty
      ? args.first
      : p.join(
          Platform.environment['USERPROFILE'] ??
              Platform.environment['HOME'] ??
              '.',
          'Documents',
          'bentago.db',
        );

  if (!File(path).existsSync()) {
    stdout.writeln('No database at $path');
    exitCode = 1;
    return;
  }

  final db = await factory.openDatabase(
    path,
    options: OpenDatabaseOptions(readOnly: true),
  );

  stdout.writeln('database : $path');
  stdout.writeln('version  : ${await db.getVersion()}');

  final tables = await db.rawQuery(
    "SELECT name FROM sqlite_master WHERE type = 'table' "
    "AND name NOT LIKE 'sqlite_%' ORDER BY name",
  );

  stdout.writeln('\ntables');
  for (final row in tables) {
    final name = row['name'] as String;
    final count = (await db.rawQuery('SELECT COUNT(*) AS c FROM "$name"'))
        .first['c'];
    stdout.writeln('  $name  ($count rows)');
  }

  stdout.writeln('\nproducts columns');
  final columns = await db.rawQuery('PRAGMA table_info(products)');
  for (final column in columns) {
    stdout.writeln('  ${column['name']}  ${column['type']}');
  }

  await db.close();
}
