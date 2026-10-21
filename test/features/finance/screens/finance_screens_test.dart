import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'package:frontend/core/database/database.dart';
import 'package:frontend/core/ui/form_widgets.dart';
import 'package:frontend/features/auth/models/user.dart';
import 'package:frontend/features/finance/models/category.dart';
import 'package:frontend/features/finance/models/fixedtransaction.dart';
import 'package:frontend/features/finance/models/recurrence_interval.dart';
import 'package:frontend/features/finance/models/transaction.dart' as tr;
import 'package:frontend/features/finance/models/transaction_type.dart';
import 'package:frontend/features/finance/repositories/category_repository.dart';
import 'package:frontend/features/finance/repositories/transaction_repository.dart';
import 'package:frontend/features/finance/screens/account_view.dart';
import 'package:frontend/features/finance/screens/add_update_fixedtransaction.dart';
import 'package:frontend/features/finance/screens/add_update_category.dart';
import 'package:frontend/features/finance/screens/add_update_account.dart';
import 'package:frontend/features/finance/screens/add_update_transactions.dart';
import 'package:frontend/features/finance/screens/category_view.dart';
import 'package:frontend/features/finance/screens/finance_hub_screen.dart';
import 'package:frontend/features/finance/screens/fixedtransaction_view.dart';
import 'package:frontend/features/finance/screens/transaction_view.dart';

import '../../../helpers/test_app.dart';

