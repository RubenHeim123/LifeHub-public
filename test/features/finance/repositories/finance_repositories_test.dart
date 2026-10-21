import 'package:flutter_test/flutter_test.dart';

import 'package:frontend/core/database/database.dart';
import 'package:frontend/core/models/app_exceptions.dart';
import 'package:frontend/features/finance/models/account.dart';
import 'package:frontend/features/finance/models/category.dart';
import 'package:frontend/features/finance/models/financial_goal.dart';
import 'package:frontend/features/finance/models/fixedtransaction.dart';
import 'package:frontend/features/finance/models/recurrence_interval.dart';
import 'package:frontend/features/finance/models/transaction.dart' as tr;
import 'package:frontend/features/finance/models/transaction_type.dart';
import 'package:frontend/features/auth/models/user.dart';
import 'package:frontend/features/finance/repositories/account_repository.dart';
import 'package:frontend/features/finance/repositories/category_repository.dart';
import 'package:frontend/features/finance/repositories/financial_goal_repository.dart';
import 'package:frontend/features/finance/repositories/transaction_repository.dart';
import 'package:frontend/features/finance/repositories/user_repository.dart';

import '../../../helpers/test_app.dart';

void main() {
  late DatabaseService db;
  late TransactionRepository transactions;
  late UserModel alice;
  late UserModel bob;

  tr.Transaction tx(UserModel u, double amount, TransactionType type,
          {String account = 'Girokonto', String category = 'Lebensmittel', DateTime? date}) =>
      tr.Transaction(
        date: date ?? DateTime(2026, 3, 10),
        amount: amount,
        category: category,
        description: '',
        account: account,
        transactionType: type,
        userid: u.uid,
      );

  setUp(() async {
    db = createTestDatabase();
    transactions = TransactionRepository(db: db);
    alice = await createTestUser(db, email: 'alice@test.de');
    bob = await createTestUser(db, email: 'bob@test.de');
    // Beide haben – wie nach der Registrierung – ein Konto mit demselben Namen.
    await createTestAccount(db, alice.uid, 'Girokonto', amount: 100);
    await createTestAccount(db, bob.uid, 'Girokonto', amount: 500);
    await createTestAccount(db, alice.uid, 'Sparkonto');
  });

  tearDown(() => db.close());

  group('TransactionRepository balances', () {
    test('only changes the balance of the owning user', () async {
      // Alices "Girokonto" liegt zuerst in der Tabelle – die alte Suche nur per Name traf es.
      await transactions.createTransaction(tx(bob, 30, TransactionType.expense));

      expect(await balanceOf(db, bob.uid, 'Girokonto'), 470);
      expect(await balanceOf(db, alice.uid, 'Girokonto'), 100);
    });

    test('update moves the amount between accounts', () async {
      await transactions.createTransaction(tx(alice, 30, TransactionType.expense));
      final saved = (await transactions.getAllTransactions(alice.uid)).single;

      await transactions.updateTransaction(tr.Transaction(
        id: saved.id,
        date: saved.date,
        amount: 50,
        category: saved.category,
        description: '',
        account: 'Sparkonto',
        transactionType: TransactionType.expense,
        userid: alice.uid,
      ));

      expect(await balanceOf(db, alice.uid, 'Girokonto'), 100);
      expect(await balanceOf(db, alice.uid, 'Sparkonto'), -50);
    });

    test('deleting twice reverts the balance only once', () async {
      await transactions.createTransaction(tx(alice, 30, TransactionType.income));
      final id = (await transactions.getAllTransactions(alice.uid)).single.id!;

      await transactions.deleteTransaction(id);
      await transactions.deleteTransaction(id);

      expect(await balanceOf(db, alice.uid, 'Girokonto'), 100);
    });

    test('undo after delete books the amount again, only once', () async {
      await transactions.createTransaction(tx(alice, 30, TransactionType.expense));
      final id = (await transactions.getAllTransactions(alice.uid)).single.id!;
      expect(await balanceOf(db, alice.uid, 'Girokonto'), 70);

      await transactions.deleteTransaction(id);
      expect(await balanceOf(db, alice.uid, 'Girokonto'), 100);
      await transactions.restoreTransaction(id);
      await transactions.restoreTransaction(id);
      expect(await balanceOf(db, alice.uid, 'Girokonto'), 70);
      expect(await transactions.getAllTransactions(alice.uid), hasLength(1));
    });

    test('deleteAllTransactions reverts all balances', () async {
      await transactions.createTransaction(tx(alice, 30, TransactionType.expense));
      await transactions.createTransaction(tx(alice, 10, TransactionType.income, account: 'Sparkonto'));

      await transactions.deleteAllTransactions(alice.uid);

      expect(await transactions.getAllTransactions(alice.uid), isEmpty);
      expect(await balanceOf(db, alice.uid, 'Girokonto'), 100);
      expect(await balanceOf(db, alice.uid, 'Sparkonto'), 0);
    });

    test('transfer books expense and income atomically', () async {
      await transactions.createTransfer(
        userid: alice.uid,
        fromAccount: 'Girokonto',
        toAccount: 'Sparkonto',
        amount: 40,
        date: DateTime(2026, 3, 1),
      );

      final all = await transactions.getAllTransactions(alice.uid);
      expect(all, hasLength(2));
      expect(all.every((t) => t.isTransfer), isTrue);
      expect(await balanceOf(db, alice.uid, 'Girokonto'), 60);
      expect(await balanceOf(db, alice.uid, 'Sparkonto'), 40);
    });
  });

  group('bookDueFixedTransactions', () {
    FixedTransaction series(RecurrenceInterval interval, DateTime start, {DateTime? end}) => FixedTransaction(
          startTime: start,
          endTime: end ?? DateTime(2300),
          nextTime: start,
          interval: interval,
          amount: 10,
          category: 'Miete',
          description: '',
          account: 'Girokonto',
          transactionType: TransactionType.expense,
          userid: alice.uid,
        );

    Future<void> insertSeries(FixedTransaction ft) async {
      final database = await db.database;
      await database.insert('fixed_transactions', ft.toMap());
    }

    test('catches up every missed occurrence, not just one', () async {
      await insertSeries(series(RecurrenceInterval.monthly, DateTime(2026, 1, 15)));

      await transactions.bookDueFixedTransactions(alice.uid, now: DateTime(2026, 4, 20));

      final booked = await transactions.getAllTransactions(alice.uid);
      expect(booked.map((t) => t.date.month).toList()..sort(), [1, 2, 3, 4]);
      expect(await balanceOf(db, alice.uid, 'Girokonto'), 60);
      final ft = (await transactions.getAllFixedTransactions(alice.uid)).single;
      expect(ft.nextTime, DateTime(2026, 5, 15));
    });

    test('running twice (e.g. concurrently) never books twice', () async {
      await insertSeries(series(RecurrenceInterval.weekly, DateTime(2026, 3, 2)));
      final now = DateTime(2026, 3, 20);

      await Future.wait([
        transactions.bookDueFixedTransactions(alice.uid, now: now),
        transactions.bookDueFixedTransactions(alice.uid, now: now),
      ]);

      expect(await transactions.getAllTransactions(alice.uid), hasLength(3)); // 2., 9., 16. März
    });

    test('keeps month-end dates anchored to the start date', () async {
      await insertSeries(series(RecurrenceInterval.monthly, DateTime(2026, 1, 31)));

      await transactions.bookDueFixedTransactions(alice.uid, now: DateTime(2026, 4, 30));

      final days = (await transactions.getAllTransactions(alice.uid)).map((t) => t.date).toList()..sort();
      expect(days, [DateTime(2026, 1, 31), DateTime(2026, 2, 28), DateTime(2026, 3, 31), DateTime(2026, 4, 30)]);
    });

    test('ends the series after its end date', () async {
      await insertSeries(series(RecurrenceInterval.monthly, DateTime(2026, 1, 1), end: DateTime(2026, 2, 15)));

      await transactions.bookDueFixedTransactions(alice.uid, now: DateTime(2026, 6, 1));

      expect(await transactions.getAllTransactions(alice.uid), hasLength(2));
      expect(await transactions.getAllFixedTransactions(alice.uid), isEmpty);
    });

    test('editing a series first books what is already due (with the old amount)', () async {
      final now = DateTime.now();
      final yesterday = DateTime(now.year, now.month, now.day - 1);
      await insertSeries(series(RecurrenceInterval.monthly, yesterday)); // App seit gestern offen, noch nicht gebucht
      final ft = (await transactions.getAllFixedTransactions(alice.uid)).single;
      final next = RecurrenceInterval.monthly.occurrence(yesterday, 1);

      await transactions.updateFixedTransaction(FixedTransaction(
        id: ft.id,
        startTime: yesterday,
        endTime: DateTime(2300),
        nextTime: next,
        interval: RecurrenceInterval.monthly,
        amount: 20,
        category: 'Miete',
        description: '',
        account: 'Girokonto',
        transactionType: TransactionType.expense,
        userid: alice.uid,
      ));

      final booked = await transactions.getAllTransactions(alice.uid);
      expect(booked.map((t) => (t.date, t.amount)), [(yesterday, 10.0)]);
      final updated = (await transactions.getAllFixedTransactions(alice.uid)).single;
      expect((updated.amount, updated.nextTime), (20.0, next));
    });
  });

  group('renames', () {
    test('renaming an account updates transactions, fixed transactions and goals', () async {
      final accounts = AccountRepository(db: db);
      final goals = FinancialGoalRepository(db: db);
      await transactions.createTransaction(tx(alice, 5, TransactionType.expense));
      await transactions.createTransaction(tx(bob, 5, TransactionType.expense));
      await goals.createGoal(FinancialGoal(
        name: 'Urlaub',
        targetAmount: 1000,
        selectedAccountNames: 'Girokonto, Sparkonto',
        colorHex: '#000000',
        userid: alice.uid,
      ));

      final giro = (await accounts.getAllAccounts(alice.uid)).firstWhere((a) => a.accountName == 'Girokonto');
      await accounts.updateAccount(Account(
        id: giro.id,
        accountName: 'Hauptkonto',
        accountUserid: alice.uid,
        accountFontFamily: giro.accountFontFamily,
        accountIconName: giro.accountIconName,
        accountCodePoint: giro.accountCodePoint,
        accountAmount: giro.accountAmount,
      ));

      expect((await transactions.getAllTransactions(alice.uid)).single.account, 'Hauptkonto');
      expect((await transactions.getAllTransactions(bob.uid)).single.account, 'Girokonto');
      expect((await goals.getAllGoals(alice.uid)).single.accountNames, ['Hauptkonto', 'Sparkonto']);
    });

    test('renaming a category updates its transactions', () async {
      final categories = CategoryRepository(db: db);
      await categories.createCategory(Category(
        categoryName: 'Lebensmittel',
        categoryUserid: alice.uid,
        categoryFontFamily: 'MaterialIcons',
        categoryIconName: 'x',
        categoryCodePoint: 1,
        transactionType: TransactionType.expense,
      ));
      await transactions.createTransaction(tx(alice, 5, TransactionType.expense));
      final cat = (await categories.getAllCategories(alice.uid)).single;

      await categories.updateCategory(Category(
        id: cat.id,
        categoryName: 'Essen',
        categoryUserid: alice.uid,
        categoryFontFamily: cat.categoryFontFamily,
        categoryIconName: cat.categoryIconName,
        categoryCodePoint: cat.categoryCodePoint,
        transactionType: TransactionType.expense,
      ));

      expect((await transactions.getAllTransactions(alice.uid)).single.category, 'Essen');
    });
  });

  group('UserRepository', () {
    test('updateUser keeps the password hash', () async {
      final users = UserRepository(db: db);
      await users.updatePasswordHash(alice.uid, 'hash');

      await users.updateUser(UserModel(uid: alice.uid, email: 'alice@test.de', displayName: 'Alice'));

      final stored = await users.getUser(alice.uid);
      expect(stored.password, 'hash');
      expect(stored.displayName, 'Alice');
    });

    test('addExperience never goes below zero', () async {
      final users = UserRepository(db: db);
      expect((await users.addExperience(alice.uid, 15)).experiencePoints, 15);
      expect((await users.addExperience(alice.uid, -50)).experiencePoints, 0);
    });
  });

  group('names and safe deletes', () {
    Account account(UserModel u, String name) => Account(
          accountName: name,
          accountUserid: u.uid,
          accountFontFamily: 'MaterialIcons',
          accountIconName: 'wallet',
          accountCodePoint: 0,
          accountAmount: 0,
        );
    Category category(UserModel u, String name, TransactionType type) => Category(
          categoryName: name,
          categoryUserid: u.uid,
          categoryFontFamily: 'MaterialIcons',
          categoryIconName: 'category',
          categoryCodePoint: 0,
          transactionType: type,
        );

    test('a second account with the same name is rejected (create, rename, restore) – other users may reuse it', () async {
      final accounts = AccountRepository(db: db);
      expect(() => accounts.createAccount(account(alice, ' girokonto ')), throwsA(isA<UserFacingException>()));
      await accounts.createAccount(account(bob, 'Sparkonto')); // anderer Nutzer: erlaubt

      final spar = (await accounts.getAllAccounts(alice.uid)).firstWhere((a) => a.accountName == 'Sparkonto');
      await expectLater(
        accounts.updateAccount(Account(
          id: spar.id,
          accountName: 'Girokonto',
          accountUserid: alice.uid,
          accountFontFamily: 'MaterialIcons',
          accountIconName: 'wallet',
          accountCodePoint: 0,
          accountAmount: 0,
        )),
        throwsA(isA<UserFacingException>()),
      );

      // Löschen, gleichnamig neu anlegen, dann Rückgängig → abgelehnt statt doppelt zu buchen
      await accounts.deleteAccount(spar.id!);
      await accounts.createAccount(account(alice, 'Sparkonto'));
      await expectLater(accounts.restoreAccount(spar.id!), throwsA(isA<UserFacingException>()));
      expect((await accounts.getAllAccounts(alice.uid)).where((a) => a.accountName == 'Sparkonto'), hasLength(1));
    });

    test('an account with bookings cannot be deleted', () async {
      final accounts = AccountRepository(db: db);
      await transactions.createTransaction(tx(alice, 5, TransactionType.expense));
      final giro = (await accounts.getAllAccounts(alice.uid)).firstWhere((a) => a.accountName == 'Girokonto');
      await expectLater(accounts.deleteAccount(giro.id!), throwsA(isA<UserFacingException>()));
      expect(await accounts.getAllAccounts(alice.uid), hasLength(2));
    });

    test('categories may share a name only across income/expense', () async {
      final categories = CategoryRepository(db: db);
      await categories.createCategory(category(alice, 'Geschenke', TransactionType.expense));
      await categories.createCategory(category(alice, 'Geschenke', TransactionType.income));
      expect(() => categories.createCategory(category(alice, 'GESCHENKE', TransactionType.expense)), throwsA(isA<UserFacingException>()));
    });

    test('unknown stored values never break reading (legacy/sync data)', () async {
      expect(TransactionType.fromDb('income'), TransactionType.income);
      expect(TransactionType.fromDb('Ausgabe'), TransactionType.expense);
      expect(TransactionType.fromDb('???'), TransactionType.expense);
      expect(RecurrenceInterval.fromDbOrMonthly('alle zwei Tage'), RecurrenceInterval.monthly);

      final raw = await db.database;
      await raw.insert('transactions', {
        ...tx(alice, 7, TransactionType.expense).toMap()..remove('id'),
        'transactionType': 'expense',
      });
      expect((await transactions.getAllTransactions(alice.uid)).single.transactionType, TransactionType.expense);
    });
  });
}
