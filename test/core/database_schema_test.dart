import 'package:flutter_test/flutter_test.dart';

import 'package:frontend/core/database/database.dart';
import 'package:frontend/features/auth/models/user.dart';
import 'package:frontend/features/calendar/models/appointment.dart';
import 'package:frontend/features/finance/models/account.dart';
import 'package:frontend/features/finance/models/category.dart';
import 'package:frontend/features/finance/models/financial_goal.dart';
import 'package:frontend/features/finance/models/fixedtransaction.dart';
import 'package:frontend/features/finance/models/recurrence_interval.dart';
import 'package:frontend/features/finance/models/transaction.dart' as tr;
import 'package:frontend/features/finance/models/transaction_type.dart';
import 'package:frontend/features/fitness/models/nutrition.dart';
import 'package:frontend/features/fitness/models/workout.dart';
import 'package:frontend/features/lists/models/lists.dart';
import 'package:frontend/features/meals/models/meal_plan.dart';
import 'package:frontend/features/style/models/style.dart';
import 'package:frontend/features/habits/models/habit.dart';
import 'package:frontend/features/inventory/models/inventory_item.dart';
import 'package:frontend/features/todos/models/todo.dart';
import 'package:frontend/features/vision/models/vision.dart';

import '../helpers/test_app.dart';

/// Stellt sicher, dass jede Spalte, die ein Model schreibt, im Schema existiert.
/// Fängt z. B. versehentlich umbenannte Spalten ab.
void main() {
  late DatabaseService db;

  setUp(() => db = createTestDatabase());
  tearDown(() => db.close());

  Future<Set<String>> columnsOf(String table) async {
    final rows = await (await db.database).rawQuery('PRAGMA table_info($table)');
    return rows.map((r) => r['name'] as String).toSet();
  }

  final now = DateTime(2026, 1, 1);
  final models = <String, Map<String, dynamic>>{
    'users': UserModel(uid: 1, email: 'a@b.de').toMap(),
    'accounts': Account(
      accountName: 'A',
      accountUserid: 1,
      accountFontFamily: 'f',
      accountIconName: 'i',
      accountCodePoint: 1,
      accountAmount: 0,
    ).toMap(),
    'categories': Category(
      categoryName: 'C',
      categoryUserid: 1,
      categoryFontFamily: 'f',
      categoryCodePoint: 1,
      categoryIconName: 'i',
      transactionType: TransactionType.expense,
    ).toMap(),
    'transactions': tr.Transaction(
      date: now,
      amount: 1,
      category: 'C',
      description: '',
      account: 'A',
      transactionType: TransactionType.expense,
      userid: 1,
    ).toMap(),
    'fixed_transactions': FixedTransaction(
      startTime: now,
      endTime: now,
      nextTime: now,
      interval: RecurrenceInterval.monthly,
      amount: 1,
      category: 'C',
      description: '',
      account: 'A',
      transactionType: TransactionType.expense,
      userid: 1,
    ).toMap(),
    'financial_goals': FinancialGoal(name: 'G', targetAmount: 1, selectedAccountNames: 'A', colorHex: '#000', userid: 1).toMap(),
    'todos': Todo(title: 'T', userid: 1).toMap(),
    'appointments': Appointment(title: 'T', date: now, userid: 1).toMap(),
    'habits': Habit(name: 'H', userid: 1).toMap(),
    'vision_areas': const VisionArea(userid: 1, title: 'A').toMap(),
    'vision_goals': const VisionGoal(areaId: 1, userid: 1, title: 'G').toMap(),
    'goal_steps': const GoalStep(goalId: 1, userid: 1, title: 'S').toMap(),
    'foods': const Food(userid: 1, name: 'F', barcode: '1', servingGrams: 50, packSizes: [400]).toMap(),
    'meal_entries': MealEntry(userid: 1, date: now, meal: Meal.lunch, foodId: 1, name: 'F', grams: 1, macros: Macros.zero).toMap(),
    'exercises': const Exercise(userid: 1, name: 'E', notes: 'N', catalogKey: 'liegestuetz').toMap(),
    'workouts': const Workout(userid: 1, name: 'W', notes: 'N', repeatWeekdays: [1], method: TrainingMethod.zirkel).toMap(),
    'workout_exercises': const WorkoutExercise(exercise: Exercise(id: 1, userid: 1, name: 'E'), reps: 1, durationSec: 1, distanceKm: 1)
        .toMap(1, 1, 0),
    'outfits': Outfit(userid: 1, name: 'O', imagePath: 'x.jpg', lastWornAt: now, wearCount: 1).toMap(),
    'wishlist_items': const WishlistItem(userid: 1, name: 'W', price: 1, url: 'u', imagePath: 'x.jpg', boughtItemId: 1).toMap(),
    'shopping_items':
        ShoppingItem(userid: 1, name: 'S', quantity: '2', done: true, doneAt: now, amount: 1, unit: 'g', foodId: 1, boughtAmount: 1, barcode: '1')
            .toMap(),
    'shopping_sources': const ShoppingSource(itemId: 1, userid: 1, amount: 1, unit: 'g', label: 'L', recipeKey: 'k', recipeId: 1, batchId: 1)
        .toMap(),
    'gift_lists': GiftList(userid: 1, person: 'P', occasion: 'O', date: now, notes: 'N').toMap(),
    'recipes': const Recipe(
      id: 1,
      userid: 1,
      name: 'R',
      summary: 'S',
      meals: {Meal.lunch},
      ingredients: [Ingredient('Linsen', 1, 'g')],
      steps: ['Kochen'],
    ).toMap(),
    'meal_plan': PlannedMeal(userid: 1, date: now, meal: Meal.lunch, time: 600, recipeKey: 'k', recipeId: 1, name: 'P', note: 'n', mealEntryId: 1, batchId: 1)
        .toMap(),
    'meal_batches': MealBatch(userid: 1, recipeKey: 'k', recipeId: 1, name: 'B', factor: 2, cookDate: now, cookedAt: now).toMap(),
    'cook_logs': CookLog(userid: 1, batchId: 1, recipeKey: 'k', recipeId: 1, name: 'C', date: now, usages: const [
      CookUsage(ingredient: 'Paprika', planned: '1', itemId: 1, itemName: 'Paprika', amount: 2, unit: 'g'),
    ]).toMap(),
    'gift_items': const GiftItem(listId: 1, userid: 1, name: 'G', price: 1, url: 'u', notes: 'n').toMap(),
    'inventory_items': InventoryItem(
      userid: 1,
      kind: InventoryKind.clothing,
      name: 'I',
      condition: ItemCondition.good,
      purchaseDate: now,
      expiryDate: now,
      openedDate: now,
      lastUsedAt: now,
      fromShopping: true,
      receiptTxId: 1,
    ).toMap(),
  };

  for (final entry in models.entries) {
    test('table ${entry.key} has every column its model writes', () async {
      expect(await columnsOf(entry.key), containsAll(entry.value.keys));
    });
  }

  test('all synced tables carry delta-sync columns', () async {
    for (final table in models.keys.where((t) => t != 'users')) {
      expect(await columnsOf(table), containsAll(['last_changed', 'is_deleted', 'server_id']), reason: table);
    }
  });
}
