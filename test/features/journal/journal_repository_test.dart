import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:frontend/core/database/database.dart';
import 'package:frontend/core/services/notification_service.dart';
import 'package:frontend/features/auth/models/user.dart';
import 'package:frontend/features/finance/repositories/account_repository.dart';
import 'package:frontend/features/finance/repositories/category_repository.dart';
import 'package:frontend/features/finance/repositories/transaction_repository.dart';
import 'package:frontend/features/finance/repositories/user_repository.dart';
import 'package:frontend/features/finance/services/export_service.dart';
import 'package:frontend/features/journal/models/journal_entry.dart';
import 'package:frontend/features/journal/repositories/journal_repository.dart';

import '../../helpers/test_app.dart';

void main() {
  late DatabaseService db;
  late UserModel user;
  late RecordingNotifications notifications;
  late JournalRepository repo;
  final day = DateTime(2026, 10, 11);

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    db = createTestDatabase();
    user = await createTestUser(db);
    notifications = RecordingNotifications();
    repo = JournalRepository(db: db, notifications: notifications);
  });
  tearDown(() => db.close());

  test('one entry per day: saving the same day again updates it instead of adding a second one', () async {
    final id = await repo.saveEntry(JournalEntry(
      userid: user.uid,
      date: DateTime(2026, 10, 11, 21, 30), // Uhrzeit egal – es zählt der Tag
      mood: Mood.good,
      answers: {JournalEntry.prompts[0]: 'Sonne beim Joggen', JournalEntry.prompts[1]: '  '},
    ));
    // Zweites „Neu“ am selben Tag (Editor kannte den Eintrag nicht)
    final again = await repo.saveEntry(JournalEntry(userid: user.uid, date: day, mood: Mood.great, text: 'Abends Pizza'));

    expect(again, id);
    final entry = (await repo.getEntries(user.uid)).single;
    expect((entry.mood, entry.text, entry.date), (Mood.great, 'Abends Pizza', day));
    expect((await repo.getEntry(user.uid, day))!.id, id);
  });

  test('empty answers are not stored, broken answer JSON still shows the entry', () async {
    await repo.saveEntry(JournalEntry(userid: user.uid, date: day, answers: {JournalEntry.prompts[0]: 'Familie', JournalEntry.prompts[2]: ' '}));
    expect((await repo.getEntry(user.uid, day))!.answers, {JournalEntry.prompts[0]: 'Familie'});

    final raw = await db.database;
    await raw.update('journal_entries', {'answers': '{kaputt'});
    final broken = (await repo.getEntry(user.uid, day))!;
    expect(broken.answers, isEmpty);
  });

  test('moving an entry to a day that already has one merges into that day', () async {
    final first = await repo.saveEntry(JournalEntry(userid: user.uid, date: day, text: 'Sonntag'));
    final saturdayId = await repo.saveEntry(JournalEntry(userid: user.uid, date: DateTime(2026, 10, 10), text: 'Samstag'));
    // Samstag-Eintrag auf Sonntag umdatiert
    final id = await repo.saveEntry(JournalEntry(id: saturdayId, userid: user.uid, date: day, text: 'Samstag, nachgetragen'));

    expect(id, first);
    final entries = await repo.getEntries(user.uid);
    expect(entries.map((e) => (e.date, e.text)), [(day, 'Samstag, nachgetragen')]);
  });

  test('search finds text and answers; delete hides an entry and restore brings it back', () async {
    await repo.saveEntry(JournalEntry(userid: user.uid, date: day, text: 'Wanderung am Neckar'));
    final id = await repo.saveEntry(JournalEntry(userid: user.uid, date: DateTime(2026, 10, 9), answers: {JournalEntry.prompts[0]: 'Gutes Gespräch mit Oma'}));
    await repo.saveEntry(JournalEntry(userid: user.uid, date: DateTime(2026, 10, 8), text: 'Nichts Besonderes'));

    expect((await repo.getEntries(user.uid, search: 'neckar')).map((e) => e.text), ['Wanderung am Neckar']);
    expect((await repo.getEntries(user.uid, search: 'OMA')).single.id, id);
    expect((await repo.getEntries(user.uid)).map((e) => e.date.day), [11, 9, 8]); // neueste zuerst

    await repo.deleteEntry(id);
    expect(await repo.getEntries(user.uid, search: 'oma'), isEmpty);
    await repo.restoreEntry(id);
    expect((await repo.getEntries(user.uid, search: 'oma')).single.id, id);
  });

  test('mood series covers every day of the range, oldest first, with gaps as null', () async {
    await repo.saveEntry(JournalEntry(userid: user.uid, date: DateTime(2026, 10, 9), mood: Mood.bad));
    await repo.saveEntry(JournalEntry(userid: user.uid, date: day, mood: Mood.great));
    await repo.saveEntry(JournalEntry(userid: user.uid, date: DateTime(2026, 10, 1), mood: Mood.okay)); // außerhalb

    final series = await repo.moodSeries(user.uid, days: 4, today: day);
    expect(series, [
      (DateTime(2026, 10, 8), null),
      (DateTime(2026, 10, 9), Mood.bad),
      (DateTime(2026, 10, 10), null),
      (DateTime(2026, 10, 11), Mood.great),
    ]);
  });

  test('the daily reminder is stored per user, scheduled, switched off and rescheduled after sign-out', () async {
    final id = NotificationService.journalIdOffset + user.uid;
    expect(await repo.getReminder(user.uid), isNull);

    await repo.setReminder(user.uid, (21, 5));
    expect(await repo.getReminder(user.uid), (21, 5));
    expect(notifications.daily[id], ('Journal', 21, 5));

    await notifications.cancelAllNotifications(); // Abmelden
    await repo.refreshReminder(user.uid); // Anmelden
    expect(notifications.daily[id], ('Journal', 21, 5));

    await repo.setReminder(user.uid, null);
    expect(notifications.daily, isEmpty);
    expect(await repo.getReminder(user.uid), isNull);
  });

  test('the JSON export contains the journal, deleting the account removes it', () async {
    await repo.saveEntry(JournalEntry(userid: user.uid, date: day, text: 'Geheim'));
    final export = ExportService(
      db: db,
      users: UserRepository(db: db),
      accounts: AccountRepository(db: db),
      categories: CategoryRepository(db: db),
      transactions: TransactionRepository(db: db, notifications: notifications),
    );
    final json = jsonDecode(await export.generateJson(user.uid)) as Map<String, dynamic>;
    expect((json['journal_entries'] as List).single['text'], 'Geheim');

    await UserRepository(db: db).deleteUser(user.uid);
    final raw = await db.database;
    expect(await raw.query('journal_entries'), isEmpty);
  });
}
