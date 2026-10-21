import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'package:frontend/app/home_shell.dart';
import 'package:frontend/core/database/database.dart';
import 'package:frontend/features/auth/screens/wrapper.dart';
import 'package:frontend/features/auth/models/user.dart';
import 'package:frontend/features/auth/services/auth.dart';
import 'package:frontend/features/auth/services/password_hasher.dart';
import 'package:frontend/features/finance/repositories/account_repository.dart';
import 'package:frontend/features/finance/repositories/category_repository.dart';
import 'package:frontend/features/finance/repositories/user_repository.dart';

import '../../helpers/test_app.dart';

void main() {
  late DatabaseService db;

  setUpAll(() => initializeDateFormatting('de_DE'));

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    db = createTestDatabase();
  });

  Future<void> fill(WidgetTester tester, String label, String text) =>
      tester.enterText(find.widgetWithText(TextFormField, label), text);

  testWidgets('registering opens the app and seeds default data', (tester) async {
    await tester.pumpWidget(testApp(db, const Wrapper()));
    await pumpUntil(tester, find.text('Willkommen zurück'));

    await tester.tap(find.text('Registrieren'));
    await tester.pump();
    await fill(tester, 'E-Mail', 'neu@test.de');
    await fill(tester, 'Passwort', 'geheim123');
    await tester.tap(find.widgetWithText(ElevatedButton, 'Registrieren'));

    await pumpUntil(tester, find.byType(HomeShell));
    final user = (await readDb(tester, () => UserRepository(db: db).getUserFromEmail('neu@test.de')));
    expect(user, isNotNull);
    await disposeApp(tester, db);
  });

  testWidgets('registration checks the e-mail address before creating an account', (tester) async {
    await tester.pumpWidget(testApp(db, const Wrapper()));
    await pumpUntil(tester, find.text('Willkommen zurück'));
    await tester.tap(find.text('Registrieren'));
    await tester.pump();

    await fill(tester, 'Passwort', 'geheim123');
    await tester.tap(find.widgetWithText(ElevatedButton, 'Registrieren'));
    await tester.pump();
    expect(find.text('Bitte gib deine E-Mail-Adresse ein'), findsOneWidget);

    await fill(tester, 'E-Mail', 'ohne-at-zeichen');
    await tester.tap(find.widgetWithText(ElevatedButton, 'Registrieren'));
    await tester.pump();
    expect(find.text('Das sieht nicht nach einer E-Mail-Adresse aus'), findsOneWidget);
    expect(await readDb(tester, () => UserRepository(db: db).getUserFromEmail('ohne-at-zeichen')), isNull);
    await disposeApp(tester, db);
  });

  testWidgets('wrong password shows an error, correct password signs in', (tester) async {
    await seedDb(tester, db, () => AuthService(
          users: UserRepository(db: db),
          accounts: AccountRepository(db: db),
          categories: CategoryRepository(db: db),
        ).registerWithEmailAndPassword('user@test.de', 'geheim123'));
    FlutterSecureStorage.setMockInitialValues({}); // abgemeldet starten

    await tester.pumpWidget(testApp(db, const Wrapper()));
    await pumpUntil(tester, find.text('Willkommen zurück'));

    await fill(tester, 'E-Mail', 'user@test.de');
    await fill(tester, 'Passwort', 'falsch123');
    await tester.tap(find.widgetWithText(ElevatedButton, 'Anmelden'));
    await pumpUntil(tester, find.textContaining('Das Passwort stimmt nicht'));

    await fill(tester, 'Passwort', 'geheim123');
    await tester.tap(find.widgetWithText(ElevatedButton, 'Anmelden'));
    await pumpUntil(tester, find.byType(HomeShell));
    await disposeApp(tester, db);
  });

  testWidgets('unknown email suggests registering', (tester) async {
    await tester.pumpWidget(testApp(db, const Wrapper()));
    await pumpUntil(tester, find.text('Willkommen zurück'));

    await fill(tester, 'E-Mail', 'niemand@test.de');
    await fill(tester, 'Passwort', 'geheim123');
    await tester.tap(find.widgetWithText(ElevatedButton, 'Anmelden'));
    await pumpUntil(tester, find.textContaining('kein Konto'));
    await disposeApp(tester, db);
  });

  testWidgets('account from an old version: hint and "Passwort vergessen?" sets a new password', (tester) async {
    useTallScreen(tester);
    final uid = await seedDb(tester, db, () => UserRepository(db: db)
        .createUser(UserModel(uid: 0, email: 'alt@test.de', password: 'abcdef0123456789-unbekannt')));

    await tester.pumpWidget(testApp(db, const Wrapper()));
    await pumpUntil(tester, find.text('Willkommen zurück'));

    await fill(tester, 'E-Mail', 'alt@test.de');
    await fill(tester, 'Passwort', 'geheim123');
    await tester.tap(find.widgetWithText(ElevatedButton, 'Anmelden'));
    await pumpUntil(tester, find.textContaining('älteren App-Version'));

    await tester.ensureVisible(find.text('Passwort vergessen?'));
    await tester.tap(find.text('Passwort vergessen?'));
    await pumpUntil(tester, find.text('Neues Passwort festlegen'));
    final dialog = find.byType(AlertDialog);
    await tester.enterText(find.descendant(of: dialog, matching: find.widgetWithText(TextFormField, 'Neues Passwort')), 'neuesPw1');
    await tester.enterText(find.descendant(of: dialog, matching: find.widgetWithText(TextFormField, 'Passwort wiederholen')), 'neuesPw1');
    await tester.tap(find.widgetWithText(ElevatedButton, 'Speichern'));
    await pumpUntil(tester, find.byType(HomeShell));

    final user = await readDb(tester, () => UserRepository(db: db).getUser(uid));
    expect(PasswordHasher.isCurrentFormat(user.password), isTrue);
    for (var i = 0; i < 4; i++) {
      await settleDb(tester); // Heute-Screen fertig laden lassen
    }
    await disposeApp(tester, db);
  });

  testWidgets('registering an existing email explains what to do', (tester) async {
    await seedDb(tester, db, () => AuthService(
          users: UserRepository(db: db),
          accounts: AccountRepository(db: db),
          categories: CategoryRepository(db: db),
        ).registerWithEmailAndPassword('user@test.de', 'geheim123'));
    FlutterSecureStorage.setMockInitialValues({});

    await tester.pumpWidget(testApp(db, const Wrapper()));
    await pumpUntil(tester, find.text('Willkommen zurück'));
    await tester.tap(find.text('Registrieren'));
    await tester.pump();
    await fill(tester, 'E-Mail', 'user@test.de');
    await fill(tester, 'Passwort', 'geheim123');
    await tester.tap(find.widgetWithText(ElevatedButton, 'Registrieren'));
    await pumpUntil(tester, find.textContaining('gibt es schon ein Konto'));
    await disposeApp(tester, db);
  });

  testWidgets('password shorter than 6 characters is rejected by the form', (tester) async {
    await tester.pumpWidget(testApp(db, const Wrapper()));
    await pumpUntil(tester, find.text('Willkommen zurück'));

    await fill(tester, 'E-Mail', 'user@test.de');
    await fill(tester, 'Passwort', '123');
    await tester.tap(find.widgetWithText(ElevatedButton, 'Anmelden'));
    await tester.pump();

    expect(find.text('Das Passwort muss mindestens 6 Zeichen lang sein'), findsOneWidget);
    await disposeApp(tester, db);
  });

  testWidgets('signed-in user with an outdated password hash is asked for a new password', (tester) async {
    final uid = await seedDb(tester, db, () => UserRepository(db: db)
        .createUser(UserModel(uid: 0, email: 'alt@test.de', password: 'hash-aus-alter-version')));
    FlutterSecureStorage.setMockInitialValues({'email': 'alt@test.de'});

    await tester.pumpWidget(testApp(db, const Wrapper()));
    await pumpUntil(tester, find.text('Neues Passwort festlegen'));

    await tester.enterText(find.widgetWithText(TextFormField, 'Neues Passwort'), 'neuesPw1');
    await tester.enterText(find.widgetWithText(TextFormField, 'Neues Passwort wiederholen'), 'neuesPw1');
    await tester.tap(find.widgetWithText(ElevatedButton, 'Speichern'));
    await pumpUntilGone(tester, find.text('Neues Passwort festlegen'));

    final user = (await readDb(tester, () => UserRepository(db: db).getUser(uid)));
    expect(PasswordHasher.isCurrentFormat(user.password), isTrue);
    await disposeApp(tester, db);
  });
}
