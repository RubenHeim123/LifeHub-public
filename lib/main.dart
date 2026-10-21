import 'package:flutter/material.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'package:frontend/app/app.dart';
import 'package:frontend/app/theme_mode.dart';
import 'package:frontend/app/upgrade_failed_app.dart';
import 'package:frontend/core/database/database.dart';
import 'package:frontend/core/database/db_backups.dart';
import 'package:frontend/core/services/notification_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await NotificationService().init();
  await initializeDateFormatting('de_DE', null);
  await loadThemePref();
  await _start();
  // Bewusst nicht awaited, damit der Berechtigungsdialog den Start nicht blockiert.
  NotificationService().requestPermissions();
}

/// Öffnet die Datenbank vor dem ersten Screen. Ein fehlgeschlagenes Update (Sicherung liegt vor,
/// Daten unverändert) zeigt einen Hinweis statt der App.
Future<void> _start() async {
  try {
    await DatabaseService.instance.database;
  } on DatabaseUpgradeException catch (e) {
    runApp(UpgradeFailedApp(error: e, onRetry: _start));
    return;
  }
  runApp(const MyApp());
}