void main() {
  late DatabaseService db;

  setUpAll(() => initializeDateFormatting('de_DE'));
  setUp(() => db = createTestDatabase());

  /// Nutzer mit Girokonto (100 €), Sparkonto (0 €) und Kategorie "Lebensmittel".
  Future<UserModel> seedFinance(WidgetTester tester, {bool withData = false}) {
    return seedDb(tester, db, () async {
      final user = await createTestUser(db);
      await createTestAccount(db, user.uid, 'Girokonto', amount: 100);
      await createTestAccount(db, user.uid, 'Sparkonto');
      await CategoryRepository(db: db).createCategory(Category(
        categoryName: 'Lebensmittel',
        categoryUserid: user.uid,
        categoryFontFamily: 'MaterialIcons',
        categoryIconName: 'category',
        categoryCodePoint: Icons.category.codePoint,
        transactionType: TransactionType.expense,
        monthlyBudget: 300,
      ));
      if (withData) {
        final transactions = TransactionRepository(db: db);
        await transactions.createTransaction(tr.Transaction(
          date: DateTime.now().subtract(const Duration(hours: 1)),
          amount: 25,
          category: 'Lebensmittel',
          description: 'Wocheneinkauf',
          account: 'Girokonto',
          transactionType: TransactionType.expense,
          userid: user.uid,
        ));
        final now = DateTime.now();
        final start = DateTime(now.year, now.month, now.day).add(const Duration(days: 3));
        await transactions.createFixedTransaction(FixedTransaction(
          startTime: start,
          endTime: DateTime(2300),
          nextTime: start,
          interval: RecurrenceInterval.monthly,
          amount: 800,
          category: 'Miete',
          description: 'Wohnung',
          account: 'Girokonto',
          transactionType: TransactionType.expense,
          userid: user.uid,
        ));
      }
      return user;
    });
  }

  Future<double> balance(WidgetTester tester, UserModel user, String account) async =>
      (await readDb(tester, () => balanceOf(db, user.uid, account)));

  group('AddUpdateTransaction', () {
    testWidgets('creating an expense lowers the account balance', (tester) async {
      useTallScreen(tester);
      final user = await seedFinance(tester);
      await tester.pumpWidget(testApp(db, launcher(AddUpdateTransaction(userid: user.uid))));
      await tester.tap(find.text('öffnen'));
      await pumpUntil(tester, find.text('Neue Transaktion'));

      await enterInCard(tester, 'Betrag', '12,50');
      await selectDropdown(tester, 'Kategorie', 'Lebensmittel');
      await selectDropdown(tester, 'Konto', 'Girokonto');
      await tester.tap(find.text('Hinzufügen'));

      await pumpUntil(tester, find.text('result:true'));
      expect(await balance(tester, user, 'Girokonto'), 87.5);
      await disposeApp(tester, db);
    });

    testWidgets('a transfer moves money between two accounts', (tester) async {
      useTallScreen(tester);
      final user = await seedFinance(tester);
      await tester.pumpWidget(testApp(db, launcher(AddUpdateTransaction(userid: user.uid))));
      await tester.tap(find.text('öffnen'));
      await pumpUntil(tester, find.text('Neue Transaktion'));

      await selectDropdown(tester, 'Transaktionstyp', 'Umbuchung');
      await enterInCard(tester, 'Betrag', '40');
      await selectDropdown(tester, 'Konto', 'Girokonto');
      await selectDropdown(tester, 'Zielkonto', 'Sparkonto');
      await tester.tap(find.text('Hinzufügen'));

      await pumpUntil(tester, find.text('result:true'));
      expect(await balance(tester, user, 'Girokonto'), 60);
      expect(await balance(tester, user, 'Sparkonto'), 40);
      await disposeApp(tester, db);
    });

    testWidgets('saving without required fields shows validation errors', (tester) async {
      useTallScreen(tester);
      final user = await seedFinance(tester);
      await tester.pumpWidget(testApp(db, launcher(AddUpdateTransaction(userid: user.uid))));
      await tester.tap(find.text('öffnen'));
      await pumpUntil(tester, find.text('Neue Transaktion'));

      await tester.tap(find.text('Hinzufügen'));
      await tester.pump();

      expect(find.text('Betrag erforderlich'), findsOneWidget);
      expect(find.text('Erforderlich'), findsWidgets);
      expect(await balance(tester, user, 'Girokonto'), 100);
      await disposeApp(tester, db);
    });
  });

  group('finance editors', () {
    Future<void> openEditor(WidgetTester tester, Widget editor, String ready) async {
      await tester.pumpWidget(testApp(db, launcher(editor)));
      await tester.tap(find.text('öffnen'));
      await pumpUntil(tester, find.text(ready));
    }

    testWidgets('account: create with a comma balance; a duplicate name is refused with a message', (tester) async {
      useTallScreen(tester);
      final user = await seedFinance(tester);
      await openEditor(tester, AddUpdateAccount(userid: user.uid), 'Kontoname');
      await enterInCard(tester, 'Kontoname', 'girokonto ');
      await enterInCard(tester, 'Kontostand', '50');
      await tester.tap(find.text('Hinzufügen'));
      await pumpUntil(tester, find.textContaining('gibt es schon'));
      expect(find.text('result:true'), findsNothing); // Editor bleibt offen

      await enterInCard(tester, 'Kontoname', 'Bargeld');
      await enterInCard(tester, 'Kontostand', '12,30');
      await tester.tap(find.text('Hinzufügen'));
      await pumpUntil(tester, find.text('result:true'));
      expect(await balance(tester, user, 'Bargeld'), 12.3);
      await disposeApp(tester, db);
    });

    testWidgets('category: income type with expected amount is saved', (tester) async {
      useTallScreen(tester);
      final user = await seedFinance(tester);
      await openEditor(tester, AddUpdateCategory(userid: user.uid), 'Kategoriename');
      await enterInCard(tester, 'Kategoriename', 'Nebenjob');
      await selectDropdown(tester, 'Transaktionstyp', 'Einnahme');
      await enterInCard(tester, 'Erwartete Einnahmen (€)', '450');
      await tester.tap(find.text('Hinzufügen'));
      await pumpUntil(tester, find.text('result:true'));

      final saved = (await readDb(tester, () => CategoryRepository(db: db).getAllCategories(user.uid)))
          .firstWhere((c) => c.categoryName == 'Nebenjob');
      expect((saved.transactionType, saved.monthlyBudget), (TransactionType.income, 450.0));
      await disposeApp(tester, db);
    });

    testWidgets('fixed cost: starting today books the first occurrence right away', (tester) async {
      useTallScreen(tester);
      final user = await seedFinance(tester);
      await openEditor(tester, AddUpdateFixedTransaction(userid: user.uid), 'Intervall');
      await enterInCard(tester, 'Betrag', '9,99');
      final start = find.ancestor(of: find.text('Startdatum'), matching: find.byType(FormFieldCard)).first;
      await tester.tap(find.descendant(of: start, matching: find.byType(TextFormField)));
      await pumpUntil(tester, find.byType(DatePickerDialog));
      await tester.tap(find.text('OK'));
      await pumpUntilGone(tester, find.byType(DatePickerDialog));
      await selectDropdown(tester, 'Kategorie', 'Lebensmittel');
      await enterInCard(tester, 'Beschreibung', 'Streaming');
      await selectDropdown(tester, 'Konto', 'Girokonto');
      await tester.ensureVisible(find.text('Hinzufügen'));
      await tester.tap(find.text('Hinzufügen'));
      await pumpUntil(tester, find.text('result:true'));

      final repo = TransactionRepository(db: db);
      final series = (await readDb(tester, () => repo.getAllFixedTransactions(user.uid))).single;
      expect((series.amount, series.description, series.interval), (9.99, 'Streaming', RecurrenceInterval.monthly));
      expect(series.nextTime.isAfter(DateTime.now()), isTrue);
      expect((await readDb(tester, () => repo.getAllTransactions(user.uid))).single.amount, 9.99);
      expect(await balance(tester, user, 'Girokonto'), closeTo(90.01, 0.001));
      await disposeApp(tester, db);
    });
  });

  group('list screens', () {
    testWidgets('undo: a deleted booking gives the money back, undo takes it again', (tester) async {
      useTallScreen(tester);
      final user = await seedFinance(tester, withData: true);
      await tester.pumpWidget(testApp(db, TransactionView(user: user)));
      await pumpUntil(tester, find.text('Wocheneinkauf'));
      expect(await balance(tester, user, 'Girokonto'), 75);

      await swipeDelete(tester, find.text('Wocheneinkauf'));
      await pumpUntilGone(tester, find.text('Wocheneinkauf'));
      expect(await balance(tester, user, 'Girokonto'), 100);
      await tester.tap(find.text('Rückgängig'));
      await pumpUntil(tester, find.text('Wocheneinkauf'));
      expect(await balance(tester, user, 'Girokonto'), 75);
      await disposeApp(tester, db);
    });

    testWidgets('undo: an account with bookings is not deleted, an empty one comes back', (tester) async {
      useTallScreen(tester);
      final user = await seedFinance(tester, withData: true);
      await tester.pumpWidget(testApp(db, AccountView(user: user)));
      await pumpUntil(tester, find.text('Sparkonto'));

      await tester.drag(find.text('Girokonto'), const Offset(-400, 0));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Löschen'));
      await pumpUntil(tester, find.textContaining('hat noch'));
      expect(find.text('Girokonto'), findsOneWidget);

      await swipeDelete(tester, find.text('Sparkonto'));
      await pumpUntilGone(tester, find.text('Sparkonto'));
      await tester.tap(find.text('Rückgängig'));
      await pumpUntil(tester, find.text('Sparkonto'));
      await disposeApp(tester, db);
    });

    testWidgets('undo: categories and fixed costs come back after deleting', (tester) async {
      useTallScreen(tester);
      final user = await seedFinance(tester, withData: true);
      await tester.pumpWidget(testApp(db, CategoryView(user: user)));
      await pumpUntil(tester, find.text('Lebensmittel'));
      await swipeDelete(tester, find.text('Lebensmittel'));
      await pumpUntilGone(tester, find.text('Lebensmittel'));
      await tester.tap(find.text('Rückgängig'));
      await pumpUntil(tester, find.text('Lebensmittel'));

      await tester.pumpWidget(testApp(db, FixedTransactionView(user: user)));
      await pumpUntil(tester, find.text('Miete'));
      await swipeDelete(tester, find.text('Miete'));
      await pumpUntilGone(tester, find.text('Miete'));
      expect(await readDb(tester, () => TransactionRepository(db: db).getAllFixedTransactions(user.uid)), isEmpty);
      await tester.tap(find.text('Rückgängig'));
      await pumpUntil(tester, find.text('Miete'));
      expect(await readDb(tester, () => TransactionRepository(db: db).getAllFixedTransactions(user.uid)), hasLength(1));
      await disposeApp(tester, db);
    });

    testWidgets('a loading error shows a message with retry instead of an endless spinner', (tester) async {
      useTallScreen(tester);
      final user = await seedDb(tester, db, () async {
        final user = await createTestUser(db);
        final raw = await db.database;
        await raw.insert('accounts', {
          'accountName': 'Kaputt',
          'accountUserid': user.uid,
          'accountAmount': 'kein-betrag',
          'accountCodePoint': 0,
          'accountFontFamily': 'MaterialIcons',
          'accountIconName': 'wallet',
        });
        return user;
      });
      await tester.pumpWidget(testApp(db, AccountView(user: user)));
      await pumpUntil(tester, find.text('Laden fehlgeschlagen'));
      expect(find.text('Erneut versuchen'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      await disposeApp(tester, db);
    });

    testWidgets('TransactionView lists transactions of the month', (tester) async {
      useTallScreen(tester);
      final user = await seedFinance(tester, withData: true);
      await tester.pumpWidget(testApp(db, TransactionView(user: user)));
      await pumpUntil(tester, find.text('Wocheneinkauf'));

      expect(find.text('−25,00 €'), findsWidgets);
      await disposeApp(tester, db);
    });

    testWidgets('AccountView shows accounts and total wealth', (tester) async {
      useTallScreen(tester);
      final user = await seedFinance(tester);
      await tester.pumpWidget(testApp(db, AccountView(user: user)));
      await pumpUntil(tester, find.text('Gesamtvermögen'));

      expect(find.text('Girokonto'), findsOneWidget);
      expect(find.text('Sparkonto'), findsOneWidget);
      expect(find.text('100,00 €'), findsWidgets);
      // Die Vermögenskarte (samt 16 px Rand) ist so breit wie der Screen, nicht nur so breit wie ihr Text.
      final card = find.ancestor(
          of: find.text('Gesamtvermögen'), matching: find.byWidgetPredicate((w) => w is Container && w.margin == const EdgeInsets.all(16)));
      expect(tester.getSize(card).width, tester.view.physicalSize.width / tester.view.devicePixelRatio);
      await disposeApp(tester, db);
    });

    testWidgets('CategoryView shows categories grouped by type', (tester) async {
      useTallScreen(tester);
      final user = await seedFinance(tester);
      await tester.pumpWidget(testApp(db, CategoryView(user: user)));
      await pumpUntil(tester, find.text('Lebensmittel'));

      expect(find.text('Ausgaben'), findsWidgets);
      await disposeApp(tester, db);
    });

    testWidgets('FixedTransactionView shows recurring payments', (tester) async {
      useTallScreen(tester);
      final user = await seedFinance(tester, withData: true);
      await tester.pumpWidget(testApp(db, FixedTransactionView(user: user)));
      await pumpUntil(tester, find.text('Miete'));

      expect(find.text('Monatlich'), findsOneWidget);
      expect(find.text('unbegrenzt'), findsOneWidget); // statt „Bis: 01.01.2300“
      await disposeApp(tester, db);
    });

    testWidgets('FinanceHubScreen shows balance, budgets and navigation', (tester) async {
      useTallScreen(tester);
      final user = await seedFinance(tester, withData: true);
      await tester.pumpWidget(testApp(db, FinanceHubScreen(user: user)));
      await pumpUntil(tester, find.text('Gesamtbilanz'));

      // Monatsplanung: keine Fixeinnahmen, 800 € Miete + 300 € Budget → Warnung
      await tester.ensureVisible(find.textContaining('Monatsplanung', skipOffstage: false));
      expect(find.text('FIXAUSGABEN'), findsOneWidget);
      expect(find.text('Wohnung'), findsOneWidget);
      expect(find.textContaining('fällig am'), findsOneWidget);
      expect(find.textContaining('übersteigen deine Fixeinnahmen um 1.100,00 €'), findsOneWidget);
      expect(find.text('noch offen: 275,00 €'), findsOneWidget); // 300 € Budget − 25 € ausgegeben
      expect(find.text('Lebensmittel'), findsWidgets);
      expect(find.text('Transaktionen'), findsOneWidget);
      await disposeApp(tester, db);
    });

    testWidgets('FinanceHubScreen keeps income and expense categories of the same name apart', (tester) async {
      useTallScreen(tester);
      final user = await seedFinance(tester);
      await seedDb(tester, db, () async {
        final transactions = TransactionRepository(db: db);
        for (final (amount, type) in [(50.0, TransactionType.income), (20.0, TransactionType.expense)]) {
          await transactions.createTransaction(tr.Transaction(
            date: DateTime.now().subtract(const Duration(hours: 1)),
            amount: amount,
            category: 'Geschenke',
            description: 'Geburtstag',
            account: 'Girokonto',
            transactionType: type,
            userid: user.uid,
          ));
        }
      });
      await tester.pumpWidget(testApp(db, FinanceHubScreen(user: user)));
      await pumpUntil(tester, find.text('Gesamtbilanz'));
      final rows = find.byWidgetPredicate((w) => w is Hero && '${w.tag}'.startsWith('cat_icon_') && '${w.tag}'.endsWith('_Geschenke'),
          skipOffstage: false);
      expect(rows, findsNWidgets(2)); // vorher: eine Zeile mit 50 − 20 = 30 €
      await disposeApp(tester, db);
    });
  });
}
