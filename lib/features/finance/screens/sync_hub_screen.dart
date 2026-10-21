import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:frontend/core/ui/app_actions.dart';
import 'package:frontend/core/ui/app_ui.dart';
import 'package:frontend/core/ui/modern_appbar.dart';
import 'package:frontend/core/ui/theme.dart';
import 'package:frontend/features/auth/models/user.dart';
import 'package:frontend/features/finance/services/local_sync_service.dart';
import 'package:frontend/features/finance/services/export_service.dart';
import 'package:frontend/features/finance/screens/backups_screen.dart';
import 'package:frontend/features/finance/screens/import_transactions_view.dart';

class SyncHubScreen extends StatefulWidget {
  final UserModel user;
  const SyncHubScreen({super.key, required this.user});

  @override
  State<SyncHubScreen> createState() => _SyncHubScreenState();
}

class _SyncHubScreenState extends State<SyncHubScreen> {
  late final LocalSyncService _syncService = context.read<LocalSyncService>();
  final TextEditingController _ipController = TextEditingController();
  bool _isProcessing = false;
  bool _isServerOnline = false;

  @override
  void dispose() {
    _ipController.dispose();
    super.dispose();
  }

  Future<void> _checkStatus() async {
    if (_ipController.text.isEmpty) return;
    final online = await _syncService.checkServerStatus(_ipController.text);
    if (mounted) setState(() => _isServerOnline = online);
  }

  Future<void> _handleCloudSync() async {
    final ip = _ipController.text.trim();
    if (ip.isEmpty) {
      showAppSnack(context, 'Bitte die IP-Adresse deines PCs eingeben.', error: true);
      return;
    }
    setState(() => _isProcessing = true);
    try {
      final success = await _syncService.syncToIP(widget.user.uid, ip);
      if (!mounted) return;
      showAppSnack(context, success ? 'Synchronisiert.' : 'Synchronisieren fehlgeschlagen – läuft der Sync-Server auf dem PC?',
          error: !success);
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  Future<void> _run(Future<void> Function() action, {String? success}) async {
    setState(() => _isProcessing = true);
    try {
      await runGuarded(context, action, success: success);
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final t = Theme.of(context).textTheme;
    final export = context.read<ExportService>();
    return Scaffold(
      appBar: const ModernAppBar(title: 'Sichern & Synchronisieren'),
      body: Stack(children: [
        ListView(
          padding: detailPadding(context),
          children: [
            Text('Sichere deine Daten als Datei oder gleiche sie mit deinem PC ab.', style: t.bodyMedium?.copyWith(color: c.muted)),
            const SizedBox(height: 16),
            const SectionTitle('Sichern'),
            _card(
              title: 'Alle Daten exportieren (JSON)',
              description: 'Eine Datei mit all deinen LifeHub-Daten – zum Aufheben oder Teilen.',
              icon: Icons.unarchive_outlined,
              color: c.accentText,
              onTap: () => _run(() => _syncService.exportData(widget.user.uid)),
            ),
            _card(
              title: 'Sicherungen & Wiederherstellen',
              description: 'Automatisch vor jedem Update gesichert. Stand zurückholen, sichern oder als Datei teilen.',
              icon: Icons.settings_backup_restore_rounded,
              color: c.positive,
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const BackupsScreen())),
            ),
            const SizedBox(height: 8),
            const SectionTitle('Finanzen'),
            _card(
              title: 'Buchungen exportieren (CSV)',
              description: 'Deine Buchungen als Tabelle, z. B. für Excel.',
              icon: Icons.table_chart_outlined,
              color: c.event,
              onTap: () => _run(() => export.shareCsv(widget.user.uid)),
            ),
            _card(
              title: 'Bank-CSV importieren',
              description: 'Umsätze aus dem Export deiner Bank übernehmen.',
              icon: Icons.upload_file_outlined,
              color: c.streak,
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ImportTransactionsView(user: widget.user))),
            ),
            const SizedBox(height: 8),
            const SectionTitle('Mit dem PC abgleichen'),
            Text('Starte auf deinem PC scripts/sync_server.py und gib hier seine IP-Adresse ein (gleiches WLAN).',
                style: t.bodySmall?.copyWith(color: c.muted)),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(
                child: TextField(
                  controller: _ipController,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(
                    hintText: 'IP des PCs, z. B. 192.168.1.10',
                    prefixIcon: Icon(Icons.computer, color: _isServerOnline ? c.positive : c.muted),
                    suffixIcon: _isServerOnline ? Icon(Icons.check_circle_rounded, color: c.positive) : null,
                  ),
                  onChanged: (_) => _checkStatus(),
                ),
              ),
              const SizedBox(width: 12),
              IconButton.filled(
                tooltip: 'Jetzt synchronisieren',
                onPressed: _isProcessing ? null : _handleCloudSync,
                icon: const Icon(Icons.sync),
              ),
            ]),
          ],
        ),
        if (_isProcessing)
          Container(
            color: Colors.black26,
            child: const Center(child: CircularProgressIndicator()),
          ),
      ]),
    );
  }

  Widget _card({required String title, required String description, required IconData icon, required Color color, required VoidCallback onTap}) {
    final c = AppColors.of(context);
    final t = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: AppCard(
        onTap: _isProcessing ? null : onTap,
        child: Row(children: [
          IconTile(icon: icon, color: color, background: color.withValues(alpha: 0.12)),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: t.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: 2),
              Text(description, style: t.bodySmall?.copyWith(color: c.muted, height: 1.3)),
            ]),
          ),
          Icon(Icons.chevron_right_rounded, color: c.dim),
        ]),
      ),
    );
  }
}
