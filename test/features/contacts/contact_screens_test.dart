import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:frontend/core/database/database.dart';
import 'package:frontend/core/models/dates.dart';
import 'package:frontend/core/services/notification_service.dart';
import 'package:frontend/features/calendar/repositories/appointment_repository.dart';
import 'package:frontend/features/contacts/models/contact.dart';
import 'package:frontend/features/contacts/models/relative_date.dart';
import 'package:frontend/features/contacts/repositories/contact_repository.dart';
import 'package:frontend/features/contacts/screens/contact_screen.dart';
import 'package:frontend/features/contacts/screens/contacts_screen.dart';
import 'package:frontend/features/dashboard/screens/home.dart';
import 'package:frontend/features/dashboard/widgets/global_search_delegate.dart';
import 'package:frontend/features/inventory/repositories/inventory_repository.dart';
import 'package:frontend/features/lists/repositories/lists_repository.dart';

import '../../helpers/test_app.dart';

void main() {
  late DatabaseService db;

  setUpAll(() => initializeDateFormatting('de_DE'));
  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({});
    db = createTestDatabase();
  });

  ContactRepository repo([NotificationService? n]) {
    final notifications = n ?? RecordingNotifications();
    return ContactRepository(db: db, notifications: notifications, appointments: AppointmentRepository(db: db, notifications: notifications));
  }

  testWidgets('add a contact, then a quick note "nächste Woche Mittwoch Arzttermin": dated, reminded, follow-up', (tester) async {
    useTallScreen(tester);
    final notifications = RecordingNotifications();
    final user = await seedDb(tester, db, () => createTestUser(db));
    await tester.pumpWidget(testApp(db, ContactsScreen(user: user), notifications: notifications));
    await pumpUntil(tester, find.text('Noch keine Kontakte'));

    await tester.tap(find.text('Kontakt'));
    await pumpUntil(tester, find.text('Neuer Kontakt'));
    await tester.enterText(find.widgetWithText(TextFormField, 'Name'), 'Lena Müller');
    await tester.tap(find.text('Freundschaft'));
    await tester.ensureVisible(find.text('Speichern'));
    await tester.tap(find.text('Speichern'));
    await pumpUntil(tester, find.text('Neue Notiz'));
    expect(find.text('LM'), findsOneWidget);

    await tester.enterText(find.widgetWithText(TextField, 'Neue Notiz'), 'hat nächste Woche Mittwoch einen Arzttermin');
    await tester.pump();
    final expected = parseRelativeDate('nächste Woche Mittwoch', DateTime.now()).date!;
    expect(find.byType(InputChip), findsOneWidget); // erkanntes Datum
    await tester.tap(find.text('Am Tag danach nachfragen'));
    await tester.pump();
    await tester.tap(find.text('Notiz hinzufügen'));
    await pumpUntil(tester, find.text('hat einen Arzttermin'));

    final p = (await readDb(tester, () => repo().getContacts(user.uid))).single;
    expect((p.name, p.relation), ('Lena Müller', 'Freundschaft'));
    final note = (await readDb(tester, () => repo().getNotes(p.id!))).single;
    expect((note.date, note.followUp, note.done), (expected, true, false));
    final id = NotificationService.contactIdOffset + 2 * note.id!;
    expect(notifications.scheduled[id], ('Lena Müller: hat einen Arzttermin', 'Heute', DateTime(expected.year, expected.month, expected.day, 9)));
    expect(notifications.scheduled[id + 1]!.$1, 'Bei Lena Müller nachfragen');

    // Ein Datum lässt sich auch wegklicken: dann bleibt der Text, wie er ist
    await tester.enterText(find.widgetWithText(TextField, 'Neue Notiz'), 'mag morgen keinen Stress');
    await tester.pump();
    await tester.tap(find.byTooltip('Ohne Datum'));
    await tester.pump();
    await tester.tap(find.text('Notiz hinzufügen'));
    await pumpUntil(tester, find.text('mag morgen keinen Stress'));
    expect((await readDb(tester, () => repo().getNotes(p.id!))).where((n) => n.date == null), hasLength(1));
    await disposeApp(tester, db);
  });

  testWidgets('Heute: today\'s note can be ticked off, upcoming birthdays show, tapping opens the contact', (tester) async {
    useTallScreen(tester);
    final today = dateOnly(DateTime.now());
    final r = repo();
    final user = await seedDb(tester, db, () async {
      final u = await createTestUser(db);
      final lena = await r.saveContact(Contact(userid: u.uid, name: 'Lena', birthday: DateTime(1990, today.month, today.day + 3)));
      await r.saveNote(ContactNote(userid: u.uid, contactId: lena, text: 'Arzttermin', date: today, created: DateTime.now()));
      return u;
    });
    await tester.pumpWidget(testApp(db, Home(user: user)));
    await pumpUntil(tester, find.text('Lena: Arzttermin'));
    expect(find.text('Menschen'), findsOneWidget);
    expect(find.text('Lena hat in 3 Tagen Geburtstag'), findsOneWidget);

    await tester.ensureVisible(find.text('Lena: Arzttermin'));
    await tester.tap(find.bySemanticsLabel('Erledigt').last);
    await tester.pump();
    await settleDb(tester);
    final lena = (await readDb(tester, () => r.getContacts(user.uid))).single;
    expect((await readDb(tester, () => r.getNotes(lena.id!))).single.done, isTrue);

    await tester.tap(find.text('Lena hat in 3 Tagen Geburtstag'));
    await pumpUntil(tester, find.text('Geschenkliste'));
    await disposeApp(tester, db);
  });

  testWidgets('Heute has no Menschen section without notes or birthdays', (tester) async {
    useTallScreen(tester);
    final user = await seedDb(tester, db, () => createTestUser(db));
    await tester.pumpWidget(testApp(db, Home(user: user)));
    await pumpUntil(tester, find.text('Habits heute'));
    expect(find.text('Menschen'), findsNothing);
    await disposeApp(tester, db);
  });

  testWidgets('the gift list button opens the person\'s gift list and creates it only once', (tester) async {
    useTallScreen(tester);
    final r = repo();
    late int id;
    final user = await seedDb(tester, db, () async {
      final u = await createTestUser(db);
      id = await r.saveContact(Contact(userid: u.uid, name: 'Tom', birthday: DateTime(1985, 12, 1), phone: '0170 123456'));
      return u;
    });
    await tester.pumpWidget(testApp(db, ContactScreen(contactId: id)));
    await pumpUntil(tester, find.text('0170 123456'));
    expect(find.textContaining('wird'), findsOneWidget);
    for (var i = 0; i < 2; i++) {
      await tester.tap(find.text('Geschenkliste'));
      await pumpUntil(tester, find.text('Tom · Geburtstag'));
      await pageBack(tester);
      await pumpUntil(tester, find.text('Geschenkliste').hitTestable());
    }
    final lists = await readDb(tester, () => ListsRepository(db: db, inventory: InventoryRepository(db: db)).getGiftLists(user.uid));
    expect(lists.single.date!.month, 12);
    await disposeApp(tester, db);
  });

  testWidgets('global search finds contacts by a note and opens them', (tester) async {
    useTallScreen(tester);
    final r = repo();
    final user = await seedDb(tester, db, () async {
      final u = await createTestUser(db);
      final lena = await r.saveContact(Contact(userid: u.uid, name: 'Lena', relation: 'Kollegin'));
      await r.saveNote(ContactNote(userid: u.uid, contactId: lena, text: 'Hund heißt Bello', created: DateTime.now()));
      return u;
    });
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
    await tester.enterText(find.byType(TextField), 'bello');
    await pumpUntil(tester, find.text('Kollegin'));
    await tester.tap(find.text('Lena'));
    await pumpUntil(tester, find.text('Hund heißt Bello'));
    await disposeApp(tester, db);
  });
}
