import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:frontend/core/database/database.dart';
import 'package:frontend/features/fitness/catalog/standard_foods.dart';
import 'package:frontend/features/auth/models/user.dart';
import 'package:frontend/features/fitness/models/nutrition.dart';
import 'package:frontend/features/fitness/repositories/nutrition_repository.dart';
import 'package:frontend/features/fitness/services/barcode_scanner.dart';
import 'package:frontend/features/fitness/services/open_food_facts_service.dart';
import 'package:frontend/features/inventory/models/inventory_item.dart';
import 'package:frontend/features/inventory/repositories/inventory_repository.dart';

import '../../helpers/test_app.dart';

void main() {
  late DatabaseService db;
  late NutritionRepository repo;
  late UserModel user;
  final day = DateTime(2026, 9, 27);

  setUp(() async {
    db = createTestDatabase();
    repo = NutritionRepository(db: db);
    user = await createTestUser(db);
  });
  tearDown(() => db.close());

  Food oats(int uid) => Food(
        userid: uid,
        name: 'Haferflocken',
        per100: const Macros(kcal: 370, protein: 13.5, carbs: 58.7, fat: 7),
        servingGrams: 50,
      );

  test('entries scale nutrients by grams and add up per meal and day', () async {
    final food = await repo.saveFood(oats(user.uid));
    await repo.addEntry(uid: user.uid, food: food, grams: 80, meal: Meal.breakfast, date: day);
    await repo.addEntry(uid: user.uid, food: food, grams: 50, meal: Meal.snack, date: day);
    await repo.addEntry(uid: user.uid, food: food, grams: 100, meal: Meal.lunch, date: day.add(const Duration(days: 1)));

    final today = await repo.getDay(user.uid, day);
    expect(today.entries, hasLength(2));
    expect(today.totalFor(Meal.breakfast).kcal, closeTo(296, 0.01));
    expect(today.total.kcal, closeTo(481, 0.01));
    expect(today.total.protein, closeTo(17.55, 0.01));
  });

  test('entries keep their values when the food changes later', () async {
    final food = await repo.saveFood(oats(user.uid));
    await repo.addEntry(uid: user.uid, food: food, grams: 100, meal: Meal.breakfast, date: day);
    await repo.saveFood(Food(id: food.id, userid: user.uid, name: 'Hafer (neu)', per100: const Macros(kcal: 999)));

    final entry = (await repo.getDay(user.uid, day)).entries.single;
    expect(entry.name, 'Haferflocken');
    expect(entry.macros.kcal, 370);
  });

  test('goals default and can be changed', () async {
    expect((await repo.getGoals(user.uid)).target.kcal, NutritionGoals.defaults.target.kcal);
    await repo.setGoals(user.uid, const Macros(kcal: 2600, protein: 170, carbs: 300, fat: 80));
    await repo.setGoals(user.uid, const Macros(kcal: 2500, protein: 160, carbs: 290, fat: 75));
    expect((await repo.getGoals(user.uid)).target.protein, 160);
  });

  test('search finds by name and brand, recently used first', () async {
    final a = await repo.saveFood(Food(userid: user.uid, name: 'Apfel'));
    await repo.saveFood(Food(userid: user.uid, name: 'Skyr', brand: 'Arla'));
    final z = await repo.saveFood(Food(userid: user.uid, name: 'Zucchini'));
    await repo.addEntry(uid: user.uid, food: z, grams: 100, meal: Meal.dinner, date: day);

    expect((await repo.searchFoods(user.uid, search: 'arla')).single.name, 'Skyr');
    expect((await repo.searchFoods(user.uid)).map((f) => f.name), ['Zucchini', 'Apfel', 'Skyr']);
    expect(a.id, isNotNull);
  });

  test('standard products are created once, keep deletions and can be linked to barcodes', () async {
    await Future.wait([repo.ensureStandardFoods(user.uid), repo.ensureStandardFoods(user.uid)]);
    final all = await repo.searchFoods(user.uid);
    expect(all.length, standardFoods.length);
    expect(all.every((f) => f.brand == standardFoodBrand), isTrue);
    expect(standardFoods.map((f) => f.name).toSet(), hasLength(standardFoods.length));

    final oats = (await repo.searchFoods(user.uid, search: 'haferflocken')).single;
    await repo.deleteFood(oats.id!);
    await repo.ensureStandardFoods(user.uid);
    expect(await repo.searchFoods(user.uid, search: 'haferflocken'), isEmpty);

    final tofu = (await repo.searchFoods(user.uid, search: 'tofu natur')).single;
    final linked = await repo.linkBarcode(user.uid, '4001', tofu);
    expect((await repo.findByBarcode(user.uid, '4001'))!.id, linked.id);
    expect(linked.per100.protein, tofu.per100.protein);
    expect(linked.brand, isNull);
  });

  test('eating from the pantry books the entry and reduces the stock', () async {
    final inventory = InventoryRepository(db: db);
    final food = await repo.saveFood(oats(user.uid));
    final gramsId = await inventory.createItem(
        InventoryItem(userid: user.uid, kind: InventoryKind.food, name: 'Hafer', quantity: 500, unit: 'g', foodId: food.id));
    final pieceId = await inventory.createItem(
        InventoryItem(userid: user.uid, kind: InventoryKind.food, name: 'Riegel', quantity: 3, unit: 'Stück', foodId: food.id));

    await repo.eatFromPantry(
        uid: user.uid, item: (await inventory.getItem(gramsId))!, food: food, grams: 80, meal: Meal.breakfast, date: day);
    await repo.eatFromPantry(
        uid: user.uid, item: (await inventory.getItem(pieceId))!, food: food, grams: 40, meal: Meal.snack, date: day);

    expect((await inventory.getItem(gramsId))!.quantity, 420);
    expect((await inventory.getItem(pieceId))!.quantity, 2);
    expect((await repo.getDay(user.uid, day)).entries, hasLength(2));
  });

  group('Open Food Facts', () {
    const product = {
      'product_name': 'Skyr Natur',
      'brands': 'Arla, Arla Foods',
      'serving_quantity': 150,
      'product_quantity': 450,
      'nutriments': {'energy-kcal_100g': 63, 'proteins_100g': 11, 'carbohydrates_100g': 4, 'fat_100g': 0.2},
    };

    test('parses a product', () async {
      final food = (await fakeOpenFoodFacts({'4001234567890': product}).lookup('4001234567890', userid: 1))!;
      expect(food.name, 'Skyr Natur');
      expect(food.brand, 'Arla');
      expect(food.per100.protein, 11);
      expect(food.servingGrams, 150);
      expect(food.packSizes, [450]); // Packungsgröße fürs Einkaufen
      expect(food.barcode, '4001234567890');
    });

    test('unknown product returns null, network errors throw', () async {
      expect(await fakeOpenFoodFacts().lookup('111', userid: 1), isNull);
      final broken = OpenFoodFactsService(client: MockClient((_) async => throw http.ClientException('offline')));
      expect(() => broken.lookup('111', userid: 1), throwsA(isA<OpenFoodFactsException>()));
    });

    test('lookup service prefers own foods and saves remote hits', () async {
      var calls = 0;
      final off = OpenFoodFactsService(
        client: MockClient((request) async {
          calls++;
          return http.Response('{"status":1,"product":{"product_name":"Skyr Natur","nutriments":{"energy-kcal_100g":63}}}', 200);
        }),
      );
      final lookup = FoodLookupService(nutrition: repo, openFoodFacts: off);

      final first = (await lookup.byBarcode(user.uid, '4001234567890'))!;
      final second = (await lookup.byBarcode(user.uid, '4001234567890'))!;

      expect(first.id, isNotNull);
      expect(second.id, first.id);
      expect(calls, 1, reason: 'der zweite Scan kommt aus den eigenen Lebensmitteln');
    });
  });

  test('water counts towards the drinking goal; drinks are their own meal', () async {
    await repo.addWater(uid: user.uid, ml: 250, date: day);
    await repo.addWater(uid: user.uid, ml: 500, date: day);
    final juice = await repo.saveFood(Food(userid: user.uid, name: 'Orangensaft', per100: const Macros(kcal: 45)));
    await repo.addEntry(uid: user.uid, food: juice, grams: 200, meal: Meal.drinks, date: day);

    var d = await repo.getDay(user.uid, day);
    expect(d.drankMl, 950);
    expect(d.goals.waterMl, NutritionGoals.defaultWaterMl);
    expect(d.total.kcal, 90); // Wasser hat keine Kalorien
    expect(d.entriesFor(Meal.drinks).map((e) => e.name), ['Wasser', 'Wasser', 'Orangensaft']);

    await repo.setGoals(user.uid, const Macros(kcal: 2400), waterMl: 3000);
    d = await repo.getDay(user.uid, day);
    expect(d.goals.waterMl, 3000);
    await repo.setGoals(user.uid, const Macros(kcal: 2500)); // Trinkziel bleibt
    expect((await repo.getGoals(user.uid)).waterMl, 3000);
  });

  test('new standard products (drinks) are added for users who already had the old list', () async {
    // Bestandsnutzer: hatte nur Haferflocken als Standardprodukt
    await repo.saveFood(Food(userid: user.uid, name: 'Haferflocken', brand: standardFoodBrand));
    await repo.ensureStandardFoods(user.uid);
    final all = await repo.searchFoods(user.uid);
    expect(all.where((f) => f.name == 'Haferflocken'), hasLength(1));
    expect(all.map((f) => f.name), containsAll(['Wasser', 'Kaffee (schwarz)', 'Apfelschorle']));
    expect(all.length, standardFoods.length);
  });

  test('pack sizes: decimal comma, separators and storage round trip', () {
    expect(Food.parsePackSizes('1,5, 500'), [1.5, 500]);
    expect(Food.parsePackSizes('400,600'), [400, 600]);
    expect(Food.parsePackSizes('250; 500 / 1000'), [250, 500, 1000]);
    expect(Food.parsePackSizes('abc, 0, -3'), isEmpty);
    const food = Food(userid: 1, name: 'Saft', packSizes: [1.5, 6]);
    expect(Food.fromMap(food.toMap()).packSizes, [1.5, 6]);
  });

  group('dishes', () {
    test('an own dish is stored per portion, logged in portions and found again in the search', () async {
      final pizza = await repo.saveDish(uid: user.uid, name: 'Pizza vom Italiener', perPortion: const Macros(kcal: 900, protein: 35, carbs: 100, fat: 38));
      expect((pizza.isDish, pizza.servingGrams), (true, 100.0)); // ohne Gramm: nominell 100 g je Portion

      final entry = await repo.addEntry(uid: user.uid, food: pizza, grams: 150, meal: Meal.dinner, date: day, portions: 1.5);
      expect(entry.portions, 1.5);
      expect(entry.macros.kcal, closeTo(1350, 0.01));
      expect((await repo.getDay(user.uid, day)).entries.single.portions, 1.5);

      final found = (await repo.searchFoods(user.uid, search: 'pizza')).single;
      expect(found.isDish, isTrue);
      expect(found.portionMacros.kcal, closeTo(900, 0.01));
    });

    test('with grams per portion the values per 100 g follow from them', () async {
      final bowl = await repo.saveDish(uid: user.uid, name: 'Buddha-Bowl', perPortion: const Macros(kcal: 600), gramsPerPortion: 400);
      expect(bowl.servingGrams, 400);
      expect(bowl.per100.kcal, closeTo(150, 0.01));
      expect(bowl.portionMacros.kcal, closeTo(600, 0.01));
    });

    test('a recipe portion is logged without a food; changing the portions rescales', () async {
      final entry = await repo.addDishEntry(
        uid: user.uid, name: 'Rote-Linsen-Dal', perPortion: const Macros(kcal: 480, protein: 22), gramsPerPortion: 350,
        portions: 2, meal: Meal.lunch, date: day,
      );
      expect((entry.foodId, entry.grams, entry.portions), (null, 700.0, 2.0));
      expect(entry.macros.kcal, closeTo(960, 0.01));

      final half = await repo.updateEntry(entry, grams: 175, meal: Meal.lunch, portions: 0.5);
      expect((half.portions, half.grams), (0.5, 175.0));
      expect(half.macros.kcal, closeTo(240, 0.01));
    });

    test('a dish keeps its flag through the database and the export map', () {
      const dish = Food(userid: 1, name: 'Döner', per100: Macros(kcal: 700), servingGrams: 100, isDish: true);
      expect(Food.fromMap(dish.toMap()).isDish, isTrue);
      expect(Food.fromMap(const Food(userid: 1, name: 'Apfel').toMap()).isDish, isFalse);
    });
  });
}
