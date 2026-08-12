import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../core/format.dart';
import '../core/theme.dart';
import '../data/backup_service.dart';
import '../state/providers.dart';
import '../widgets/common.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  bool _working = false;

  Future<void> _run(Future<void> Function() action) async {
    if (_working) return;
    setState(() => _working = true);
    try {
      await action();
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _createBackup() => _run(() async {
        final result =
            await ref.read(backupServiceProvider).createManualBackup();
        ref.refreshData();
        if (!mounted) return;
        showToast(context, result.message, isError: !result.ok);
      });

  Future<void> _shareBackup(BackupFile backup) => _run(() async {
        final files = <XFile>[
          XFile(backup.database.path),
          if (backup.csv != null) XFile(backup.csv!.path),
        ];
        await Share.shareXFiles(
          files,
          subject: 'BentaGo backup — ${backup.name}',
          text: 'BentaGo backup from ${Dates.readableDay(backup.createdAt)}.',
        );
      });

  Future<void> _deleteBackup(BackupFile backup) => _run(() async {
        final ok = await confirmDestructive(
          context,
          title: 'Delete this backup?',
          message: '${backup.name}\n\nIt cannot be recovered once deleted.',
          confirmLabel: 'Delete',
        );
        if (!ok) return;

        if (await backup.database.exists()) await backup.database.delete();
        final csv = backup.csv;
        if (csv != null && await csv.exists()) await csv.delete();
        ref.refreshData();
        if (mounted) showToast(context, 'Backup deleted');
      });

  Future<void> _restore() => _run(() async {
        final available =
            await ref.read(backupServiceProvider).listRestorable();

        if (!mounted) return;
        if (available.isEmpty) {
          showToast(
            context,
            'No backup files found in the BentaGo folder.',
            isError: true,
          );
          return;
        }

        final chosen = await showModalBottomSheet<BackupFile>(
          context: context,
          useSafeArea: true,
          builder: (sheetContext) => _RestorePicker(backups: available),
        );
        if (chosen == null) return;

        if (!mounted) return;
        final ok = await confirmDestructive(
          context,
          title: 'Replace all data?',
          message: 'Restoring "${chosen.name}" will replace every sale, '
              'product and credit record currently in the app.\n\nThe current '
              'data is copied aside into the "before-restore" folder first, '
              'just in case.',
          confirmLabel: 'Restore',
        );
        if (!ok) return;

        final result = await ref
            .read(backupServiceProvider)
            .restoreFrom(chosen.database);

        if (!mounted) return;
        if (!result.ok) {
          showToast(context, result.message, isError: true);
          return;
        }

        // The in-memory database handle now points at a file that has been
        // replaced underneath it, so the app has to be restarted rather than
        // simply refreshed.
        await showDialog<void>(
          context: context,
          barrierDismissible: false,
          builder: (context) => AlertDialog(
            title: const Text('Restore finished'),
            content: const Text(
              'Close BentaGo completely and open it again to see the '
              'restored data.',
            ),
            actions: [
              FilledButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Got it'),
              ),
            ],
          ),
        );
      });

  Future<void> _exportCsv() => _run(() async {
        final service = ref.read(backupServiceProvider);
        final dir = await service.rootDirectory();
        final file = await service.exportCsvTo(dir);
        await Share.shareXFiles(
          [XFile(file.path)],
          subject: 'BentaGo — sales records',
        );
      });

  @override
  Widget build(BuildContext context) {
    final backups = ref.watch(backupListProvider);
    final path = ref.watch(backupPathProvider);
    final lastBackup = ref.watch(lastBackupProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          AsyncBlock<DateTime?>(
            value: lastBackup,
            loadingHeight: 96,
            builder: (when) {
              final stale =
                  when == null || DateTime.now().difference(when).inDays > 7;
              return StatTile(
                large: true,
                label: 'Last backup',
                value: when == null ? 'None yet' : Dates.relativeDay(when),
                caption: when == null
                    ? 'No backup saved on this device yet.'
                    : Dates.readableDay(when),
                tone: stale ? StatTone.warn : StatTone.good,
                icon: Icons.backup_outlined,
              );
            },
          ),
          const SizedBox(height: 12),

          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: _working ? null : _createBackup,
                  icon: const Icon(Icons.save_alt, size: 20),
                  label: const Text('Back up now'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _working ? null : _exportCsv,
                  icon: const Icon(Icons.ios_share, size: 19),
                  label: const Text('Share CSV'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          SectionCard(
            title: 'How backups work',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const _BulletLine(
                  icon: Icons.event_repeat,
                  text: 'A copy is made automatically once a month, the first '
                      'time the app is opened that month. The last 12 months '
                      'are kept.',
                ),
                const SizedBox(height: 10),
                const _BulletLine(
                  icon: Icons.folder_outlined,
                  text: 'Copies live inside the app\'s own folder, so no '
                      'permission is needed and they are still visible from '
                      'any file manager.',
                ),
                const SizedBox(height: 10),
                _BulletLine(
                  icon: Icons.warning_amber_outlined,
                  tone: context.colors.warn,
                  text: 'The folder is deleted if the app is uninstalled, and '
                      'it goes with the phone if the phone does. So once a '
                      'month, share the backup to yourself on Messenger or '
                      'Drive.',
                ),
                const SizedBox(height: 14),
                AsyncBlock<String>(
                  value: path,
                  loadingHeight: 40,
                  builder: (value) => Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(11),
                    decoration: BoxDecoration(
                      color: context.scheme.surfaceContainerLowest,
                      borderRadius: BorderRadius.circular(9),
                      border: Border.all(
                        color: context.scheme.outlineVariant
                            .withValues(alpha: 0.6),
                      ),
                    ),
                    child: Text(
                      value,
                      style: TextStyle(
                        fontSize: 11.5,
                        height: 1.4,
                        fontFamily: 'monospace',
                        color: context.colors.muted,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          SectionCard(
            title: 'Saved backups',
            subtitle: 'Tap to share or delete',
            child: AsyncBlock<List<BackupFile>>(
              value: backups,
              loadingHeight: 120,
              builder: (files) {
                if (files.isEmpty) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 20),
                    child: Center(
                      child: Text(
                        'No backups yet.',
                        style: TextStyle(color: context.colors.muted),
                      ),
                    ),
                  );
                }

                return Column(
                  children: [
                    for (final backup in files)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: Container(
                          width: 40,
                          height: 40,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: (backup.kind == BackupKind.monthly
                                    ? context.scheme.primary
                                    : context.colors.accent)
                                .withValues(alpha: 0.14),
                            borderRadius: BorderRadius.circular(11),
                          ),
                          child: Icon(
                            backup.kind == BackupKind.monthly
                                ? Icons.event_repeat
                                : Icons.save_alt,
                            size: 19,
                            color: backup.kind == BackupKind.monthly
                                ? context.scheme.primary
                                : context.colors.accent,
                          ),
                        ),
                        title: Text(
                          Dates.readableDay(backup.createdAt),
                          style: const TextStyle(
                            fontSize: 14.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        subtitle: Text(
                          '${backup.kind.label} · ${backup.sizeLabel}'
                          '${backup.csv != null ? ' · with CSV' : ''}',
                          style: TextStyle(
                            fontSize: 12,
                            color: context.colors.muted,
                          ),
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.ios_share, size: 20),
                              tooltip: 'Share',
                              onPressed:
                                  _working ? null : () => _shareBackup(backup),
                            ),
                            IconButton(
                              icon: Icon(
                                Icons.delete_outline,
                                size: 20,
                                color: context.colors.muted,
                              ),
                              tooltip: 'Delete',
                              onPressed: _working
                                  ? null
                                  : () => _deleteBackup(backup),
                            ),
                          ],
                        ),
                      ),
                  ],
                );
              },
            ),
          ),
          const SizedBox(height: 12),

          SectionCard(
            title: 'Restore data',
            subtitle: 'From a backup file',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Use this after moving to a new phone, or if data has gone '
                  'missing. It replaces everything currently in the app.',
                  style: TextStyle(
                    fontSize: 13.5,
                    height: 1.45,
                    color: context.colors.muted,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  'Restoring a backup from somewhere else? Copy its .db file '
                  'into the folder shown above using any file manager, then '
                  'it will appear in this list.',
                  style: TextStyle(
                    fontSize: 12.5,
                    height: 1.45,
                    color: context.colors.muted,
                  ),
                ),
                const SizedBox(height: 14),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(double.infinity, 50),
                    foregroundColor: context.colors.warn,
                    side: BorderSide(
                      color: context.colors.warn.withValues(alpha: 0.5),
                    ),
                  ),
                  onPressed: _working ? null : _restore,
                  icon: const Icon(Icons.restore, size: 20),
                  label: const Text('Choose a backup to restore'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          Center(
            child: Text(
              'BentaGo 1.0.0',
              style: TextStyle(fontSize: 12.5, color: context.colors.muted),
            ),
          ),
          const SizedBox(height: 4),
          Center(
            child: Text(
              'Works with no internet connection.',
              style: TextStyle(fontSize: 12, color: context.colors.muted),
            ),
          ),
        ],
      ),
    );
  }
}

