import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart';

import 'package:frontend/app/theme_mode.dart';
import 'package:frontend/core/database/db_backups.dart';
import 'package:frontend/core/ui/theme.dart';

/// Wird statt der App gezeigt, wenn das Update der Datenbank fehlschlägt: Die Daten sind
/// unverändert, die App startet aber nicht in einem halb umgebauten Zustand.
class UpgradeFailedApp extends StatelessWidget {
  final DatabaseUpgradeException error;
  final Future<void> Function() onRetry;
  const UpgradeFailedApp({super.key, required this.error, required this.onRetry});

  @override
  Widget build(BuildContext context) => MaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'LifeHub',
        theme: AppTheme.lightTheme,
        darkTheme: AppTheme.darkTheme,
        themeMode: themeModeNotifier.value,
        locale: const Locale('de', 'DE'),
        supportedLocales: const [Locale('de', 'DE')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        home: _UpgradeFailedScreen(error: error, onRetry: onRetry),
      );
}

class _UpgradeFailedScreen extends StatefulWidget {
  final DatabaseUpgradeException error;
  final Future<void> Function() onRetry;
  const _UpgradeFailedScreen({required this.error, required this.onRetry});

  @override
  State<_UpgradeFailedScreen> createState() => _UpgradeFailedScreenState();
}

class _UpgradeFailedScreenState extends State<_UpgradeFailedScreen> {
  bool _retrying = false;

  Future<void> _retry() async {
    setState(() => _retrying = true);
    await widget.onRetry();
    if (mounted) setState(() => _retrying = false);
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final t = Theme.of(context).textTheme;
    final backup = widget.error.backup;
    return Scaffold(
      body: SafeArea(
        child: ListView(padding: const EdgeInsets.fromLTRB(24, 48, 24, 24), children: [
          Icon(Icons.shield_outlined, size: 56, color: c.accentText),
          const SizedBox(height: 16),
          Text('Das Update hat nicht geklappt', textAlign: TextAlign.center, style: t.headlineSmall),
          const SizedBox(height: 12),
          Text(
            'Deine Daten sind unverändert – es ist nichts verloren gegangen.'
            '${backup == null ? '' : ' Zusätzlich liegt eine Sicherung vom ${DateFormat('d. MMMM y, HH:mm', 'de_DE').format(backup.createdAt)} Uhr auf dem Handy.'}'
            '\n\nInstalliere bitte wieder die vorherige App-Version oder eine korrigierte – danach ist alles wie vorher.',
            textAlign: TextAlign.center,
            style: t.bodyLarge,
          ),
          const SizedBox(height: 24),
          FilledButton(onPressed: _retrying ? null : _retry, child: const Text('Erneut versuchen')),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: widget.error.message));
              if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Fehlermeldung kopiert')));
            },
            icon: const Icon(Icons.copy_rounded),
            label: const Text('Fehlermeldung kopieren'),
          ),
          const SizedBox(height: 16),
          ExpansionTile(
            title: Text('Technische Details', style: t.titleSmall),
            children: [Text(widget.error.message, style: t.bodySmall?.copyWith(color: c.muted))],
          ),
        ]),
      ),
    );
  }
}
