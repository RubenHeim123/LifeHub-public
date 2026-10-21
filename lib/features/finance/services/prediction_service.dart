import 'package:frontend/core/models/dates.dart';
import 'package:frontend/features/finance/models/fixedtransaction.dart';
import 'package:frontend/features/finance/repositories/account_repository.dart';
import 'package:frontend/features/finance/repositories/transaction_repository.dart';

class ForecastBreakdown {
  final double currentBalance;
  final double remainingFixedIncome;
  final double remainingFixedExpenses;
  final double estimatedVariableIncome;
  final double estimatedVariableExpenses;
  final double totalForecast;
  final DateTime targetDate;

  ForecastBreakdown({
    required this.currentBalance,
    required this.remainingFixedIncome,
    required this.remainingFixedExpenses,
    required this.estimatedVariableIncome,
    required this.estimatedVariableExpenses,
    required this.totalForecast,
    required this.targetDate,
  });
}

/// Termine von [ft] nach [today] bis einschließlich [monthEnd] (und nicht nach dem Enddatum).
int _remainingOccurrences(FixedTransaction ft, {required DateTime today, required DateTime monthEnd}) {
  final first = dateOnly(ft.nextTime);
  final end = dateOnly(ft.endTime).isBefore(monthEnd) ? dateOnly(ft.endTime) : monthEnd;
  if (first.isAfter(end)) return 0;
  // nextTime selbst ist der nächste Termin, danach folgen die Termine der Serie ab dem Startdatum
  var count = first.isAfter(today) ? 1 : 0;
  for (var n = 0; n < 1000; n++) {
    final day = dateOnly(ft.interval.occurrence(ft.startTime, n));
    if (day.isAfter(end)) break;
    if (day.isAfter(first) && day.isAfter(today)) count++;
  }
  return count;
}

class PredictionService {
  PredictionService({required TransactionRepository transactions, required AccountRepository accounts})
      : _transactions = transactions,
        _accounts = accounts;

  final TransactionRepository _transactions;
  final AccountRepository _accounts;

  /// Wert für [calculateEndOfMonthForecast], wenn alle Konten gemeint sind.
  static const String allAccounts = 'All Accounts';

  Future<ForecastBreakdown> calculateEndOfMonthForecast(int userId, {String? accountName, DateTime? now}) async {
    now ??= DateTime.now();
    final lastDayOfMonth = DateTime(now.year, now.month + 1, 0);
    final daysRemaining = lastDayOfMonth.day - now.day;

    // 1. Fetch data
    final transactions = await _transactions.getAllTransactions(userId);
    final fixedTransactions = await _transactions.getAllFixedTransactions(userId);
    final accounts = await _accounts.getAllAccounts(userId);
    final allAccountsSelected = accountName == null || accountName == allAccounts;

    // Calculate actual current balance
    double actualBalance = 0;
    for (var acc in accounts) {
      if (allAccountsSelected || acc.accountName == accountName) {
        actualBalance += acc.accountAmount;
      }
    }

    // 2. Transaction-based Historical Variable Calculation
    final DateTime threeSixtyFiveDaysAgo = now.subtract(const Duration(days: 365));
    
    double totalVariableIncomeHistory = 0;
    double totalVariableExpenseHistory = 0;
    
    for (var t in transactions) {
      if (!allAccountsSelected && t.account != accountName) continue;
      if (t.isTransfer) continue;

      // Variable Average Logic (Last 365 days)
      if (t.date.isAfter(threeSixtyFiveDaysAgo) && t.date.isBefore(now.add(const Duration(seconds: 1)))) {
        bool isFixed = fixedTransactions.any((ft) => 
          ft.transactionType == t.transactionType && 
          ft.category == t.category && 
          ft.account == t.account &&
          (ft.amount - t.amount).abs() < 0.01
        );

        if (!isFixed) {
          if (t.transactionType.isIncome) {
            totalVariableIncomeHistory += t.amount;
          } else {
            totalVariableExpenseHistory += t.amount;
          }
        }
      }
    }

    // 4. Remaining Fixed Transactions (Future in this month)
    double remainingFixedExpenses = 0;
    double remainingFixedIncome = 0;

    for (var ft in fixedTransactions) {
      if (!allAccountsSelected && ft.account != accountName) continue;
      if (ft.isTransfer) continue;

      // Jeder noch kommende Termin bis Monatsende zählt – wöchentlich also 4–5×, nicht nur der nächste
      final due = _remainingOccurrences(ft, today: dateOnly(now), monthEnd: lastDayOfMonth) * ft.amount;
      if (ft.transactionType.isIncome) {
        remainingFixedIncome += due;
      } else {
        remainingFixedExpenses += due;
      }
    }

    // 5. Calculate Variable Averages (Based on 12 months)
    double avgDailyVariableIncome = totalVariableIncomeHistory / 365;
    double avgDailyVariableExpense = totalVariableExpenseHistory / 365;

    double estimatedVariableIncome = avgDailyVariableIncome * daysRemaining;
    double estimatedVariableExpense = avgDailyVariableExpense * daysRemaining;

    // 6. Total Forecast
    double totalForecast = actualBalance + remainingFixedIncome - remainingFixedExpenses + estimatedVariableIncome - estimatedVariableExpense;

    return ForecastBreakdown(
      currentBalance: actualBalance,
      remainingFixedIncome: remainingFixedIncome,
      remainingFixedExpenses: remainingFixedExpenses,
      estimatedVariableIncome: estimatedVariableIncome,
      estimatedVariableExpenses: estimatedVariableExpense,
      totalForecast: totalForecast,
      targetDate: lastDayOfMonth,
    );
  }
}
