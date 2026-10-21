import 'package:flutter_test/flutter_test.dart';

import 'package:frontend/features/finance/models/category.dart';
import 'package:frontend/features/finance/models/fixedtransaction.dart';
import 'package:frontend/features/finance/models/recurrence_interval.dart';
import 'package:frontend/features/finance/models/transaction.dart';
import 'package:frontend/features/finance/models/transaction_type.dart';
import 'package:frontend/features/finance/services/budget_plan_service.dart';

void main() {
  final month = DateTime(2026, 10);

  FixedTransaction fixed(String name, double amount, TransactionType type,
          {String? category, RecurrenceInterval interval = RecurrenceInterval.monthly, DateTime? start, DateTime? end}) =>
      FixedTransaction(
        startTime: start ?? DateTime(2026, 1, 15),
        endTime: end ?? DateTime(2030),
        nextTime: DateTime(2026, 10, 15),
        interval: interval,
        amount: amount,
        category: category ?? name,
        description: name,
        account: 'Giro',
        transactionType: type,
        userid: 1,
      );

  Category cat(String name, double budget, {TransactionType type = TransactionType.expense}) => Category(
        categoryName: name,
        categoryUserid: 1,
        categoryFontFamily: 'MaterialIcons',
        categoryIconName: 'category',
        categoryCodePoint: 0,
        transactionType: type,
        monthlyBudget: budget,
      );

  Transaction spend(String category, double amount, DateTime date) => Transaction(
        date: date,
        amount: amount,
        category: category,
        description: '',
        account: 'Giro',
        transactionType: TransactionType.expense,
        userid: 1,
      );

  test('fixed income minus fixed expenses minus budgets; fixed costs in a budget category count once', () {
    final plan = const BudgetPlanService().build(
      month: month,
      categories: [cat('Lebensmittel', 400), cat('Wohnen', 1000), cat('Freizeit', 100), cat('Gehalt', 3000, type: TransactionType.income)],
      fixed: [
        fixed('Gehalt', 3000, TransactionType.income),
        fixed('Miete', 900, TransactionType.expense, category: 'Wohnen'),
        fixed('Versicherung', 120, TransactionType.expense, interval: RecurrenceInterval.yearly), // 10 €/Monat
        fixed('Altvertrag', 50, TransactionType.expense, end: DateTime(2026, 9, 30)), // vorbei
      ],
      transactions: [
        spend('Lebensmittel', 150, DateTime(2026, 10, 3)),
        spend('Lebensmittel', 99, DateTime(2026, 9, 28)), // anderer Monat
        spend('Freizeit', 130, DateTime(2026, 10, 9)),
      ],
    );
    expect(plan.fixedIncomeTotal, 3000);
    expect(plan.fixedExpenses.map((l) => l.name), ['Miete', 'Versicherung']);
    expect(plan.fixedExpenseTotal, 910);
    // Wohnen: Budget 1000, davon 900 fix → nur 100 zusätzlich
    final wohnen = plan.budgets.firstWhere((b) => b.category.categoryName == 'Wohnen');
    expect((wohnen.planned, wohnen.variable), (1000.0, 100.0));
    expect(plan.variableBudgetTotal, 400 + 100 + 100);
    expect(plan.available, 3000 - 910 - 600);
    expect(plan.overcommitted, isFalse);

    final food = plan.budgets.firstWhere((b) => b.category.categoryName == 'Lebensmittel');
    expect((food.spent, food.open, food.over), (150.0, 250.0, false));
    final fun = plan.budgets.firstWhere((b) => b.category.categoryName == 'Freizeit');
    expect((fun.open, fun.over), (-30.0, true));
    expect(plan.openBudgets, 250 + 1000); // Freizeit ist ausgeschöpft
  });

  test('warns when budgets and fixed costs exceed the fixed income', () {
    final plan = const BudgetPlanService().build(
      month: month,
      categories: [cat('Lebensmittel', 500)],
      fixed: [fixed('Gehalt', 1200, TransactionType.income), fixed('Miete', 900, TransactionType.expense)],
      transactions: const [],
    );
    expect(plan.available, -200);
    expect(plan.overcommitted, isTrue);
  });

  test('due dates in the month; weekly fixed costs are spread to a monthly value', () {
    final plan = const BudgetPlanService().build(
      month: month,
      categories: const [],
      fixed: [fixed('Putzhilfe', 30, TransactionType.expense, interval: RecurrenceInterval.weekly, start: DateTime(2026, 10, 2))],
      transactions: const [],
    );
    final line = plan.fixedExpenses.single;
    expect(line.dueThisMonth.map((d) => d.day), [2, 9, 16, 23, 30]);
    expect(line.monthly, closeTo(30 * 365 / 12 / 7, 0.01));
    expect(line.nextDue(DateTime(2026, 10, 10)), DateTime(2026, 10, 16));
  });

  test('only fixed income: everything is available, nothing overcommitted', () {
    final plan = const BudgetPlanService().build(
      month: month,
      categories: [cat('Gehalt', 0, type: TransactionType.income)],
      fixed: [fixed('Gehalt', 2500, TransactionType.income), fixed('Kindergeld', 250, TransactionType.income)],
      transactions: const [],
    );
    expect(plan.isEmpty, isFalse);
    expect(plan.fixedExpenses, isEmpty);
    expect(plan.budgets, isEmpty);
    expect(plan.available, 2750);
    expect(plan.overcommitted, isFalse);
    expect(plan.openBudgets, 0);
  });

  test('nothing set up yet: the plan is empty and adds up to 0', () {
    final plan = const BudgetPlanService().build(month: month, categories: const [], fixed: const [], transactions: const []);
    expect(plan.isEmpty, isTrue);
    expect((plan.fixedIncomeTotal, plan.fixedExpenseTotal, plan.variableBudgetTotal, plan.available), (0.0, 0.0, 0.0, 0.0));
    expect(plan.overcommitted, isFalse);
  });

  test('a budget with no fixed income shows how much it is overcommitted', () {
    final plan = const BudgetPlanService().build(
      month: month,
      categories: [cat('Lebensmittel', 300)],
      fixed: const [],
      transactions: [spend('Lebensmittel', 320, DateTime(2026, 10, 2))],
    );
    expect(plan.available, -300);
    expect(plan.overcommitted, isTrue);
    expect(plan.openBudgets, 0); // überzogen zählt nicht als „noch offen“
  });
}
