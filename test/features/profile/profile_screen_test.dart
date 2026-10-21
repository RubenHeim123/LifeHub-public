import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'package:frontend/core/database/database.dart';
import 'package:frontend/features/auth/services/auth.dart';
import 'package:frontend/features/finance/repositories/account_repository.dart';
import 'package:frontend/features/finance/repositories/category_repository.dart';
import 'package:frontend/features/finance/repositories/user_repository.dart';
import 'package:frontend/features/profile/screens/profile_screen.dart';

import '../../helpers/test_app.dart';

void main() {
  late DatabaseService db;

  setUpAll(() => initializeDateFormatting('de_DE'));
  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    db = createTestDatabase();
  });

  AuthService auth() => AuthService(
        users: UserRepository(db: db),
        accounts: AccountRepository(db: db),
        categories: CategoryRepository(db: db),
      );

  testWidgets('password can be changed from the profile', (tester) async {
    useTallScreen(tester);
    final user = await seedDb(tester, db, () => auth().registerWithEmailAndPassword('p@test.de', 'altesPw1'));

    await tester.pumpWidget(testApp(db, launcher(ProfilePage(user: user))));
    await tester.tap(find.text('öffnen'));
    await pumpUntil(tester, find.text('Passwort ändern'));

    await tester.tap(find.text('Passwort ändern'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextFormField, 'Aktuelles Passwort'), 'falsch');
    await tester.enterText(find.widgetWithText(TextFormField, 'Neues Passwort'), 'neuesPw1');
    await tester.enterText(find.widgetWithText(TextFormField, 'Neues Passwort wiederholen'), 'neuesPw1');
    await tester.tap(find.text('Ändern'));
    await pumpUntil(tester, find.text('Aktuelles Passwort ist falsch.'));

    await tester.enterText(find.widgetWithText(TextFormField, 'Aktuelles Passwort'), 'altesPw1');
    await tester.tap(find.text('Ändern'));
    await pumpUntil(tester, find.text('Passwort geändert'));

    final ok = await readDb(tester, () => auth().signInWithEmailAndPassword('p@test.de', 'neuesPw1'));
    expect(ok, isNotNull);
    await disposeApp(tester, db);
  });

  testWidgets('saving the profile keeps the password and updates the name', (tester) async {
    useTallScreen(tester);
    final user = await seedDb(tester, db, () => auth().registerWithEmailAndPassword('p@test.de', 'altesPw1'));

    await tester.pumpWidget(testApp(db, launcher(ProfilePage(user: user))));
    await tester.tap(find.text('öffnen'));
    await pumpUntil(tester, find.text('Profil aktualisieren'));

    await tester.enterText(find.widgetWithText(TextFormField, 'Name'), 'Alex');
    await tester.tap(find.text('Profil aktualisieren'));
    await pumpUntil(tester, find.textContaining('result:'));

    final stored = (await readDb(tester, () => UserRepository(db: db).getUser(user.uid)));
    expect(stored.displayName, 'Alex');
    expect(stored.password, user.password);
    await disposeApp(tester, db);
  });
}
