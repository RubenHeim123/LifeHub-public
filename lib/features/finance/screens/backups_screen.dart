import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import 'package:frontend/core/database/database.dart';
import 'package:frontend/core/database/db_backups.dart';
import 'package:frontend/core/ui/app_actions.dart';
import 'package:frontend/core/ui/app_ui.dart';
import 'package:frontend/core/ui/modern_appbar.dart';
import 'package:frontend/core/ui/theme.dart';
import 'package:frontend/features/auth/screens/wrapper.dart';

/// Sicherungen der Datenbank: automatisch vor jedem Update, von Hand, als Datei teilen und
/// wiederherstellen (auch aus einer geteilten Datei – übersteht so ein Deinstallieren).
class BackupsScreen extends StatefulWidget {
  const BackupsScreen({super.key});

  @override
  State<BackupsScreen> createState() => _BackupsScreenState();
}

class _BackupsScreenState extends State<BackupsScreen> {
  late final DatabaseService _db = context.read<DatabaseService>();
  List<DbBackup>? _backups;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final list = await _db.backups.list();
    if (mounted) setState(() => _backups = list);
  }

  Future<void> _busyWhile(Future<void> Function() action) async {
    setState(() => _busy = true);
    try {
      await action();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _backupNow() => _busyWhile(() async {
        await runGuarded(context, _db.backupNow, success: 'Gesichert');
        await _load();
      });

  Future<void> _share(DbBackup b) => runGuarded(
        context,
        () => Share.shareXFiles([XFile(b.file.path)], text: 'LifeHub-Sicherung vom ${_date(b.createdAt)}'),
      );

  Future<void> _restore(File file, String label) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Wiederherstellen?'),
        content: Text('Die App kehrt zum Stand „$label“ zurück. Der jetzige Stand wird vorher gesichert '
            'und lässt sich hier ebenfalls wiederherstellen.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Abbrechen')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Wiederherstellen')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    var done = false;
    await _busyWhile(() async {
      done = await runGuarded(context, () async {
            await _db.restoreBackup(file);
            return true;
          }) ??
          false;
    });
    if (!done || !mounted) return;
    showAppSnack(context, 'Wiederhergestellt – bitte neu anmelden');
    await Wrapper.signOut(context); // alle Ansichten mit den wiederhergestellten Daten neu laden
  }

  Future<void> _restoreFromFile() async {
    final result = await FilePicker.platform.pickFiles();
    final path = result?.files.single.path;
    if (path == null || !mounted) return;
    await _restore(File(path), result!.files.single.name);
  }

  static String _date(DateTime d) => DateFormat('d. MMMM y, HH:mm', 'de_DE').format(d);

  static String _size(int bytes) =>
      bytes < 1024 * 1024 ? '${(bytes / 1024).ceil()} KB' : '${(bytes / 1024 / 1024).toStringAsFixed(1).replaceAll('.', ',')} MB';

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final t = Theme.of(context).textTheme;
    final backups = _backups;
    return Scaffold(
      appBar: const ModernAppBar(title: 'Sicherungen'),
      body: backups == null
          ? Center(child: CircularProgressIndicator(color: c.accent))
          : ListView(padding: detailPadding(context), children: [
              Text(
                'Vor jedem Update der App sichert LifeHub automatisch den bisherigen Stand (die letzten '
                '${DbBackupStore.keep} Sicherungen bleiben). Teilst du eine Sicherung – z. B. in Google Drive –, '
                'übersteht sie auch ein Deinstallieren der App.',
                style: t.bodyMedium?.copyWith(color: c.muted),
              ),
              const SizedBox(height: 16),
              Wrap(spacing: 8, runSpacing: 8, children: [
                FilledButton.icon(onPressed: _busy ? null : _backupNow, icon: const Icon(Icons.save_outlined), label: const Text('Jetzt sichern')),
                OutlinedButton.icon(
                  onPressed: _busy ? null : _restoreFromFile,
                  icon: const Icon(Icons.file_open_outlined),
                  label: const Text('Aus Datei wiederherstellen'),
                ),
              ]),
              const SizedBox(height: 20),
              if (backups.isEmpty)
                const EmptyState(
                  icon: Icons.inventory_2_outlined,
                  title: 'Noch keine Sicherungen',
                  message: 'Die erste entsteht beim nächsten Update – oder jetzt mit „Jetzt sichern“.',
                ),
              for (final b in backups)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: AppCard(
                    padding: const EdgeInsets.fromLTRB(14, 12, 6, 12),
                    child: Row(children: [
                      IconTile(
                        icon: b.reason == BackupReason.update ? Icons.system_update_alt_rounded : Icons.save_outlined,
                        color: c.accentText,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(_date(b.createdAt), style: t.titleSmall),
                          Text('${b.reason.label} · Version ${b.version} · ${_size(b.sizeBytes)}', style: t.labelMedium),
                        ]),
                      ),
                      IconButton(tooltip: 'Teilen', icon: const Icon(Icons.share_outlined), onPressed: _busy ? null : () => _share(b)),
                      IconButton(
                        tooltip: 'Wiederherstellen',
                        icon: const Icon(Icons.settings_backup_restore_rounded),
                        onPressed: _busy ? null : () => _restore(b.file, _date(b.createdAt)),
                      ),
                    ]),
                  ),
                ),
            ]),
    );
  }
}
