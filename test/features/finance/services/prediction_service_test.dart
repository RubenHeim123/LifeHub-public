import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:frontend/core/database/database.dart';
import 'package:frontend/features/finance/models/account.dart';
import 'package:frontend/features/finance/models/fixedtransaction.dart';
import 'package:frontend/features/finance/models/recurrence_interval.dart';
import 'package:frontend/features/finance/models/transaction.dart' as tr;
import 'package:frontend/features/finance/models/transaction_type.dart';
import 'package:frontend/features/finance/repositories/account_repository.dart';
import 'package:frontend/features/finance/repositories/transaction_repository.dart';
import 'package:frontend/features/finance/services/prediction_service.dart';

// Die Datenbank wird erst beim ersten Zugriff geöffnet – die Fakes greifen nie zu.
final _unusedDb = DatabaseService(path: 'unused.db');

class _FakeTransactions extends TransactionRepository {
  _FakeTransactions() : super(db: _unusedDb);
  List<tr.Transaction> transactions = [];
  List<FixedTransaction> fixed = [];

  @override
  Future<List<tr.Transaction>> getAllTransactions(int uid) async => transactions;

  @override
  Future<List<FixedTransaction>> getAllFixedTransactions(int uid) async => fixed;
}

class _FakeAccounts extends AccountRepository {
  _FakeAccounts() : super(db: _unusedDb);
  List<Account> accounts = [];

  @override
  Future<List<Account>> getAllAccounts(int uid) async => accounts;
}

Account _account(String name, double amount) => Account(
      accountName: name,
      accountUserid: 1,
      accountFontFamily: 'MaterialIcons',
      accountIconName: 'wallet',
      accountCodePoint: Icons.wallet.codePoint,
      accountAmount: amount,
    );

tr.Transaction _tx(DateTime date, double amount, String category, TransactionType type) => tr.Transaction(
      date: date,
      amount: amount,
      category: category,
      description: '',
      account: 'Girokonto',
      transactionType: type,
      userid: 1,
    );

void main() {
  late _FakeTransactions transactions;
  late _FakeAccounts accounts;
  late PredictionService service;

  setUp(() {
    transactions = _FakeTransactions();
    accounts = _FakeAccounts();
    service = PredictionService(transactions: transactions, accounts: accounts);
  });

  test('forecast adds remaining fixed items and averages variable ones', () async {
    final now = DateTime.now();
    final lastDayOfMonth = DateTime(now.year, now.month + 1, 0);
    final daysRemaining = lastDayOfMonth.day - now.day;
    final firstDayOfMonth = DateTime(now.year, now.month, 1);

    FixedTransaction fixed(double amount, String category, TransactionType type, int inDays) => FixedTransaction(
          amount: amount,
          category: category,
          description: '',
          account: 'Girokonto',
          transactionType: type,
          nextTime: now.add(Duration(days: inDays)),
          userid: 1,
          startTime: now.subtract(const Duration(days: 30)),
          endTime: now.add(const Duration(days: 365)),
          interval: RecurrenceInterval.monthly,
        );

    final fixedIncome = fixed(2000, 'Gehalt', TransactionType.income, 5);
    final fixedExpense = fixed(1000, 'Miete', TransactionType.expense, 2);
    transactions.fixed = [fixedIncome, fixedExpense];
    transactions.transactions = [
      _tx(firstDayOfMonth.add(const Duration(hours: 1)), 2000, 'Gehalt', TransactionType.income),
      _tx(now.subtract(const Duration(hours: 2)), 100, 'Nebenjob', TransactionType.income),
      _tx(firstDayOfMonth.add(const Duration(hours: 2)), 1000, 'Miete', TransactionType.expense),
      _tx(now.subtract(const Duration(hours: 1)), 50, 'Lebensmittel', TransactionType.expense),
    ];
    accounts.accounts = [_account('Girokonto', 1050)];

    final result = await service.calculateEndOfMonthForecast(1);

    // Fixe Termine zählen nur, wenn sie noch in diesen Monat fallen (Monatsende-sicher).
    bool dueThisMonth(FixedTransaction f) => !f.nextTime.isAfter(lastDayOfMonth.add(const Duration(seconds: 1)));
    final remainingIncome = dueThisMonth(fixedIncome) ? 2000.0 : 0.0;
    final remainingExpense = dueThisMonth(fixedExpense) ? 1000.0 : 0.0;
    expect(result.currentBalance, 1050);
    expect(result.remainingFixedIncome, remainingIncome);
    expect(result.remainingFixedExpenses, remainingExpense);
    // Nur die nicht-fixen Buchungen zählen als variabel (Durchschnitt über 365 Tage).
    expect(result.estimatedVariableIncome, closeTo(100 / 365 * daysRemaining, 0.01));
    expect(result.estimatedVariableExpenses, closeTo(50 / 365 * daysRemaining, 0.01));
    expect(
      result.totalForecast,
      closeTo(1050 + remainingIncome - remainingExpense + (100 - 50) / 365 * daysRemaining, 0.01),
    );
  });

  test('transfers are ignored for the variable averages', () async {
    final now = DateTime.now();
    transactions.transactions = [
      _tx(now.subtract(const Duration(days: 1)), 200, 'Gehalt', TransactionType.income),
      _tx(now.subtract(const Duration(days: 3)), 1000, kTransferCategory, TransactionType.expense),
    ];
    accounts.accounts = [_account('Girokonto', 150)];

    final result = await service.calculateEndOfMonthForecast(1);

    expect(result.currentBalance, 150);
    expect(result.estimatedVariableExpenses, 0);
  });

  test('filters by account', () async {
    accounts.accounts = [_account('Girokonto', 100), _account('Sparkonto', 900)];

    expect((await service.calculateEndOfMonthForecast(1, accountName: 'Sparkonto')).currentBalance, 900);
    expect((await service.calculateEndOfMonthForecast(1, accountName: PredictionService.allAccounts)).currentBalance, 1000);
  });

  test('every remaining occurrence until month end counts (weekly 3×, daily until its end date)', () async {
    final now = DateTime(2026, 10, 10, 9);
    FixedTransaction fixed(double amount, RecurrenceInterval interval, DateTime next, {DateTime? end}) => FixedTransaction(
          amount: amount,
          category: 'Fix',
          description: '',
          account: 'Girokonto',
          transactionType: TransactionType.expense,
          nextTime: next,
          userid: 1,
          startTime: DateTime(2026, 10, 5),
          endTime: end ?? DateTime(2300),
          interval: interval,
        );
    transactions.fixed = [
      fixed(10, RecurrenceInterval.weekly, DateTime(2026, 10, 12)), // 12., 19., 26.
      fixed(1, RecurrenceInterval.daily, DateTime(2026, 10, 11), end: DateTime(2026, 10, 15)), // 11.–15.
      fixed(500, RecurrenceInterval.monthly, DateTime(2026, 11, 5)), // erst im November
    ];
    accounts.accounts = [_account('Girokonto', 0)];

    final result = await service.calculateEndOfMonthForecast(1, now: now);
    expect(result.remainingFixedExpenses, 30 + 5);
  });
}