/// Lists every backup found on the device so one can be picked for restore.
/// Replaces a system file browser, which asked a non-technical user to navigate
/// to an app-scoped storage path they would never find on their own.
class _RestorePicker extends StatelessWidget {
  const _RestorePicker({required this.backups});

  final List<BackupFile> backups;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
            child: Row(
              children: [
                const Expanded(
                  child: Text(
                    'Choose a backup',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  tooltip: 'Close',
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
            child: Text(
              'Newest first. The date is when the backup was written.',
              style: TextStyle(fontSize: 12.5, color: context.colors.muted),
            ),
          ),
          const Divider(height: 1),
          Flexible(
            child: ListView.separated(
              shrinkWrap: true,
              itemCount: backups.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final backup = backups[index];
                return ListTile(
                  leading: Container(
                    width: 40,
                    height: 40,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: context.scheme.primary.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(11),
                    ),
                    child: Icon(
                      Icons.restore,
                      size: 19,
                      color: context.scheme.primary,
                    ),
                  ),
                  title: Text(
                    Dates.readableDay(backup.createdAt),
                    style: const TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  subtitle: Text(
                    '${backup.kind.label} · ${backup.sizeLabel} · '
                    '${Dates.time(backup.createdAt)}',
                    style: TextStyle(
                      fontSize: 12,
                      color: context.colors.muted,
                    ),
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.pop(context, backup),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _BulletLine extends StatelessWidget {
  const _BulletLine({required this.icon, required this.text, this.tone});

  final IconData icon;
  final String text;
  final Color? tone;

  @override
  Widget build(BuildContext context) {
    final color = tone ?? context.colors.muted;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Icon(icon, size: 17, color: color),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              fontSize: 13.5,
              height: 1.45,
              color: tone ?? context.scheme.onSurface.withValues(alpha: 0.82),
            ),
          ),
        ),
      ],
    );
  }
}
