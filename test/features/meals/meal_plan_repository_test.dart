import 'package:flutter_test/flutter_test.dart';

import 'package:frontend/core/database/database.dart';
import 'package:frontend/features/calendar/repositories/appointment_repository.dart';
import 'package:frontend/features/fitness/models/nutrition.dart';
import 'package:frontend/features/fitness/repositories/nutrition_repository.dart';
import 'package:frontend/features/inventory/models/inventory_item.dart';
import 'package:frontend/features/inventory/repositories/inventory_repository.dart';
import 'package:frontend/features/lists/models/lists.dart';
import 'package:frontend/features/lists/repositories/lists_repository.dart';
import 'package:frontend/features/meals/catalog/recipe_catalog.dart';
import 'package:frontend/features/meals/models/meal_plan.dart';
import 'package:frontend/features/meals/repositories/meal_plan_repository.dart';
import 'package:frontend/features/meals/services/pantry_check.dart';

import '../../helpers/test_app.dart';

void main() {
  group('catalog', () {
    test('every recipe is complete and has a unique key', () {
      expect(recipeCatalog.length, greaterThanOrEqualTo(20));
      expect(recipeCatalog.map((r) => r.key).toSet(), hasLength(recipeCatalog.length));
      for (final r in recipeCatalog) {
        expect(r.meals, isNotEmpty, reason: r.name);
        expect(r.ingredients, isNotEmpty, reason: r.name);
        expect(r.steps, isNotEmpty, reason: r.name);
        expect(r.perServing.kcal, greaterThan(0), reason: r.name);
        expect(r.perServing.protein, greaterThan(0), reason: r.name);
        expect(catalogRecipe(r.key), same(r));
      }
      for (final m in plannedMeals) {
        expect(recipeCatalog.where((r) => r.meals.contains(m)).length, greaterThanOrEqualTo(3), reason: m.label);
      }
    });

    test('ingredient amounts scale and round readably; lines are parsed', () {
      const lentils = Ingredient('Rote Linsen', 250, 'g');
      expect(lentils.amountFor(1), '250 g');
      expect(lentils.amountFor(1 / 3), '85 g');
      expect(const Ingredient('Chiasamen', 1, 'EL').amountFor(1.5), '1,5 EL');
      expect(const Ingredient('Banane', 0.5).amountFor(1), '0,5');
      expect(const Ingredient('Salz').amountFor(2), '');

      final parsed = Ingredient.parse('200 g Haferflocken');
      expect((parsed.name, parsed.amount, parsed.unit), ('Haferflocken', 200, 'g'));
      final pieces = Ingredient.parse('2 Knoblauchzehen');
      expect((pieces.name, pieces.amount, pieces.unit), ('Knoblauchzehen', 2, null));
      final tins = Ingredient.parse('2 Dosen Tomaten');
      expect((tins.name, tins.amount, tins.unit), ('Tomaten', 2, 'Dose'));
      expect(tins.amountFor(1), '2 Dosen');
      expect(tins.amountFor(0.5), '1 Dose');
      expect(Ingredient.parse('Pfeffer').amount, isNull);
    });
  });

  group('repository', () {
    late DatabaseService db;
    late MealPlanRepository repo;
    late ListsRepository lists;
    late int uid;
    final day = DateTime(2026, 10, 1);

    setUp(() async {
      db = createTestDatabase();
      lists = ListsRepository(db: db, inventory: InventoryRepository(db: db));
      repo = MealPlanRepository(db: db, lists: lists, inventory: InventoryRepository(db: db));
      uid = (await createTestUser(db)).uid;
    });
    tearDown(() => db.close());

    test('plans dishes per day sorted by time, with own times and removal', () async {
      final dal = catalogRecipe('rote-linsen-dal')!;
      final oats = catalogRecipe('overnight-oats')!;
      final dinner = await repo.plan(uid: uid, recipe: dal, date: day, meal: Meal.dinner, servings: 2);
      await repo.plan(uid: uid, recipe: oats, date: day, meal: Meal.breakfast);
      await repo.plan(uid: uid, recipe: oats, date: day.add(const Duration(days: 1)), meal: Meal.breakfast);

      var plan = await repo.getDay(uid, day);
      expect(plan.map((p) => '${p.name}@${formatMinutes(p.minutes)}'), ['Overnight Oats mit Beeren@07:30', 'Rote-Linsen-Dal@18:30']);
      expect(plan.last.servings, 2);
      expect(await repo.recipeFor(plan.last), same(dal));

      // Abendessen schon um 6 Uhr morgens (unsinnig, zeigt aber die Sortierung nach Uhrzeit)
      await repo.update(dinner.copyWith(time: 6 * 60));
      plan = await repo.getDay(uid, day);
      expect(plan.first.name, 'Rote-Linsen-Dal');
      expect(plan.first.at, DateTime(2026, 10, 1, 6));

      expect(await repo.getRange(uid, day, day.add(const Duration(days: 6))), hasLength(3));
      await repo.remove(dinner.id!);
      expect(await repo.getDay(uid, day), hasLength(1));
    });

    test('eaten dishes land in the nutrition log and can be taken back', () async {
      final nutrition = NutritionRepository(db: db, inventory: InventoryRepository(db: db));
      final dal = catalogRecipe('rote-linsen-dal')!;
      final planned = await repo.plan(uid: uid, recipe: dal, date: day, meal: Meal.lunch, servings: 2);

      final eaten = await repo.markEaten(planned, dal);
      expect(eaten.eaten, isTrue);
      var log = await nutrition.getDay(uid, day);
      final entry = log.entriesFor(Meal.lunch).single;
      expect(entry.name, 'Rote-Linsen-Dal (2 Portionen)');
      expect(entry.macros.kcal, dal.perServing.kcal * 2);
      expect(entry.grams, dal.gramsPerServing * 2);
      expect((await repo.getDay(uid, day)).single.eaten, isTrue);

      final back = await repo.unmarkEaten(eaten);
      expect(back.eaten, isFalse);
      expect((await nutrition.getDay(uid, day)).entries, isEmpty);

      // Eintrag im Protokoll gelöscht → im Plan wieder offen
      final again = await repo.markEaten(back, dal);
      await nutrition.deleteEntry(again.mealEntryId!);
      expect((await repo.getDay(uid, day)).single.eaten, isFalse);
      log = await nutrition.getDay(uid, day);
      expect(log.entries, isEmpty);
    });

    test('ingredients are always added up on the shopping list, with the recipe as source', () async {
      await lists.saveShopping(ShoppingItem(userid: uid, name: 'Zwiebel', amount: 1));
      final dal = catalogRecipe('rote-linsen-dal')!; // 3 Portionen
      final chili = catalogRecipe('chili-sin-carne')!; // 4 Portionen

      final added = await repo.addToShopping(uid, [(dal, 3.0), (chili, 2.0)]);
      expect(added, dal.ingredients.length + chili.ingredients.length);
      final items = {for (final i in await lists.getShopping(uid)) i.name: i};
      expect(items['Zwiebel']!.quantityLabel, '3×'); // 1 selbst + 1 Dal + 1 Chili (aufgerundet)
      expect(items['Rote Linsen']!.quantityLabel, '300 g'); // 250 g + 100 g × 2/4
      expect(items['Knoblauchzehen']!.quantityLabel, '3×'); // 2 + 1
      expect(items['Gehackte Tomaten']!.quantityLabel, '2 Dosen'); // 1 + 2 × 2/4
      expect(items['Rote Linsen']!.category, ShoppingCategory.food);
      final sources = await lists.getSources(items['Rote Linsen']!.id!);
      expect(sources.map((s) => '${s.label}: ${s.amountLabel}'), ['Rote-Linsen-Dal: 250 g', 'Chili sin Carne: 50 g']);

      // Nochmal dasselbe Rezept: ersetzt dessen offene Mengen statt sie zu verdoppeln
      await repo.addToShopping(uid, [(dal, 3.0)]);
      final again = {for (final i in await lists.getShopping(uid)) i.name: i};
      expect(again['Rote Linsen']!.quantityLabel, '300 g');
    });

    test('own recipes are listed first and survive in the plan when deleted', () async {
      final id = await repo.saveRecipe(Recipe(
        userid: uid,
        name: 'Omas Linseneintopf',
        meals: const {Meal.lunch},
        servings: 4,
        ingredients: [Ingredient.parse('300 g Linsen'), Ingredient.parse('Salz')],
        steps: const ['Alles kochen.'],
        perServing: const Macros(kcal: 400, protein: 20),
      ));
      final recipes = await repo.getRecipes(uid);
      expect(recipes.first.name, 'Omas Linseneintopf');
      expect(recipes.first.isOwn, isTrue);
      expect(recipes.first.ingredients.first.amount, 300);
      expect(recipes, hasLength(recipeCatalog.length + 1));

      final planned = await repo.plan(uid: uid, recipe: recipes.first, date: day, meal: Meal.lunch);
      expect((await repo.recipeFor(planned))!.name, 'Omas Linseneintopf');
      await repo.deleteRecipe(id);
      expect(await repo.recipeFor(planned), isNull);
      expect((await repo.getDay(uid, day)).single.name, 'Omas Linseneintopf');
    });

    test('a single food can be planned; eaten it is logged and taken from the pantry, undo restores the log', () async {
      final inventory = InventoryRepository(db: db);
      final nutrition = NutritionRepository(db: db, inventory: inventory);
      final oats = await nutrition.saveFood(Food(userid: uid, name: 'Haferflocken', per100: const Macros(kcal: 370, protein: 13, carbs: 59, fat: 7)));
      final itemId = await inventory.createItem(InventoryItem(userid: uid, kind: InventoryKind.food, name: 'Haferflocken', quantity: 500, unit: 'g', foodId: oats.id));

      final planned = await repo.planFood(uid: uid, food: oats, grams: 60, date: day, meal: Meal.breakfast, itemId: itemId);
      expect((planned.isFood, planned.grams, planned.name), (true, 60.0, 'Haferflocken'));
      expect((await repo.getDay(uid, day)).single.foodId, oats.id);

      final eaten = await repo.markFoodEaten(planned, oats);
      expect(eaten.eaten, isTrue);
      final log = await nutrition.getDay(uid, day);
      expect(log.entries.single.grams, 60);
      expect(log.total.kcal, closeTo(222, 0.01));
      final stock = (await inventory.getItems(uid)).firstWhere((i) => i.id == itemId);
      expect(stock.quantity, 440);

      await repo.unmarkEaten(eaten);
      expect((await nutrition.getDay(uid, day)).entries, isEmpty);
      expect((await repo.getDay(uid, day)).single.eaten, isFalse);
    });

    group('batches', () {
      final chili = catalogRecipe('chili-sin-carne')!; // 4 Portionen
      DateTime d(int offset) => day.add(Duration(days: offset));

      Future<int> plannedDal() async {
        final dal = catalogRecipe('rote-linsen-dal')!;
        final id = await repo.planBatch(uid: uid, recipe: dal, cookDate: day, factor: 1, slots: [PortionSlot(day, Meal.lunch, 3)]);
        final checks = await repo.checkPantry(uid, dal, 1, batchId: id);
        await repo.saveIngredientPlan(uid, id, checks, [for (final _ in checks) false]);
        return id;
      }

      test('saving a batch again after shopping adds nothing twice; more portions add only the difference', () async {
        final dal = catalogRecipe('rote-linsen-dal')!;
        final id = await plannedDal();
        final lentils = dal.ingredients.firstWhere((i) => i.name.contains('Linsen'));
        var item = (await lists.getShopping(uid)).firstWhere((i) => i.name == lentils.name);
        await lists.toggleShopping(item); // gekauft
        final before = await lists.getShopping(uid);

        // Nur die Uhrzeit geändert – der Zutaten-Schritt läuft erneut
        var checks = await repo.checkPantry(uid, dal, 1, batchId: id);
        await repo.saveIngredientPlan(uid, id, checks, [for (final _ in checks) false]);
        final after = await lists.getShopping(uid);
        expect(after.length, before.length);
        expect(after.where((i) => i.name == lentils.name && !i.done), isEmpty); // Gekauftes kommt nicht wieder

        // Doppelte Menge: nur die zweite Hälfte der Linsen kommt neu dazu
        final batch = (await repo.getBatch(id))!;
        await repo.replanBatch(batch, dal, cookDate: day, slots: [PortionSlot(day, Meal.lunch, 6)], factor: 2);
        checks = await repo.checkPantry(uid, dal, 2, batchId: id);
        await repo.saveIngredientPlan(uid, id, checks, [for (final _ in checks) false]);
        item = (await lists.getShopping(uid)).firstWhere((i) => i.name == lentils.name && !i.done);
        expect(item.amount, lentils.amount!);
      });

      test('switches: without pantry nothing is reserved, without shopping nothing goes on the list (and is taken off)', () async {
        final dal = catalogRecipe('rote-linsen-dal')!;
        final inventory = InventoryRepository(db: db);
        final lentils = dal.ingredients.firstWhere((i) => i.name.contains('Linsen'));
        await inventory.createItem(InventoryItem(userid: uid, kind: InventoryKind.food, name: lentils.name, quantity: 1, unit: 'kg'));
        final id = await repo.planBatch(uid: uid, recipe: dal, cookDate: day, factor: 1, slots: [PortionSlot(day, Meal.lunch, 3)]);
        var checks = await repo.checkPantry(uid, dal, 1, batchId: id);
        await repo.saveIngredientPlan(uid, id, checks, [for (final c in checks) c.inPantry]);
        expect(await repo.reservationsOf(id), hasLength(1));
        expect(await lists.getShopping(uid), isNotEmpty);

        // Vorrat aus: die Linsen werden jetzt eingekauft statt reserviert
        checks = await repo.checkPantry(uid, dal, 1, batchId: id);
        await repo.saveIngredientPlan(uid, id, checks, [for (final c in checks) c.inPantry], pantry: false);
        expect(await repo.reservationsOf(id), isEmpty);
        expect((await lists.getShopping(uid)).where((i) => i.name == lentils.name), hasLength(1));

        // Beides aus: nichts reserviert, nichts (mehr) auf der Liste
        await repo.saveIngredientPlan(uid, id, checks, [for (final c in checks) c.inPantry], pantry: false, shop: false);
        expect(await repo.reservationsOf(id), isEmpty);
        expect(await lists.getShopping(uid), isEmpty);
        final batch = (await repo.getBatch(id))!;
        expect((batch.usePantry, batch.shop), (false, false)); // bleibt beim Bearbeiten erhalten
      });

      test('"Zutaten auf die Einkaufsliste" twice for the same recipe puts the amounts on once', () async {
        final dal = catalogRecipe('rote-linsen-dal')!;
        await repo.addToShopping(uid, [(dal, 3.0)]);
        final once = {for (final i in await lists.getShopping(uid)) i.name: i.amount};
        await repo.addToShopping(uid, [(dal, 3.0)]);
        final twice = {for (final i in await lists.getShopping(uid)) i.name: i.amount};
        expect(twice, once);
      });

      test('an item edited by hand keeps its batch share; saving the batch again does not double it', () async {
        final dal = catalogRecipe('rote-linsen-dal')!;
        final id = await plannedDal();
        final lentils = dal.ingredients.firstWhere((i) => i.name.contains('Linsen'));
        final item = (await lists.getShopping(uid)).firstWhere((i) => i.name == lentils.name);
        await lists.saveShopping(item.copyWith(amount: item.amount! + 100)); // etwas mehr für den Vorrat
        final checks = await repo.checkPantry(uid, dal, 1, batchId: id);
        await repo.saveIngredientPlan(uid, id, checks, [for (final _ in checks) false]);
        expect((await lists.getShopping(uid)).firstWhere((i) => i.name == lentils.name).amount, lentils.amount! + 100);
      });

      test('example: 3 × the recipe, 9 portions spread 3/1/4, the cooking is an appointment', () async {
        final dal = catalogRecipe('rote-linsen-dal')!; // 3 Portionen
        final appointments = AppointmentRepository(db: db);
        final id = await repo.planBatch(
          uid: uid,
          recipe: dal,
          cookDate: d(3), // Sonntag
          factor: 3,
          cookHour: 17,
          durationMin: 90,
          slots: [PortionSlot(d(4), Meal.lunch, 3), PortionSlot(d(5), Meal.lunch, 1), PortionSlot(d(6), Meal.dinner, 4)],
        );
        final batch = (await repo.getBatch(id))!;
        expect((batch.servingsOf(dal), batch.cookTimeLabel, batch.durationMin), (9.0, '17:00', 90));
        expect(await repo.unplannedServings(batch, dal), 1);

        var appointment = (await appointments.getAllAppointments(uid)).single;
        expect((appointment.title, appointment.date, appointment.durationMinutes), ('Kochen: ${dal.name}', DateTime(2026, 10, 4, 17), 90));
        expect(batch.appointmentId, appointment.id);

        // Umplanen auf Samstag 11:30 verschiebt den Termin mit
        await repo.replanBatch(batch, dal, cookDate: d(2), cookHour: 11, cookMinute: 30, slots: [PortionSlot(d(4), Meal.lunch, 9)]);
        appointment = (await appointments.getAllAppointments(uid)).single;
        expect(appointment.date, DateTime(2026, 10, 3, 11, 30));

        final at = await repo.deleteBatch(id);
        expect(await appointments.getAllAppointments(uid), isEmpty);
        await repo.restoreBatch(id, at);
        expect((await appointments.getAllAppointments(uid)).single.id, appointment.id);
      });

      test('ingredients: reserve from the pantry, the rest and declined ones go shopping; reserved stock is not offered twice', () async {
        final dal = catalogRecipe('rote-linsen-dal')!;
        final inventory = InventoryRepository(db: db);
        final lentilsNeed = dal.ingredients.firstWhere((i) => i.name.contains('Linsen'));
        await inventory.createItem(InventoryItem(userid: uid, kind: InventoryKind.food, name: lentilsNeed.name, quantity: 0.5, unit: 'kg'));

        final first = await repo.planBatch(uid: uid, recipe: dal, cookDate: day, factor: 1, slots: [PortionSlot(day, Meal.lunch, 3)]);
        var checks = await repo.checkPantry(uid, dal, 1, batchId: first);
        final lentils = checks.indexWhere((c) => c.ingredient.name == lentilsNeed.name);
        expect(checks[lentils].status, PantryStatus.enough);

        final (reserved, shopping) = await repo.saveIngredientPlan(uid, first, checks, [for (final c in checks) c.inPantry]);
        expect(reserved, 1);
        expect(shopping, dal.ingredients.length - 1); // alles andere fehlt
        final shop = await lists.getShopping(uid);
        expect(shop.where((i) => i.name == lentilsNeed.name), isEmpty); // Linsen kommen aus dem Vorrat
        expect((await repo.getBatch(first))!.ingredientsPlanned, isTrue);

        // Zweimal speichern legt nichts doppelt an
        await repo.saveIngredientPlan(uid, first, checks, [for (final c in checks) c.inPantry]);
        expect((await lists.getShopping(uid)).length, shop.length);

        // Ein zweiter Koch-Block mit doppelter Menge: nur noch der Rest der Linsen ist frei
        final second = await repo.planBatch(uid: uid, recipe: dal, cookDate: d(1), factor: 2, slots: [PortionSlot(d(1), Meal.lunch, 6)]);
        checks = await repo.checkPantry(uid, dal, 2, batchId: second);
        final need = lentilsNeed.amount! * 2;
        final free = 500 - lentilsNeed.amount!;
        expect(checks[lentils].status, free >= need ? PantryStatus.enough : (free > 0 ? PantryStatus.partial : PantryStatus.missing));
        expect(checks[lentils].available, closeTo(free / 1000, 1e-9)); // in kg

        // Abgelehnt → komplett auf die Einkaufsliste
        await repo.saveIngredientPlan(uid, second, checks, [for (final _ in checks) false]);
        final lentilsOnList = (await lists.getShopping(uid)).where((i) => i.name == lentilsNeed.name).single;
        expect(lentilsOnList.amount, need);

        // Gekocht: die Reservierung des ersten Blocks wird frei
        await repo.markCooked(uid: uid, recipe: dal, date: day, usages: const [], batch: (await repo.getBatch(first))!);
        expect(await repo.reservationsOf(first), isEmpty);
      });

      test('deleting a batch frees its reservations, undo brings them back', () async {
        final dal = catalogRecipe('rote-linsen-dal')!;
        await InventoryRepository(db: db).createItem(InventoryItem(userid: uid, kind: InventoryKind.food, name: 'Rote Linsen', quantity: 1000, unit: 'g'));
        final id = await repo.planBatch(uid: uid, recipe: dal, cookDate: day, slots: [PortionSlot(day, Meal.lunch, 3)]);
        final checks = await repo.checkPantry(uid, dal, 1, batchId: id);
        await repo.saveIngredientPlan(uid, id, checks, [for (final c in checks) c.inPantry]);
        expect(await repo.reservationsOf(id), hasLength(1));

        final at = await repo.deleteBatch(id);
        expect(await repo.reservationsOf(id), isEmpty);
        await repo.restoreBatch(id, at);
        expect(await repo.reservationsOf(id), hasLength(1));
      });

      test('not all portions need a meal, but never more than cooked; replanning keeps eaten ones', () async {
        expect(
          () => repo.planBatch(uid: uid, recipe: chili, cookDate: day, slots: [PortionSlot(day, Meal.lunch, 5)]),
          throwsA(isA<StateError>()),
        );
        final partial = await repo.planBatch(uid: uid, recipe: chili, cookDate: day, slots: [PortionSlot(day, Meal.lunch, 3)]);
        expect(await repo.unplannedServings((await repo.getBatch(partial))!, chili), 1); // 1 Portion noch frei
        await repo.deleteBatch(partial);
        final id = await repo.planBatch(uid: uid, recipe: chili, cookDate: day, factor: 1.5, slots: [
          PortionSlot(day, Meal.lunch, 2),
          PortionSlot(day, Meal.dinner, 2),
          PortionSlot(d(1), Meal.lunch, 2),
        ]);
        final batch = (await repo.getBatch(id))!;
        expect(batch.servingsOf(chili), 6);
        final meals = await repo.getBatchMeals(id);
        expect(meals.map((m) => m.servings), [2, 2, 2]);

        await repo.markEaten(meals.first, chili); // 2 Portionen gegessen
        await repo.replanBatch(batch, chili, cookDate: day, slots: [PortionSlot(d(2), Meal.dinner, 4)]);
        final after = await repo.getBatchMeals(id);
        expect(after.map((m) => (m.date, m.meal, m.servings, m.eaten)), [(day, Meal.lunch, 2.0, true), (d(2), Meal.dinner, 4.0, false)]);
        expect(await repo.getBatches(uid, d(2), d(2)), hasLength(1)); // gefunden über die Portion

        final at = await repo.deleteBatch(id);
        expect(await repo.getRange(uid, day, d(6)), isEmpty);
        await repo.restoreBatch(id, at);
        expect(await repo.getRange(uid, day, d(6)), hasLength(2));
      });

      test('shopping for a batch takes the whole recipe × factor on top; a batch can be taken off again', () async {
        final id = await repo.planBatch(uid: uid, recipe: chili, cookDate: day, factor: 2, slots: [
          for (var i = 0; i < 4; i++) ...[PortionSlot(d(i), Meal.lunch, 1), PortionSlot(d(i), Meal.dinner, 1)],
        ]);
        await lists.addToList(uid, name: 'Rote Linsen', amount: 100, unit: 'g'); // stand schon drauf
        final checks = await repo.checkPantry(uid, chili, 2, batchId: id); // Vorrat leer → alles einkaufen
        await repo.saveIngredientPlan(uid, id, checks, [for (final _ in checks) false]);
        var items = {for (final i in await lists.getShopping(uid)) i.name: i};
        expect(items['Rote Linsen']!.quantityLabel, '300 g'); // 100 + 2 × 100
        expect(items['Gehackte Tomaten']!.quantityLabel, '4 Dosen');

        final at = await repo.removeBatchFromShopping(uid, id);
        items = {for (final i in await lists.getShopping(uid)) i.name: i};
        expect(items.keys, ['Rote Linsen']);
        expect(items['Rote Linsen']!.quantityLabel, '100 g');
        await repo.restoreShopping(uid, at);
        expect((await lists.getShopping(uid)).length, greaterThan(5));
      });

      test('cooked: takes the actual amounts from the pantry and marks the batch', () async {
        final inventory = InventoryRepository(db: db);
        final paprikaId = await inventory.createItem(InventoryItem(userid: uid, kind: InventoryKind.food, name: 'Paprika', quantity: 5));
        final id = await repo.planBatch(uid: uid, recipe: chili, cookDate: day, slots: [PortionSlot(day, Meal.dinner, 4)]);
        final log = await repo.markCooked(
          uid: uid,
          recipe: chili,
          date: day,
          batch: await repo.getBatch(id),
          usages: [
            CookUsage(ingredient: 'Paprika', planned: '2', itemId: paprikaId, itemName: 'Paprika', amount: 2),
            const CookUsage(ingredient: 'Zwiebel', planned: '1'), // nicht aus dem Vorrat
          ],
        );
        expect((await inventory.getItem(paprikaId))!.quantity, 3);
        expect((await repo.getBatch(id))!.cooked, isTrue);
        expect((await repo.getCookLogs(uid, day, day)).single.usages.map((u) => (u.ingredient, u.amount)),
            [('Paprika', 2.0), ('Zwiebel', null)]);
        expect(log.id, isNotNull);
      });

      test('cooked: an item used up disappears, one deleted meanwhile is skipped – nothing half done', () async {
        final inventory = InventoryRepository(db: db);
        final tofu = await inventory.createItem(InventoryItem(userid: uid, kind: InventoryKind.food, name: 'Tofu', quantity: 200, unit: 'g'));
        final gone = await inventory.createItem(InventoryItem(userid: uid, kind: InventoryKind.food, name: 'Paprika', quantity: 2));
        await inventory.deleteItem(gone);
        await repo.markCooked(uid: uid, recipe: chili, date: day, usages: [
          CookUsage(ingredient: 'Tofu', planned: '200 g', itemId: tofu, itemName: 'Tofu', amount: 250),
          CookUsage(ingredient: 'Paprika', planned: '2', itemId: gone, itemName: 'Paprika', amount: 2),
        ]);
        expect(await inventory.getItems(uid), isEmpty);
        expect((await repo.getCookLogs(uid, day, day)).single.name, chili.name);
      });
    });
  });
}
