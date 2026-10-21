import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:frontend/app/upgrade_failed_app.dart';
import 'package:frontend/core/database/database.dart';
import 'package:frontend/core/database/db_backups.dart';
import 'package:frontend/features/finance/screens/backups_screen.dart';

import '../../helpers/test_app.dart';

void main() {
  late DatabaseService db;

  setUpAll(() => initializeDateFormatting('de_DE'));
  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({});
    db = createTestDatabase();
  });

  Future<List<String>> recipes(WidgetTester tester) async =>
      [for (final r in await readDb(tester, () async => (await db.database).query('recipes', orderBy: 'id'))) r['name'] as String];

  testWidgets('back up now, change something, restore: the old state is back and you sign in again', (tester) async {
    useTallScreen(tester);
    await seedDb(tester, db, () async {
      final u = await createTestUser(db);
      await (await db.database).insert('recipes', {'userid': u.uid, 'name': 'Linsen-Dal'});
      return u;
    });
    await tester.pumpWidget(testApp(db, const BackupsScreen()));
    await pumpUntil(tester, find.text('Noch keine Sicherungen'));

    await tester.tap(find.text('Jetzt sichern'));
    await pumpUntil(tester, find.textContaining('Von Hand gesichert · Version ${DatabaseService.schemaVersion}'));
    await readDb(tester, () async => (await db.database).insert('recipes', {'userid': 1, 'name': 'Später angelegt'}));
    expect(await recipes(tester), ['Linsen-Dal', 'Später angelegt']);

    await tester.tap(find.byTooltip('Wiederherstellen'));
    await pumpUntil(tester, find.text('Wiederherstellen?'));
    await tester.tap(find.widgetWithText(FilledButton, 'Wiederherstellen'));
    await pumpUntil(tester, find.widgetWithText(ElevatedButton, 'Anmelden'));
    expect(await recipes(tester), ['Linsen-Dal']);

    // Der Stand vor dem Wiederherstellen ist selbst gesichert
    final backups = await readDb(tester, () => db.backups.list());
    expect(backups.map((b) => b.reason), containsAll([BackupReason.manual, BackupReason.beforeRestore]));
    await disposeApp(tester, db);
  });

  testWidgets('a failed update shows that the data is safe, can copy the error and retry', (tester) async {
    var retried = 0;
    final error = DatabaseUpgradeException(
      fromVersion: 29,
      toVersion: 30,
      backup: null,
      cause: 'kaputt',
    );
    await tester.pumpWidget(UpgradeFailedApp(error: error, onRetry: () async => retried++));
    await tester.pumpAndSettle();
    expect(find.text('Das Update hat nicht geklappt'), findsOneWidget);
    expect(find.textContaining('Deine Daten sind unverändert'), findsOneWidget);
    await tester.tap(find.text('Erneut versuchen'));
    await tester.pumpAndSettle();
    expect(retried, 1);
  });
}
