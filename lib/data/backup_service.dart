import 'dart:io';

import 'package:path/path.dart' as p;

import '../core/format.dart';
import 'app_database.dart';
import 'app_storage.dart';

enum BackupKind { monthly, manual, safety }

extension BackupKindX on BackupKind {
  String get folder => switch (this) {
        BackupKind.monthly => 'monthly',
        BackupKind.manual => 'manual',
        BackupKind.safety => 'before-restore',
      };

  String get label => switch (this) {
        BackupKind.monthly => 'Monthly backup',
        BackupKind.manual => 'Manual backup',
        BackupKind.safety => 'Before restore',
      };
}

class BackupFile {
  const BackupFile({
    required this.kind,
    required this.database,
    this.csv,
    required this.createdAt,
    required this.sizeBytes,
  });

  final BackupKind kind;
  final File database;
  final File? csv;
  final DateTime createdAt;
  final int sizeBytes;

  String get name => p.basenameWithoutExtension(database.path);

  String get sizeLabel {
    if (sizeBytes < 1024) return '$sizeBytes B';
    if (sizeBytes < 1024 * 1024) {
      return '${(sizeBytes / 1024).toStringAsFixed(0)} KB';
    }
    return '${(sizeBytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}

class BackupResult {
  const BackupResult({
    required this.ok,
    required this.message,
    this.file,
  });

  final bool ok;
  final String message;
  final BackupFile? file;
}

/// Backups live in a folder the app owns, alongside its own files:
///
///   Android/data/<package>/files/BentaGo/Backups/{monthly,manual}/
///
/// That location needs no storage permission on any modern Android version,
/// survives app updates, and is still reachable from any file manager so the
/// files can be copied off the phone by hand.
///
/// The trade-off is real and worth stating plainly: Android deletes this folder
/// when the app is uninstalled, and it disappears with the phone if the phone
/// does. On-device backups protect against a corrupted database or a bad
/// restore, not against a lost handset -- that is what [shareBackup] is for.
class BackupService {
  BackupService(this._app, {Directory? rootOverride})
      : _rootOverride = rootOverride;

  final AppDatabase _app;

  /// Test seam: points the whole service at a temp directory instead of
  /// resolving app-scoped storage through platform bindings.
  final Directory? _rootOverride;

  static const String lastMonthlyKey = 'backup.last_monthly_month';
  static const String lastManualKey = 'backup.last_manual_at';

  static const int keepMonthly = 12;
  static const int keepManual = 10;
  static const int keepSafety = 3;

  /// Root of everything this service writes.
  Future<Directory> rootDirectory() =>
      appOwnedDirectory('Backups', override: _rootOverride);

  Future<Directory> _folderFor(BackupKind kind) async {
    final root = await rootDirectory();
    final dir = Directory(p.join(root.path, kind.folder));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  /// A user-facing path for the settings screen.
  Future<String> displayPath() async => (await rootDirectory()).path;

  // --- writing ------------------------------------------------------------

  /// Copies the live SQLite file plus a readable CSV of every sale.
  ///
  /// The checkpoint matters: sqflite may leave recent writes in a `-wal`
  /// sidecar file, and copying just the `.db` would silently produce a backup
  /// missing the most recent sales. Truncating the WAL folds everything back
  /// into the main file first.
  Future<BackupResult> _writeBackup(BackupKind kind, String baseName) async {
    try {
      await _app.db.execute('PRAGMA wal_checkpoint(TRUNCATE)');

      final folder = await _folderFor(kind);
      final dbTarget = File(p.join(folder.path, '$baseName.db'));
      final csvTarget = File(p.join(folder.path, '$baseName.csv'));

      await _app.file.copy(dbTarget.path);
      await csvTarget.writeAsString(await _salesCsv());

      final stat = await dbTarget.stat();
      final result = BackupFile(
        kind: kind,
        database: dbTarget,
        csv: csvTarget,
        createdAt: stat.modified,
        sizeBytes: stat.size,
      );

      await _prune(kind);

      return BackupResult(
        ok: true,
        message: 'Saved to ${p.basename(folder.path)}/$baseName.db',
        file: result,
      );
    } on Object catch (error) {
      return BackupResult(
        ok: false,
        message: 'Backup failed: $error',
      );
    }
  }

  Future<BackupResult> createManualBackup() async {
    final now = DateTime.now();
    final result = await _writeBackup(
      BackupKind.manual,
      'bentago-manual-${Dates.fileStamp(now)}',
    );
    if (result.ok) {
      await _app.setSetting(lastManualKey, now.toIso8601String());
    }
    return result;
  }

  /// Runs at startup. Writes at most one backup per calendar month, so opening
  /// the app twenty times in August produces exactly one August file.
  ///
  /// Deliberately not a background job: WorkManager-style scheduling is
  /// unreliable across the aggressive battery savers on budget Android phones,
  /// and the app is opened most days anyway.
  Future<BackupResult?> runMonthlyBackupIfDue() async {
    final now = DateTime.now();
    final thisMonth = Dates.monthKey(now);

    final recorded = await _app.getSetting(lastMonthlyKey);
    if (recorded == thisMonth) return null;

    // Trust the folder over the setting -- if the marker was lost but the file
    // is there, do not write a duplicate.
    final folder = await _folderFor(BackupKind.monthly);
    final expected = File(p.join(folder.path, 'bentago-$thisMonth.db'));
    if (await expected.exists()) {
      await _app.setSetting(lastMonthlyKey, thisMonth);
      return null;
    }

    final result = await _writeBackup(
      BackupKind.monthly,
      'bentago-$thisMonth',
    );
    if (result.ok) {
      await _app.setSetting(lastMonthlyKey, thisMonth);
    }
    return result;
  }

  /// Keeps the newest N of each kind and deletes the rest, so the folder never
  /// grows without bound on a phone with little free space.
  Future<void> _prune(BackupKind kind) async {
    final keep = switch (kind) {
      BackupKind.monthly => keepMonthly,
      BackupKind.manual => keepManual,
      BackupKind.safety => keepSafety,
    };

    final files = await listBackups(kind);
    if (files.length <= keep) return;

    for (final stale in files.skip(keep)) {
      try {
        if (await stale.database.exists()) await stale.database.delete();
        final csv = stale.csv;
        if (csv != null && await csv.exists()) await csv.delete();
      } on Object {
        // A file we cannot delete is not worth failing a backup over.
      }
    }
  }

  // --- reading ------------------------------------------------------------

  /// Newest first.
  Future<List<BackupFile>> listBackups(BackupKind kind) async {
    final folder = await _folderFor(kind);
    final entries = await folder
        .list()
        .where((e) => e is File && p.extension(e.path) == '.db')
        .cast<File>()
        .toList();

    final files = <BackupFile>[];
    for (final file in entries) {
      final stat = await file.stat();
      final csv = File(p.setExtension(file.path, '.csv'));
      files.add(
        BackupFile(
          kind: kind,
          database: file,
          csv: await csv.exists() ? csv : null,
          createdAt: stat.modified,
          sizeBytes: stat.size,
        ),
      );
    }

    files.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return files;
  }

  Future<List<BackupFile>> listAll() async {
    final all = <BackupFile>[
      ...await listBackups(BackupKind.monthly),
      ...await listBackups(BackupKind.manual),
    ];
    all.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return all;
  }

  /// Everything that could be restored from, including the safety copies taken
  /// before previous restores.
  ///
  /// Restore offers this list rather than a system file browser. To bring a
  /// backup in from somewhere else -- a new phone, or a file sent over
  /// Messenger -- drop the `.db` into the folder [displayPath] reports and it
  /// appears here.
  Future<List<BackupFile>> listRestorable() async {
    final all = <BackupFile>[
      ...await listBackups(BackupKind.monthly),
      ...await listBackups(BackupKind.manual),
      ...await listBackups(BackupKind.safety),
    ];

    // Anything dropped straight into the root of the backups folder counts too.
    final root = await rootDirectory();
    final loose = await root
        .list()
        .where((e) => e is File && p.extension(e.path) == '.db')
        .cast<File>()
        .toList();
    for (final file in loose) {
      final stat = await file.stat();
      final csv = File(p.setExtension(file.path, '.csv'));
      all.add(
        BackupFile(
          kind: BackupKind.manual,
          database: file,
          csv: await csv.exists() ? csv : null,
          createdAt: stat.modified,
          sizeBytes: stat.size,
        ),
      );
    }

    all.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return all;
  }

  Future<DateTime?> lastBackupAt() async {
    final all = await listAll();
    if (all.isEmpty) return null;
    return all.first.createdAt;
  }

  // --- restore ------------------------------------------------------------

  /// Replaces the live database with [source].
  ///
  /// Two safeguards, in order: the candidate file is opened and checked for the
  /// tables this app expects, and the current database is copied aside before
  /// anything is overwritten. The app must be restarted afterwards -- the old
  /// database handle in memory still points at the file that was replaced.
  Future<BackupResult> restoreFrom(File source) async {
    try {
      if (!await source.exists()) {
        return const BackupResult(
          ok: false,
          message: 'The chosen file is missing.',
        );
      }

      if (!await _looksLikeBentaGoDatabase(source)) {
        return const BackupResult(
          ok: false,
          message:
              'That is not a BentaGo backup. Choose a file starting with '
              '"bentago-" and ending in .db',
        );
      }

      // Safety copy of what is about to be replaced.
      await _app.db.execute('PRAGMA wal_checkpoint(TRUNCATE)');
      final safetyFolder = await _folderFor(BackupKind.safety);
      final safetyPath = p.join(
        safetyFolder.path,
        'before-restore-${Dates.fileStamp(DateTime.now())}.db',
      );
      await _app.file.copy(safetyPath);
      await _prune(BackupKind.safety);

      await _app.close();

      final livePath = _app.file.path;
      await source.copy(livePath);

      // Sidecars belong to the replaced database; leaving them behind would
      // corrupt the file that just arrived.
      for (final suffix in const ['-wal', '-shm', '-journal']) {
        final sidecar = File('$livePath$suffix');
        if (await sidecar.exists()) await sidecar.delete();
      }

      return BackupResult(
        ok: true,
        message: 'Restored. Close and reopen the app.',
        file: BackupFile(
          kind: BackupKind.safety,
          database: File(safetyPath),
          createdAt: DateTime.now(),
          sizeBytes: await source.length(),
        ),
      );
    } on Object catch (error) {
      return BackupResult(
        ok: false,
        message: 'Restore failed: $error',
      );
    }
  }

  /// Cheap structural check: does the file carry the tables this app writes?
  /// Reads a bounded prefix rather than the whole file -- SQLite keeps its
  /// schema in the opening pages, and a full read would be wasteful on a
  /// database that has grown to tens of megabytes.
  Future<bool> _looksLikeBentaGoDatabase(File file) async {
    const prefixBytes = 256 * 1024;

    try {
      final handle = await file.open();
      try {
        final length = await handle.length();
        if (length < 100) return false;

        final header = await handle.read(16);
        if (!String.fromCharCodes(header.take(15))
            .startsWith('SQLite format 3')) {
          return false;
        }

        // Header is right; confirm the schema by name so an unrelated SQLite
        // file cannot be restored over the store's records.
        await handle.setPosition(0);
        final chunk = await handle.read(
          length < prefixBytes ? length : prefixBytes,
        );
        final text = String.fromCharCodes(
          chunk.where((b) => b >= 32 && b < 127),
        );
        return text.contains('sale_items') &&
            text.contains('ledger_entries') &&
            text.contains('products');
      } finally {
        await handle.close();
      }
    } on Object {
      return false;
    }
  }

  // --- CSV ----------------------------------------------------------------

  /// One row per sale line, flat enough to open in Excel or Google Sheets.
  Future<String> _salesCsv() async {
    final rows = await _app.db.rawQuery('''
      SELECT s.id            AS sale_id,
             s.sold_at       AS sold_at,
             s.day_key       AS day_key,
             s.payment_type  AS payment_type,
             s.voided        AS voided,
             c.name          AS customer,
             i.product_name  AS product,
             i.qty           AS qty,
             i.unit_price_centavos AS unit_price,
             i.unit_cost_centavos  AS unit_cost,
             i.line_total_centavos AS line_total,
             s.note          AS note
      FROM sales s
      LEFT JOIN sale_items i ON i.sale_id = s.id
      LEFT JOIN customers c  ON c.id = s.customer_id
      ORDER BY s.sold_at DESC, i.id ASC
    ''');

    final buffer = StringBuffer()
      ..writeln(
        csvRow([
          'sale_id',
          'date',
          'time',
          'payment',
          'customer',
          'product',
          'qty',
          'price',
          'cost',
          'total',
          'profit',
          'cancelled',
          'note',
        ]),
      );

    for (final row in rows) {
      final soldAt =
          DateTime.fromMillisecondsSinceEpoch((row['sold_at'] as int?) ?? 0);
      final qty = (row['qty'] as int?) ?? 0;
      final total = (row['line_total'] as int?) ?? 0;
      final cost = ((row['unit_cost'] as int?) ?? 0) * qty;

      buffer.writeln(
        csvRow([
          row['sale_id'],
          row['day_key'],
          Dates.time(soldAt),
          row['payment_type'],
          row['customer'] ?? '',
          row['product'] ?? '',
          qty,
          Money.plain((row['unit_price'] as int?) ?? 0),
          Money.plain((row['unit_cost'] as int?) ?? 0),
          Money.plain(total),
          Money.plain(total - cost),
          ((row['voided'] as int?) ?? 0) == 1 ? 'yes' : '',
          row['note'] ?? '',
        ]),
      );
    }

    return buffer.toString();
  }

  /// Writes a standalone CSV for one period's sales, for sharing or printing.
  Future<File> exportCsvTo(Directory directory, {String? fileName}) async {
    final name =
        fileName ?? 'bentago-benta-${Dates.fileStamp(DateTime.now())}.csv';
    final file = File(p.join(directory.path, name));
    await file.writeAsString(await _salesCsv());
    return file;
  }
}
