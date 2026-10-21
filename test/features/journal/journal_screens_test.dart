import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:frontend/app/app_tabs.dart';
import 'package:frontend/core/database/database.dart';
import 'package:frontend/core/models/dates.dart';
import 'package:frontend/core/services/notification_service.dart';
import 'package:frontend/core/ui/dictation_overlay.dart';
import 'package:frontend/features/dashboard/screens/home.dart';
import 'package:frontend/features/dashboard/widgets/global_search_delegate.dart';
import 'package:frontend/features/journal/models/journal_entry.dart';
import 'package:frontend/features/journal/repositories/journal_repository.dart';
import 'package:frontend/features/journal/screens/journal_editor_screen.dart';
import 'package:frontend/features/journal/screens/journal_screen.dart';
import 'package:frontend/features/planning/screens/planning_hub_screen.dart';

import '../../helpers/test_app.dart';

void main() {
  late DatabaseService db;

  setUpAll(() => initializeDateFormatting('de_DE'));
  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({});
    db = createTestDatabase();
  });

  JournalRepository repo() => JournalRepository(db: db, notifications: RecordingNotifications());
  final today = dateOnly(DateTime.now());

  /// Felder im Editor: Datum, je Leitfrage eins, zuletzt „Freie Gedanken“.
  Future<void> enter(WidgetTester tester, String label, String text) => tester.enterText(
        label == 'Freie Gedanken' ? find.byType(TextFormField).last : find.byType(TextFormField).at(JournalEntry.prompts.indexOf(label) + 1),
        text,
      );

  testWidgets('write today\'s entry with mood, a prompt and free text; reopening edits it instead of adding a second', (tester) async {
    useTallScreen(tester);
    final user = await seedDb(tester, db, () => createTestUser(db));
    await tester.pumpWidget(testApp(db, JournalScreen(user: user)));
    await pumpUntil(tester, find.text('Noch keine Einträge'));
    expect(find.text('Heute schon geschrieben?'), findsOneWidget);

    await tester.tap(find.text('Eintrag'));
    await pumpUntil(tester, find.text('Neuer Eintrag'));
    await tester.tap(find.text('Gut'));
    await enter(tester, JournalEntry.prompts[0], 'Sonne beim Joggen');
    await enter(tester, 'Freie Gedanken', 'Langer Abend mit Freunden');
    await tester.ensureVisible(find.text('Hinzufügen'));
    await tester.tap(find.text('Hinzufügen'));
    await pumpUntil(tester, find.text('Sonne beim Joggen · Langer Abend mit Freunden'));

    final saved = (await readDb(tester, () => repo().getEntries(user.uid))).single;
    expect((saved.date, saved.mood, saved.text), (today, Mood.good, 'Langer Abend mit Freunden'));
    expect(saved.answers, {JournalEntry.prompts[0]: 'Sonne beim Joggen'});
    expect(find.text('Heute'), findsOneWidget); // Heute-Karte zeigt jetzt den Eintrag

    // Erneut über die Heute-Karte: bearbeiten statt neu
    await tester.tap(find.text('Heute'));
    await pumpUntil(tester, find.text('Eintrag bearbeiten'));
    expect(find.text('Sonne beim Joggen'), findsOneWidget);
    await tester.tap(find.text('Super'));
    await tester.ensureVisible(find.text('Speichern'));
    await tester.tap(find.text('Speichern'));
    await pumpUntil(tester, find.text('Stimmung · 30 Tage'));
    await settleDb(tester);
    final entries = await readDb(tester, () => repo().getEntries(user.uid));
    expect(entries.single.mood, Mood.great);
    await disposeApp(tester, db);
  });

  testWidgets('an empty entry is not saved; delete with undo brings the entry back', (tester) async {
    useTallScreen(tester);
    final user = await seedDb(tester, db, () async {
      final u = await createTestUser(db);
      await repo().saveEntry(JournalEntry(userid: u.uid, date: addDays(today, -1), mood: Mood.okay, text: 'Gestern war ruhig'));
      return u;
    });
    await tester.pumpWidget(testApp(db, JournalScreen(user: user)));
    await pumpUntil(tester, find.text('Gestern war ruhig'));

    await tester.tap(find.text('Eintrag'));
    await pumpUntil(tester, find.text('Neuer Eintrag'));
    await tester.ensureVisible(find.text('Hinzufügen'));
    await tester.tap(find.text('Hinzufügen'));
    await pumpUntil(tester, find.text('Schreib etwas oder wähle eine Stimmung.'));
    expect(find.text('Neuer Eintrag'), findsOneWidget); // bleibt offen
    await pageBack(tester);
    await pumpUntil(tester, find.text('Gestern war ruhig'));

    await swipeDelete(tester, find.text('Gestern war ruhig'));
    await pumpUntilGone(tester, find.text('Gestern war ruhig'));
    expect(await readDb(tester, () => repo().getEntries(user.uid)), isEmpty);
    await tester.tap(find.text('Rückgängig'));
    await pumpUntil(tester, find.text('Gestern war ruhig'));
    await disposeApp(tester, db);
  });

  testWidgets('deleting from the editor removes the entry with undo', (tester) async {
    useTallScreen(tester);
    final user = await seedDb(tester, db, () async {
      final u = await createTestUser(db);
      await repo().saveEntry(JournalEntry(userid: u.uid, date: today, text: 'Wird gelöscht'));
      return u;
    });
    await tester.pumpWidget(testApp(db, JournalScreen(user: user)));
    await pumpUntil(tester, find.text('Wird gelöscht'));
    await tester.tap(find.text('Wird gelöscht').last);
    await pumpUntil(tester, find.text('Eintrag bearbeiten'));
    await tester.ensureVisible(find.text('Löschen'));
    await tester.tap(find.text('Löschen'));
    await pumpUntil(tester, find.text('Rückgängig'));
    expect(await readDb(tester, () => repo().getEntries(user.uid)), isEmpty);
    await tester.tap(find.text('Rückgängig'));
    await pumpUntil(tester, find.text('Wird gelöscht'));
    await disposeApp(tester, db);
  });

  testWidgets('choosing a day that already has an entry warns that saving replaces it', (tester) async {
    useTallScreen(tester);
    final user = await seedDb(tester, db, () async {
      final u = await createTestUser(db);
      await repo().saveEntry(JournalEntry(userid: u.uid, date: DateTime(2026, 10, 9), text: 'Freitag'));
      return u;
    });
    await tester.pumpWidget(testApp(db, launcher(JournalEditorScreen(userid: user.uid, date: DateTime(2026, 10, 10)))));
    await tester.tap(find.text('öffnen'));
    await pumpUntil(tester, find.byType(TextFormField)); // Titel steht schon, während der Tag noch lädt
    await tester.enterText(find.byType(TextFormField).last, 'Etwas Neues');
    await tester.tap(find.text('10.10.2026'));
    await pumpUntil(tester, find.text('OK'));
    await tester.tap(find.text('9'));
    await tester.tap(find.text('OK'));
    await pumpUntil(tester, find.textContaining('Speichern ersetzt ihn'));
    expect(find.text('Etwas Neues'), findsOneWidget); // eigener Text bleibt stehen
    await disposeApp(tester, db);
  });

  testWidgets('the daily reminder can be set and switched off', (tester) async {
    useTallScreen(tester);
    final notifications = RecordingNotifications();
    final user = await seedDb(tester, db, () => createTestUser(db));
    await tester.pumpWidget(testApp(db, JournalScreen(user: user), notifications: notifications));
    await pumpUntil(tester, find.text('Erinnerung'));
    expect(find.text('aus'), findsOneWidget);

    await tester.tap(find.text('Erinnerung'));
    await pumpUntil(tester, find.text('Täglich erinnern …'));
    await tester.tap(find.text('Täglich erinnern …'));
    await pumpUntil(tester, find.text('OK'));
    await tester.tap(find.text('OK')); // Vorschlag 21:00
    await pumpUntil(tester, find.text('täglich 21:00 Uhr'));
    expect(notifications.daily[NotificationService.journalIdOffset + user.uid], ('Journal', 21, 0));

    await tester.tap(find.text('Erinnerung'));
    await pumpUntil(tester, find.text('Erinnerung ausschalten'));
    await tester.tap(find.text('Erinnerung ausschalten'));
    await pumpUntil(tester, find.text('aus'));
    expect(notifications.daily, isEmpty);
    await disposeApp(tester, db);
  });

  testWidgets('the journal is a section of „Planen“, Heute links to it and the search finds entries', (tester) async {
    useTallScreen(tester);
    final user = await seedDb(tester, db, () async {
      final u = await createTestUser(db);
      await repo().saveEntry(JournalEntry(userid: u.uid, date: addDays(today, -3), mood: Mood.great, text: 'Bergtour mit Lena'));
      return u;
    });
    await tester.pumpWidget(testApp(db, PlanningHubScreen(user: user, initialSection: PlanSection.journal)));
    await pumpUntil(tester, find.text('Bergtour mit Lena'));

    (AppTab, Enum?)? jumped;
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(testApp(db, Home(user: user, onTabNav: (tab, [section]) => jumped = (tab, section))));
    await pumpUntil(tester, find.text('Heute schon geschrieben?'));
    await tester.ensureVisible(find.text('Heute schon geschrieben?'));
    await tester.tap(find.text('Alle').last);
    expect(jumped, (AppTab.plan, PlanSection.journal));
    await tester.tap(find.text('Heute schon geschrieben?'));
    await pumpUntil(tester, find.text('Neuer Eintrag'));
    await pageBack(tester);
    await pumpUntil(tester, find.text('Heute schon geschrieben?'));

    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(testApp(
      db,
      Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: TextButton(
              onPressed: () => showSearch(context: context, delegate: GlobalSearchDelegate(userId: user.uid, db: db)),
              child: const Text('Suche'),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('Suche'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'bergtour');
    await pumpUntil(tester, find.text('Bergtour mit Lena'));
    await tester.tap(find.text('Bergtour mit Lena'));
    await pumpUntil(tester, find.text('Eintrag bearbeiten'));
    await disposeApp(tester, db);
  });

  testWidgets('journal fields can be dictated', (tester) async {
    useTallScreen(tester);
    final user = await seedDb(tester, db, () => createTestUser(db));
    await tester.pumpWidget(testApp(db, launcher(JournalEditorScreen(userid: user.uid)), dictation: FakeDictation(words: 'ein ruhiger sonntag')));
    await tester.tap(find.text('öffnen'));
    await pumpUntil(tester, find.byType(TextFormField));
    await tester.tap(find.byType(TextFormField).last);
    await tester.pump();
    await tester.tap(find.byKey(DictationOverlay.micKey));
    await tester.pump();
    await tester.ensureVisible(find.text('Hinzufügen'));
    await tester.tap(find.text('Hinzufügen'));
    await pumpUntil(tester, find.text('result:true'));
    expect((await readDb(tester, () => repo().getEntry(user.uid, today)))!.text, 'Ein ruhiger sonntag');
    await disposeApp(tester, db);
  });
}
