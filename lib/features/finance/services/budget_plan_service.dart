import 'dart:math' as math;

import 'package:frontend/features/finance/models/category.dart';
import 'package:frontend/features/finance/models/fixedtransaction.dart';
import 'package:frontend/features/finance/models/transaction.dart';
import 'package:frontend/features/finance/models/transaction_type.dart';

/// Eine Fixeinnahme bzw. -ausgabe im Monat.
class FixedLine {
  final FixedTransaction fixed;

  /// Monatlicher Gegenwert (z. B. Versicherung jährlich 120 € → 10 €).
  final double monthly;

  /// Termine in diesem Monat.
  final List<DateTime> dueThisMonth;
  const FixedLine(this.fixed, this.monthly, this.dueThisMonth);

  String get name => fixed.description.isNotEmpty ? fixed.description : fixed.category;

  /// Noch offener Termin in diesem Monat (nach heute), sonst `null` = schon gebucht bzw. nicht fällig.
  DateTime? nextDue(DateTime now) => dueThisMonth.where((d) => d.isAfter(now)).firstOrNull;
}

/// Budget einer Ausgabenkategorie im Monat.
class BudgetLine {
  final Category category;
  final double budget;

  /// Fixausgaben in dieser Kategorie (zählen aufs Budget an).
  final double fixed;
  final double spent;
  const BudgetLine(this.category, this.budget, this.fixed, this.spent);

  /// Geplant: das Budget – oder mehr, wenn schon die Fixkosten darüber liegen.
  double get planned => math.max(budget, fixed);

  /// Der Teil des Budgets, der über die Fixkosten hinausgeht (variable Ausgaben).
  double get variable => math.max(budget - fixed, 0);

  double get open => planned - spent;
  bool get over => spent > planned;
}

/// Monatsplanung: Fixeinnahmen, Fixausgaben und Budgets – und was davon frei bleibt.
class BudgetPlan {
  final DateTime month;
  final List<FixedLine> fixedIncome;
  final List<FixedLine> fixedExpenses;
  final List<BudgetLine> budgets;
  const BudgetPlan(this.month, this.fixedIncome, this.fixedExpenses, this.budgets);

  double get fixedIncomeTotal => fixedIncome.fold(0, (s, l) => s + l.monthly);
  double get fixedExpenseTotal => fixedExpenses.fold(0, (s, l) => s + l.monthly);

  /// Budgets ohne den Teil, der schon als Fixausgabe zählt (sonst doppelt).
  double get variableBudgetTotal => budgets.fold(0, (s, b) => s + b.variable);

  /// Fixeinnahmen − Fixausgaben − Budgets.
  double get available => fixedIncomeTotal - fixedExpenseTotal - variableBudgetTotal;
  bool get overcommitted => available < 0;

  /// Was in diesem Monat von den Budgets noch ausgegeben werden darf.
  double get openBudgets => budgets.fold(0, (s, b) => s + math.max(b.open, 0));

  bool get isEmpty => fixedIncome.isEmpty && fixedExpenses.isEmpty && budgets.isEmpty;
}

/// Berechnet die [BudgetPlan] eines Monats aus Kategorien, Fixtransaktionen und Buchungen.
class BudgetPlanService {
  const BudgetPlanService();

  BudgetPlan build({
    required DateTime month,
    required List<Category> categories,
    required List<FixedTransaction> fixed,
    required List<Transaction> transactions,
  }) {
    final start = DateTime(month.year, month.month);
    final end = DateTime(month.year, month.month + 1).subtract(const Duration(microseconds: 1));

    List<DateTime> due(FixedTransaction f) {
      final dates = <DateTime>[];
      for (var n = 0; n < 1000; n++) {
        final d = f.interval.occurrence(f.startTime, n);
        if (d.isAfter(end) || d.isAfter(f.endTime)) break;
        if (!d.isBefore(start)) dates.add(d);
      }
      return dates;
    }

    final active = fixed.where((f) => !f.isTransfer && !f.startTime.isAfter(end) && !f.endTime.isBefore(start));
    FixedLine line(FixedTransaction f) => FixedLine(f, f.interval.monthlyEquivalent(f.amount), due(f));
    final income = [for (final f in active.where((f) => f.transactionType.isIncome)) line(f)]..sort((a, b) => b.monthly.compareTo(a.monthly));
    final expenses = [for (final f in active.where((f) => !f.transactionType.isIncome)) line(f)]..sort((a, b) => b.monthly.compareTo(a.monthly));

    final spent = <String, double>{};
    for (final t in transactions) {
      if (t.isTransfer || t.transactionType != TransactionType.expense) continue;
      if (t.date.isBefore(start) || t.date.isAfter(end)) continue;
      spent[t.category] = (spent[t.category] ?? 0) + t.amount;
    }
    final fixedByCategory = <String, double>{};
    for (final l in expenses) {
      fixedByCategory[l.fixed.category] = (fixedByCategory[l.fixed.category] ?? 0) + l.monthly;
    }
    final budgets = [
      for (final c in categories)
        if (c.transactionType == TransactionType.expense && c.monthlyBudget > 0)
          BudgetLine(c, c.monthlyBudget, fixedByCategory[c.categoryName] ?? 0, spent[c.categoryName] ?? 0),
    ]..sort((a, b) => b.planned.compareTo(a.planned));

    return BudgetPlan(start, income, expenses, budgets);
  }
}
