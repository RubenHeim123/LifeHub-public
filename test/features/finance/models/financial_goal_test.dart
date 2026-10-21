import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/features/finance/models/financial_goal.dart';
import 'package:frontend/features/finance/models/account.dart';

void main() {
  group('Financial Goal Logic Tests', () {
    test('Calculate current amount from linked accounts', () {
      final goal = FinancialGoal(
        name: 'Test Goal',
        targetAmount: 1000,
        selectedAccountNames: 'Account A, Account C',
        colorHex: '#000000',
        userid: 1,
      );

      final accounts = [
        Account(id: 1, accountName: 'Account A', accountUserid: 1, accountIconName: 'wallet', accountCodePoint: 0, accountFontFamily: '', accountAmount: 500),
        Account(id: 2, accountName: 'Account B', accountUserid: 1, accountIconName: 'wallet', accountCodePoint: 0, accountFontFamily: '', accountAmount: 300),
        Account(id: 3, accountName: 'Account C', accountUserid: 1, accountIconName: 'wallet', accountCodePoint: 0, accountFontFamily: '', accountAmount: 200),
      ];

      final linkedNames = goal.accountNames;
      double sum = 0;
      for (var acc in accounts) {
        if (linkedNames.contains(acc.accountName)) {
          sum += acc.accountAmount;
        }
      }

      expect(sum, 700);
      expect(sum / goal.targetAmount, 0.7);
    });

    test('Collision detection logic', () {
      final existingGoals = [
        FinancialGoal(id: 1, name: 'Goal 1', targetAmount: 1000, selectedAccountNames: 'Sparkonto', colorHex: '#000000', userid: 1),
      ];

      String? getCollision(String accountName, List<FinancialGoal> goals) {
        for (var goal in goals) {
          if (goal.accountNames.contains(accountName)) {
            return goal.name;
          }
        }
        return null;
      }

      expect(getCollision('Sparkonto', existingGoals), 'Goal 1');
      expect(getCollision('Girokonto', existingGoals), null);
    });
  });
}
