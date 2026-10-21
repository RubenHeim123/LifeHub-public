import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:frontend/core/database/database.dart';
import 'package:frontend/features/dashboard/screens/home.dart';
import 'package:frontend/features/learning/models/flash_card.dart';
import 'package:frontend/features/learning/repositories/learning_repository.dart';
import 'package:frontend/features/learning/screens/learning_screen.dart';

import '../../helpers/test_app.dart';

void main() {
  late DatabaseService db;

  setUpAll(() => initializeDateFormatting('de_DE'));
  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({});
    db = createTestDatabase();
  });

  testWidgets('create a deck, import cards, study them: the due counter drops', (tester) async {
    useTallScreen(tester);
    final user = await seedDb(tester, db, () => createTestUser(db));
    await tester.pumpWidget(testApp(db, LearningScreen(user: user)));
    await pumpUntil(tester, find.text('Noch keine Karteikarten'));

    await tester.tap(find.text('Stapel'));
    await pumpUntil(tester, find.text('Neuer Stapel'));
    await tester.enterText(find.byType(TextFormField), 'Spanisch');
    await tester.tap(find.text('Speichern'));
    await pumpUntil(tester, find.text('Noch keine Karten'));

    await tester.tap(find.text('Importieren'));
    await pumpUntil(tester, find.text('Karten importieren'));
    await tester.enterText(find.byType(TextField).last, 'el perro – der Hund\nla casa – das Haus\nohne Trenner');
    await tester.pump();
    await tester.tap(find.text('2 Karten importieren'));
    await pumpUntil(tester, find.text('el perro'));
    expect(find.text('2 fällig'), findsOneWidget);

    await tester.tap(find.text('Lernen'));
    await pumpUntil(tester, find.text('Antwort zeigen').hitTestable());
    expect(find.text('der Hund'), findsNothing);
    await tester.tap(find.text('Antwort zeigen'));
    await pumpUntil(tester, find.text('der Hund'));
    expect(find.text('10 Min'), findsOneWidget);
    await tester.tap(find.text('Gut'));
    await pumpUntil(tester, find.text('la casa'));
    await tester.tap(find.text('Antwort zeigen'));
    await pumpUntil(tester, find.text('Nochmal'));
    await tester.tap(find.text('Nochmal'));
    await pumpUntil(tester, find.text('Antwort zeigen').hitTestable());
    expect(find.text('la casa'), findsOneWidget); // „Nochmal“ kommt in derselben Runde wieder
    await tester.tap(find.text('Antwort zeigen'));
    await pumpUntil(tester, find.text('Leicht'));
    await tester.tap(find.text('Leicht'));
    await pumpUntil(tester, find.text('Fertig für heute'));

    await tester.tap(find.text('Zurück'));
    await pumpUntil(tester, find.text('Nichts fällig'));
    await pageBack(tester);
    await pumpUntil(tester, find.text('Alles gelernt'));
    expect(find.text('0 fällig · 2 Karten'), findsOneWidget);
    await disposeApp(tester, db);
  });

  testWidgets('Heute shows the number of due cards', (tester) async {
    useTallScreen(tester);
    final repo = LearningRepository(db: db);
    final user = await seedDb(tester, db, () async {
      final u = await createTestUser(db);
      final id = await repo.saveDeck(Deck(userid: u.uid, name: 'Erdkunde'));
      await repo.importCards(u.uid, id, 'Frankreich – Paris\nSpanien – Madrid\nItalien – Rom');
      return u;
    });
    await tester.pumpWidget(testApp(db, Home(user: user)));
    await pumpUntil(tester, find.text('3 Karten fällig'));
    await disposeApp(tester, db);
  });

  testWidgets('Heute has no learning card without due cards', (tester) async {
    useTallScreen(tester);
    final empty = await seedDb(tester, db, () => createTestUser(db));
    await tester.pumpWidget(testApp(db, Home(user: empty)));
    await pumpUntil(tester, find.text('Habits heute'));
    expect(find.textContaining('Karten fällig'), findsNothing);
    await disposeApp(tester, db);
  });
}
