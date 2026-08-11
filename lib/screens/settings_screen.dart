import 'dart:io';

import 'package:file_picker/file_picker.dart';
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
          text: 'Backup ng BentaGo mula ${Dates.readableDay(backup.createdAt)}.',
        );
      });

  Future<void> _deleteBackup(BackupFile backup) => _run(() async {
        final ok = await confirmDestructive(
          context,
          title: 'Burahin ang backup na ito?',
          message: '${backup.name}\n\n'
              'Hindi ito maibabalik kapag nabura.',
          confirmLabel: 'Burahin',
        );
        if (!ok) return;

        if (await backup.database.exists()) await backup.database.delete();
        final csv = backup.csv;
        if (csv != null && await csv.exists()) await csv.delete();
        ref.refreshData();
        if (mounted) showToast(context, 'Nabura ang backup');
      });

  Future<void> _restore() => _run(() async {
        final picked = await FilePicker.platform.pickFiles(
          dialogTitle: 'Pumili ng BentaGo backup (.db)',
        );
        final path = picked?.files.single.path;
        if (path == null) return;

        if (!mounted) return;
        final ok = await confirmDestructive(
          context,
          title: 'Palitan ang lahat ng datos?',
          message:
              'Papalitan ng backup na ito ang bawat benta, paninda at utang na '
              'nasa app ngayon.\n\nItatabi muna ang kasalukuyang datos sa '
              'folder na "bago-i-restore" kung sakaling kailanganin.',
          confirmLabel: 'Ituloy ang restore',
        );
        if (!ok) return;

        final result =
            await ref.read(backupServiceProvider).restoreFrom(File(path));

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
            title: const Text('Tapos na ang restore'),
            content: const Text(
              'Isara nang buo ang BentaGo at buksan muli para makita ang '
              'naibalik na datos.',
            ),
            actions: [
              FilledButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Naintindihan'),
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
          subject: 'BentaGo — talaan ng benta',
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
                label: 'Huling backup',
                value: when == null ? 'Wala pa' : Dates.relativeDay(when),
                caption: when == null
                    ? 'Wala pang naitalang backup sa telepono.'
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
                  label: const Text('Backup ngayon'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _working ? null : _exportCsv,
                  icon: const Icon(Icons.ios_share, size: 19),
                  label: const Text('I-share (CSV)'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          SectionCard(
            title: 'Paano gumagana ang backup',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const _BulletLine(
                  icon: Icons.event_repeat,
                  text: 'Awtomatikong gumagawa ng kopya isang beses kada '
                      'buwan, sa unang pagbukas ng app sa buwang iyon. '
                      'Iniingatan ang huling 12 buwan.',
                ),
                const SizedBox(height: 10),
                const _BulletLine(
                  icon: Icons.folder_outlined,
                  text: 'Nasa loob ng folder ng app ang mga kopya, kaya '
                      'walang permission na kailangan at makikita rin ito sa '
                      'file manager.',
                ),
                const SizedBox(height: 10),
                _BulletLine(
                  icon: Icons.warning_amber_outlined,
                  tone: context.colors.warn,
                  text: 'Mawawala ang folder kapag na-uninstall ang app o '
                      'nawala ang telepono. Kaya kada buwan, i-share ang '
                      'backup sa sarili mo sa Messenger o Drive.',
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
            title: 'Mga naka-save na backup',
            subtitle: 'Pindutin para i-share o burahin',
            child: AsyncBlock<List<BackupFile>>(
              value: backups,
              loadingHeight: 120,
              builder: (files) {
                if (files.isEmpty) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 20),
                    child: Center(
                      child: Text(
                        'Wala pang backup.',
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
                          '${backup.csv != null ? ' · may CSV' : ''}',
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
                              tooltip: 'I-share',
                              onPressed:
                                  _working ? null : () => _shareBackup(backup),
                            ),
                            IconButton(
                              icon: Icon(
                                Icons.delete_outline,
                                size: 20,
                                color: context.colors.muted,
                              ),
                              tooltip: 'Burahin',
                              onPressed:
                                  _working ? null : () => _deleteBackup(backup),
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
            title: 'Ibalik ang datos',
            subtitle: 'Mula sa backup file',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Gamitin ito kung napalitan ng bagong telepono, o kung may '
                  'nawalang datos. Papalitan nito ang lahat ng nasa app '
                  'ngayon.',
                  style: TextStyle(
                    fontSize: 13.5,
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
                  label: const Text('Pumili ng backup file'),
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
              'Gumagana kahit walang internet.',
              style: TextStyle(fontSize: 12, color: context.colors.muted),
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
