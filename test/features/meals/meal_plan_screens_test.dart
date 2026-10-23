import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:frontend/features/calendar/repositories/appointment_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'package:frontend/core/database/database.dart';
import 'package:frontend/features/dashboard/screens/home.dart';
import 'package:frontend/features/fitness/models/nutrition.dart';
import 'package:frontend/features/fitness/repositories/nutrition_repository.dart';
import 'package:frontend/app/app_tabs.dart';
import 'package:frontend/features/food/screens/food_hub_screen.dart';
import 'package:frontend/core/ui/app_ui.dart';
import 'package:frontend/features/inventory/models/inventory_item.dart';
import 'package:frontend/features/inventory/repositories/inventory_repository.dart';
import 'package:frontend/features/lists/repositories/lists_repository.dart';
import 'package:frontend/features/meals/catalog/recipe_catalog.dart';
import 'package:frontend/features/meals/models/meal_plan.dart';
import 'package:frontend/features/meals/repositories/meal_plan_repository.dart';
import 'package:frontend/features/meals/screens/meal_plan_screen.dart';
import 'package:frontend/features/meals/screens/portion_planner_screen.dart';
import 'package:frontend/features/meals/screens/recipe_screen.dart';
import 'package:frontend/features/meals/screens/recipes_screen.dart';

import '../../helpers/test_app.dart';

/// Planer abschließen: weiter zu den Zutaten, dann einplanen.
Future<void> confirmPlan(WidgetTester tester) async {
  await tester.tap(find.widgetWithText(ElevatedButton, 'Weiter: Zutaten prüfen'));
  await pumpUntil(tester, find.widgetWithText(ElevatedButton, 'Einplanen'));
  await tester.tap(find.widgetWithText(ElevatedButton, 'Einplanen'));
}

void main() {
  late DatabaseService db;

  setUpAll(() => initializeDateFormatting('de_DE'));
  setUp(() => db = createTestDatabase());

  MealPlanRepository repo() =>
      MealPlanRepository(db: db, lists: ListsRepository(db: db, inventory: InventoryRepository(db: db)), inventory: InventoryRepository(db: db));
  DateTime today() {
    final n = DateTime.now();
    return DateTime(n.year, n.month, n.day);
  }

  testWidgets('plan a dish for lunch, open its recipe and log it as eaten', (tester) async {
    useTallScreen(tester);
    final user = await seedDb(tester, db, () => createTestUser(db));
    await tester.pumpWidget(testApp(db, MealPlanScreen(user: user)));
    await pumpUntil(tester, find.text('Mittagessen'));
    expect(find.textContaining('HEUTE, '), findsOneWidget); // GroupLabel in Großbuchstaben
    expect(find.text('Noch nichts geplant'), findsNWidgets(4));

    await tester.tap(find.byTooltip('Mittagessen: Gericht hinzufügen'));
    await pumpUntil(tester, find.text('Kochen planen').hitTestable());
    await tester.tap(find.text('Kochen planen'));
    await pumpUntil(tester, find.text('Gericht für Mittagessen'));
    expect(find.text('Overnight Oats mit Beeren'), findsNothing); // passt nicht zum Mittagessen
    await tester.enterText(find.byType(TextField), 'linsen');
    await tester.pump();
    await tester.tap(find.text('Rote-Linsen-Dal'));
    // Das Rezept ergibt 3 Portionen – heute Mittag liegt schon eine; übrige dürfen bleiben
    await pumpUntil(tester, find.text('Noch 2 Portionen frei – kannst du auch später verteilen'));
    expect(tester.widget<ElevatedButton>(find.widgetWithText(ElevatedButton, 'Weiter: Zutaten prüfen')).onPressed, isNotNull);
    await tester.tap(find.text('Abendessen').first); // heute Abend
    await tester.pump();
    await tester.tap(find.text('Mittagessen').first); // morgen Mittag (heute ist schon „Mittagessen ×1“)
    await tester.pump();
    expect(find.text('Alle 3 Portionen verteilt'), findsOneWidget);
    await confirmPlan(tester);
    await pumpUntil(tester, find.text('Kochen: Rote-Linsen-Dal'));
    expect(find.text('Rote-Linsen-Dal'), findsNWidgets(2)); // heute Mittag und Abend
    expect(find.text('Noch nichts geplant'), findsNWidgets(2));
    final batch = (await readDb(tester, () => repo().getBatches(user.uid, today(), today()))).single;
    expect(batch.factor, 1);
    final meals = await readDb(tester, () => repo().getBatchMeals(batch.id!));
    expect(meals.map((m) => (m.date, m.meal)),
        [(today(), Meal.lunch), (today(), Meal.dinner), (today().add(const Duration(days: 1)), Meal.lunch)]);

    // Antippen zeigt das Rezept – Zutaten passend zu 1 von 3 Portionen
    await tester.tap(find.text('Rote-Linsen-Dal').first);
    await pumpUntil(tester, find.text('Als gegessen eintragen'));
    expect(find.text('ZUTATEN'), findsOneWidget);
    expect(find.text('ZUBEREITUNG'), findsOneWidget);
    expect(find.text('85 g'), findsOneWidget); // 250 g rote Linsen / 3
    expect(find.textContaining('Mittagessen um 12:30 Uhr'), findsOneWidget);

    await tester.tap(find.byTooltip('Mehr Portionen'));
    await pumpUntil(tester, find.text('2 Portionen'));
    expect(find.text('165 g'), findsOneWidget);

    await tester.tap(find.text('Als gegessen eintragen'));
    await pumpUntil(tester, find.text('Gegessen – rückgängig machen'));
    final log = await readDb(tester, () => NutritionRepository(db: db, inventory: InventoryRepository(db: db)).getDay(user.uid, today()));
    expect(log.entriesFor(Meal.lunch).single.name, 'Rote-Linsen-Dal (2 Portionen)');
    expect(log.total.kcal, 2 * catalogRecipe('rote-linsen-dal')!.perServing.kcal);

    await pageBack(tester);
    await pumpUntil(tester, find.byIcon(Icons.check_circle_rounded));
    await pumpUntil(tester, find.textContaining('2 Portionen')); // neu geladen nach dem Zurückgehen
    await disposeApp(tester, db);
  });

  testWidgets('cooked: what was taken from the pantry is booked off (200 g recipe vs. 2 pieces)', (tester) async {
    useTallScreen(tester);
    final inventory = InventoryRepository(db: db);
    final user = await seedDb(tester, db, () async {
      final u = await createTestUser(db);
      await inventory.createItem(InventoryItem(userid: u.uid, kind: InventoryKind.food, name: 'Paprika', quantity: 5));
      await inventory.createItem(InventoryItem(userid: u.uid, kind: InventoryKind.food, name: 'Räuchertofu', quantity: 400, unit: 'g'));
      final recipe = catalogRecipe('gemuesepfanne-raeuchertofu')!; // 2 Portionen
      await repo().planBatch(uid: u.uid, recipe: recipe, cookDate: today(), slots: [
        PortionSlot(today(), Meal.lunch, 1),
        PortionSlot(today(), Meal.dinner, 1),
      ]);
      return u;
    });
    await tester.pumpWidget(testApp(db, MealPlanScreen(user: user)));
    await pumpUntil(tester, find.text('Gekocht'));
    await tester.tap(find.text('Gekocht'));
    await pumpUntil(tester, find.text('Als gekocht eintragen'));
    expect(find.text('200 g'), findsOneWidget); // Räuchertofu laut Rezept
    // Paprika: Rezept „1“ Stück, Vorrat in Stück → vorbelegt; auf 2 erhöhen
    final paprika = find.ancestor(of: find.text('Paprika'), matching: find.byType(AppCard)).first;
    await tester.enterText(find.descendant(of: paprika, matching: find.byType(TextField)), '2');
    await tester.tap(find.text('Als gekocht eintragen'));
    await pumpUntil(tester, find.textContaining('als gekocht eingetragen'));

    final items = {for (final i in await readDb(tester, () => inventory.getItems(user.uid))) i.name: i.quantity};
    expect(items['Paprika'], 3);
    expect(items['Räuchertofu'], 200);
    final logs = await readDb(tester, () => repo().getCookLogs(user.uid, today(), today()));
    final usage = logs.single.usages.firstWhere((u) => u.ingredient == 'Paprika');
    expect((usage.planned, usage.amount, usage.itemName), ('1', 2.0, 'Paprika'));
    expect((await readDb(tester, () => repo().getBatches(user.uid, today(), today()))).single.cooked, isTrue);
    await disposeApp(tester, db);
  });

  testWidgets('recipe list: browse, put ingredients on the shopping list and plan for a day', (tester) async {
    useTallScreen(tester);
    final user = await seedDb(tester, db, () => createTestUser(db));
    await tester.pumpWidget(testApp(db, RecipesScreen(userid: user.uid)));
    await pumpUntil(tester, find.text('Chili sin Carne'));

    await tester.tap(find.text('Snacks'));
    await tester.pump();
    expect(find.text('Chili sin Carne'), findsNothing);
    expect(find.text('Dattel-Hafer-Energy-Balls'), findsOneWidget);
    await tester.tap(find.text('Alle'));
    await tester.pump();

    await tester.ensureVisible(find.text('Chili sin Carne'));
    await tester.tap(find.text('Chili sin Carne'));
    await pumpUntil(tester, find.text('Einplanen'));
    expect(find.text('4 Portionen'), findsOneWidget);

    await tester.ensureVisible(find.text('Zutaten auf die Einkaufsliste'));
    await tester.tap(find.text('Zutaten auf die Einkaufsliste'));
    await pumpUntil(tester, find.textContaining('auf der Einkaufsliste – nochmal tippen ersetzt sie'));
    final shopping = await readDb(tester, () => ListsRepository(db: db, inventory: InventoryRepository(db: db)).getShopping(user.uid));
    expect(shopping.map((i) => i.name), contains('Kidneybohnen (Dose, abgetropft)'));

    await tester.tap(find.text('Einplanen'));
    await pumpUntil(tester, find.text('Noch 4 Portionen frei – kannst du auch später verteilen'));
    await tester.tap(find.text('Automatisch auf Mittag- und Abendessen verteilen'));
    await tester.pump();
    await confirmPlan(tester);
    await pumpUntil(tester, find.textContaining('eingeplant'));
    final planned = await readDb(tester, () => repo().getRange(user.uid, today(), today().add(const Duration(days: 6))));
    expect(planned.map((p) => p.meal), [Meal.lunch, Meal.dinner, Meal.lunch, Meal.dinner]);
    expect(planned.every((p) => p.name == 'Chili sin Carne' && p.batchId != null), isTrue);

    // Vertippt: Zutaten wieder von der Einkaufsliste
    await tester.ensureVisible(find.text('Zutaten wieder von der Einkaufsliste nehmen'));
    await tester.tap(find.text('Zutaten wieder von der Einkaufsliste nehmen'));
    await pumpUntil(tester, find.textContaining('gelöscht'));
    // Übrig bleibt nur der Einkauf des geplanten Koch-Blocks (beim Einplanen gegen den leeren Vorrat geprüft)
    final chili = catalogRecipe('chili-sin-carne')!;
    final left = await readDb(tester, () => ListsRepository(db: db, inventory: InventoryRepository(db: db)).getShopping(user.uid));
    expect(left.map((i) => i.name).toSet(), chili.ingredients.map((i) => i.name).toSet());
    await disposeApp(tester, db);
  });

  testWidgets('own recipe: create it from the picker and it is planned right away', (tester) async {
    useTallScreen(tester);
    final user = await seedDb(tester, db, () => createTestUser(db));
    await tester.pumpWidget(testApp(db, MealPlanScreen(user: user)));
    await pumpUntil(tester, find.text('Abendessen'));

    await tester.tap(find.byTooltip('Abendessen: Gericht hinzufügen'));
    await pumpUntil(tester, find.text('Kochen planen').hitTestable());
    await tester.tap(find.text('Kochen planen'));
    await pumpUntil(tester, find.text('Eigenes Rezept'));
    await tester.tap(find.text('Eigenes Rezept'));
    await pumpUntil(tester, find.text('Neues Rezept'));

    await enterInCard(tester, 'Name', 'Ofengemüse');
    await enterInCard(tester, 'Zutaten – eine pro Zeile', '500 g Kartoffeln\n2 Paprika\nRosmarin');
    await enterInCard(tester, 'Zubereitung – ein Schritt pro Zeile', 'Schneiden.\nBacken.');
    await tester.enterText(find.widgetWithText(TextFormField, 'kcal'), '420');
    await tester.ensureVisible(find.text('Hinzufügen'));
    await tester.tap(find.text('Hinzufügen'));
    // Verteilen: 2 Portionen, heute Abend ist schon eine
    await pumpUntil(tester, find.text('Noch 1 Portion frei – kannst du auch später verteilen'));
    await tester.tap(find.text('Mittagessen').at(1)); // morgen Mittag
    await tester.pump();
    await confirmPlan(tester);
    await pumpUntil(tester, find.textContaining('1 Portion · 20 min · 420 kcal'));

    final recipes = await readDb(tester, () => repo().getRecipes(user.uid));
    final own = recipes.first;
    expect(own.name, 'Ofengemüse');
    expect(own.ingredients.map((i) => i.toString()), ['500 g Kartoffeln', '2 Paprika', 'Rosmarin']);
    expect(own.steps, ['Schneiden.', 'Backen.']);

    await tester.tap(find.text('Ofengemüse'));
    await pumpUntil(tester, find.byTooltip('Rezept bearbeiten'));
    expect(find.text('Rosmarin'), findsOneWidget);
    await disposeApp(tester, db);
  });

  testWidgets('home: tapping a meal logs it as eaten, again takes it back, long press opens the recipe', (tester) async {
    useTallScreen(tester);
    final user = await seedDb(tester, db, () async {
      final u = await createTestUser(db);
      await repo().plan(uid: u.uid, recipe: catalogRecipe('overnight-oats')!, date: today(), meal: Meal.breakfast);
      await repo().plan(uid: u.uid, recipe: catalogRecipe('linsen-bolognese')!, date: today(), meal: Meal.dinner);
      return u;
    });
    Future<List<MealEntry>> entries() =>
        readDb(tester, () async => (await NutritionRepository(db: db, inventory: InventoryRepository(db: db)).getDay(user.uid, today())).entries);
    await tester.pumpWidget(testApp(db, Home(user: user)));
    await pumpUntil(tester, find.text('Essen heute'));
    expect(find.text('Overnight Oats mit Beeren'), findsOneWidget);
    expect(find.text('07:30'), findsOneWidget);
    expect(find.text('18:30'), findsOneWidget);

    const dish = 'Linsen-Bolognese mit Vollkornspaghetti';
    await tester.tap(find.text(dish));
    await pumpUntil(tester, find.text('„$dish“ unter Abendessen eingetragen'));
    expect(find.byType(RecipeScreen), findsNothing);
    final logged = await entries();
    expect(logged.single.name, dish);
    expect(logged.single.macros.kcal, greaterThan(0));

    await tester.tap(find.text(dish));
    await pumpUntil(tester, find.text('„$dish“ aus dem Ernährungsprotokoll entfernt'));
    expect(await entries(), isEmpty);

    await tester.longPress(find.text(dish));
    await pumpUntil(tester, find.byType(RecipeScreen));
    await disposeApp(tester, db);
  });

  testWidgets('home: tapping a planned food logs it with its calories', (tester) async {
    useTallScreen(tester);
    final user = await seedDb(tester, db, () async {
      final u = await createTestUser(db);
      final skyr = await NutritionRepository(db: db, inventory: InventoryRepository(db: db))
          .saveFood(Food(userid: u.uid, name: 'Skyr', per100: const Macros(kcal: 60, protein: 11)));
      await repo().planFood(uid: u.uid, food: skyr, grams: 250, date: today(), meal: Meal.breakfast);
      return u;
    });
    await tester.pumpWidget(testApp(db, Home(user: user)));
    await pumpUntil(tester, find.text('Skyr'));
    await tester.tap(find.text('Skyr'));
    await pumpUntil(tester, find.text('„Skyr“ unter Frühstück eingetragen'));
    expect(find.textContaining('Rezept zu'), findsNothing);
    final day = await readDb(tester, () => NutritionRepository(db: db, inventory: InventoryRepository(db: db)).getDay(user.uid, today()));
    final e = day.entries.single;
    expect((e.name, e.grams, e.macros.kcal), ('Skyr', 250.0, 150.0));
    await disposeApp(tester, db);
  });

  testWidgets('food hub has the meal plan tab', (tester) async {
    useTallScreen(tester);
    final user = await seedDb(tester, db, () => createTestUser(db));
    await tester.pumpWidget(testApp(db, FoodHubScreen(user: user, initialSection: FoodSection.mealPlan)));
    await pumpUntil(tester, find.text('Frühstück'));
    expect(find.text('Essensplan'), findsOneWidget);
    expect(find.text('Wocheneinkauf'), findsNothing); // Einkauf läuft über den Zutaten-Schritt beim Einplanen
    await disposeApp(tester, db);
  });

  testWidgets('meal plan and recipe render on a 360 dp phone without overflow', (tester) async {
    tester.view.physicalSize = const Size(360, 780);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final user = await seedDb(tester, db, () async {
      final u = await createTestUser(db);
      for (final (key, meal) in [
        ('tofu-ruehrei', Meal.breakfast),
        ('ofenkartoffeln-brokkoli', Meal.lunch),
        ('gemuesesticks-hummus', Meal.snack),
        ('suesskartoffel-bohnen-wraps', Meal.dinner),
      ]) {
        await repo().plan(uid: u.uid, recipe: catalogRecipe(key)!, date: today(), meal: meal, servings: 2);
      }
      return u;
    });
    await tester.pumpWidget(testApp(db, MealPlanScreen(user: user)));
    await pumpUntil(tester, find.text('Ofenkartoffeln mit Brokkoli und Bohnen-Dip'));
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('Ofenkartoffeln mit Brokkoli und Bohnen-Dip'));
    await pumpUntil(tester, find.text('ZUTATEN'));
    expect(tester.takeException(), isNull);
    await disposeApp(tester, db);
  });

  group('clock change (DST)', () {
    testWidgets('week arrows move exactly one week across the change in spring and autumn', (tester) async {
      useTallScreen(tester);
      final user = await seedDb(tester, db, () => createTestUser(db));
      await tester.pumpWidget(testApp(db, MealPlanScreen(user: user, clock: () => DateTime(2026, 3, 30, 9))));
      await pumpUntil(tester, find.text('30.3. – 5.4.'));
      await tester.tap(find.byTooltip('Vorige Woche'));
      await pumpUntil(tester, find.text('23.3. – 29.3.'));
      // Herbst: von der Woche mit dem 25.10. (25 Stunden) weiter
      for (var i = 0; i < 30; i++) {
        if (find.text('19.10. – 25.10.').evaluate().isNotEmpty) break;
        await tester.tap(find.byTooltip('Nächste Woche'));
        await tester.pump();
      }
      await pumpUntil(tester, find.text('19.10. – 25.10.'));
      await tester.tap(find.byTooltip('Nächste Woche'));
      await pumpUntil(tester, find.text('26.10. – 1.11.'));
      await disposeApp(tester, db);
    });

    testWidgets('portion planner around 25.10. shows every day once and saves calendar days', (tester) async {
      useTallScreen(tester);
      final user = await seedDb(tester, db, () => createTestUser(db));
      final recipe = catalogRecipe('rote-linsen-dal')!; // 3 Portionen
      await tester.pumpWidget(testApp(db, launcher(PortionPlannerScreen(userid: user.uid, recipe: recipe, initialDate: DateTime(2026, 10, 24)))));
      await tester.tap(find.text('öffnen'));
      await pumpUntil(tester, find.text('Sonntag, 25.10.'));
      expect(find.text('Sonntag, 25.10.'), findsOneWidget);
      await tester.scrollUntilVisible(find.text('Montag, 26.10.'), 200, scrollable: find.byType(Scrollable).first);
      expect(find.text('Montag, 26.10.'), findsOneWidget);
      await tester.scrollUntilVisible(find.text('Automatisch auf Mittag- und Abendessen verteilen'), -200,
          scrollable: find.byType(Scrollable).first);
      await tester.tap(find.text('Automatisch auf Mittag- und Abendessen verteilen'));
      await tester.pump();
      await confirmPlan(tester);
      await pumpUntil(tester, find.text('result:true'));
      final batch = (await readDb(tester, () => repo().getBatches(user.uid, DateTime(2026, 10, 24), DateTime(2026, 10, 24)))).single;
      final meals = await readDb(tester, () => repo().getBatchMeals(batch.id!));
      expect(meals.map((m) => (m.date, m.meal)), [
        (DateTime(2026, 10, 24), Meal.lunch),
        (DateTime(2026, 10, 24), Meal.dinner),
        (DateTime(2026, 10, 25), Meal.lunch),
      ]);
      await disposeApp(tester, db);
    });
  });

  testWidgets('own recipe: deleting it in the editor removes it with undo', (tester) async {
    useTallScreen(tester);
    final user = await seedDb(tester, db, () async {
      final u = await createTestUser(db);
      await repo().saveRecipe(Recipe(
        userid: u.uid,
        name: 'Omas Linseneintopf',
        summary: '',
        meals: const {Meal.lunch},
        servings: 2,
        minutes: 40,
        ingredients: const [],
        steps: const [],
        perServing: const Macros(kcal: 400, protein: 20, carbs: 50, fat: 8),
      ));
      return u;
    });
    await tester.pumpWidget(testApp(db, RecipesScreen(userid: user.uid)));
    await pumpUntil(tester, find.text('Omas Linseneintopf'));
    await tester.ensureVisible(find.text('Omas Linseneintopf'));
    await tester.tap(find.text('Omas Linseneintopf'));
    await pumpUntil(tester, find.byTooltip('Rezept bearbeiten'));
    await tester.tap(find.byTooltip('Rezept bearbeiten'));
    await pumpUntil(tester, find.text('Rezept bearbeiten'));
    await tester.ensureVisible(find.text('Löschen'));
    await tester.tap(find.text('Löschen'));
    await pumpUntil(tester, find.text('Rückgängig'));
    expect((await readDb(tester, () => repo().getRecipes(user.uid))).where((r) => r.name == 'Omas Linseneintopf'), isEmpty);

    await tester.tap(find.text('Rückgängig'));
    await pumpUntilGone(tester, find.text('Rückgängig'));
    await tester.pump(const Duration(milliseconds: 300));
    expect((await readDb(tester, () => repo().getRecipes(user.uid))).where((r) => r.name == 'Omas Linseneintopf'), hasLength(1));
    await disposeApp(tester, db);
  });

  testWidgets('re-planning: an eaten portion stays, a bigger factor is filled up, a smaller one trims from the end', (tester) async {
    useTallScreen(tester);
    final recipe = catalogRecipe('rote-linsen-dal')!; // 3 Portionen
    final d = today();
    final tomorrow = DateTime(d.year, d.month, d.day + 1);
    late MealBatch batch;
    final user = await seedDb(tester, db, () async {
      final u = await createTestUser(db);
      final id = await repo().planBatch(uid: u.uid, recipe: recipe, cookDate: d, slots: [
        PortionSlot(d, Meal.lunch, 1),
        PortionSlot(d, Meal.dinner, 1),
        PortionSlot(tomorrow, Meal.lunch, 1),
      ]);
      batch = (await repo().getBatch(id))!;
      final lunch = (await repo().getBatchMeals(id)).firstWhere((m) => m.meal == Meal.lunch && m.date == d);
      await repo().markEaten(lunch, recipe);
      return u;
    });
    await tester.pumpWidget(testApp(db, launcher(PortionPlannerScreen(userid: user.uid, recipe: recipe, initialDate: d, batch: batch))));
    await tester.tap(find.text('öffnen'));
    await pumpUntil(tester, find.text('1 Portion ist schon gegessen.'));
    expect(find.text('Alle 3 Portionen verteilt'), findsOneWidget);

    await tester.tap(find.text('×2 = 6 Portionen'));
    await tester.pump();
    expect(find.text('Noch 3 Portionen frei – kannst du auch später verteilen'), findsOneWidget);
    await tester.tap(find.text('Automatisch auf Mittag- und Abendessen verteilen'));
    await tester.pump();
    expect(find.text('Alle 6 Portionen verteilt'), findsOneWidget);

    await tester.tap(find.text('×1.5 = 4.5 Portionen'.replaceAll('.', ',')));
    await tester.pump();
    expect(find.text('Alle 4,5 Portionen verteilt'), findsOneWidget); // von hinten gekürzt

    await confirmPlan(tester);
    await pumpUntil(tester, find.text('result:true'));
    final meals = await readDb(tester, () => repo().getBatchMeals(batch.id!));
    expect(meals.where((m) => m.eaten).map((m) => (m.date, m.meal)), [(d, Meal.lunch)]);
    expect(meals.fold<double>(0, (s, m) => s + m.servings), 4.5);
    expect((await readDb(tester, () => repo().getBatch(batch.id!)))!.factor, 1.5);
    await disposeApp(tester, db);
  });

  testWidgets('cooked without anything in the pantry: nothing is booked off, the batch is marked', (tester) async {
    useTallScreen(tester);
    final user = await seedDb(tester, db, () async {
      final u = await createTestUser(db);
      await repo().planBatch(uid: u.uid, recipe: catalogRecipe('rote-linsen-dal')!, cookDate: today(), slots: [
        PortionSlot(today(), Meal.lunch, 1),
        PortionSlot(today(), Meal.dinner, 2),
      ]);
      return u;
    });
    await tester.pumpWidget(testApp(db, MealPlanScreen(user: user)));
    await pumpUntil(tester, find.text('Gekocht'));
    await tester.tap(find.text('Gekocht'));
    await pumpUntil(tester, find.text('Als gekocht eintragen'));
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Als gekocht eintragen'));
    await pumpUntil(tester, find.textContaining('als gekocht eingetragen'));

    final log = (await readDb(tester, () => repo().getCookLogs(user.uid, today(), today()))).single;
    expect(log.usages.where((u) => u.fromPantry), isEmpty);
    expect((await readDb(tester, () => repo().getBatches(user.uid, today(), today()))).single.cooked, isTrue);
    await disposeApp(tester, db);
  });

  testWidgets('cook planning: 9 portions on Sunday 17:00 spread 3/1/4, pantry reserved, the rest goes shopping', (tester) async {
    useTallScreen(tester);
    final recipe = catalogRecipe('rote-linsen-dal')!; // 3 Portionen
    final sunday = DateTime(2026, 11, 1);
    final user = await seedDb(tester, db, () async {
      final u = await createTestUser(db);
      final inventory = InventoryRepository(db: db);
      await inventory.createItem(InventoryItem(userid: u.uid, kind: InventoryKind.food, name: 'Rote Linsen', quantity: 1, unit: 'kg'));
      await inventory.createItem(InventoryItem(userid: u.uid, kind: InventoryKind.food, name: 'Gehackte Tomaten', quantity: 2));
      return u;
    });
    await tester.pumpWidget(testApp(db, launcher(PortionPlannerScreen(userid: user.uid, recipe: recipe, initialDate: sunday))));
    await tester.tap(find.text('öffnen'));
    await pumpUntil(tester, find.text('Portionen'));

    // Dreifache Menge über den Portionen-Zähler, 1,5 Stunden kochen
    for (var i = 0; i < 6; i++) {
      await tester.tap(find.byTooltip('Eine Portion mehr'));
      await tester.pump();
    }
    expect(find.text('×3 = 9 Portionen'), findsOneWidget);
    expect(tester.widget<AppChip>(find.widgetWithText(AppChip, '×3 = 9 Portionen')).selected, isTrue);
    await tester.tap(find.text('1,5 Std'));
    await tester.pump();

    Future<void> add(String day, String meal, int times) async {
      for (var i = 0; i < times; i++) {
        final card = find.ancestor(of: find.text(day), matching: find.byType(AppCard)).first;
        final chip = find.descendant(of: card, matching: find.textContaining(meal)).first;
        await tester.ensureVisible(chip);
        await tester.tap(chip);
        await tester.pump();
      }
    }

    await add('Montag, 2.11.', 'Mittagessen', 3); // Besuch
    await add('Dienstag, 3.11.', 'Mittagessen', 1);
    await add('Mittwoch, 4.11.', 'Abendessen', 4); // die nächste Gruppe
    expect(find.text('Noch 1 Portion frei – kannst du auch später verteilen'), findsOneWidget);

    await tester.tap(find.widgetWithText(ElevatedButton, 'Weiter: Zutaten prüfen'));
    await pumpUntil(tester, find.text('im Vorrat: Rote Linsen'));
    expect(find.text('nur 2 da – Rest wird eingekauft'), findsOneWidget); // Tomaten: 2 von 3 Dosen
    expect(find.text('nicht im Vorrat'), findsWidgets);
    // Tomaten lieber frisch kaufen
    final tomatoCard = find.ancestor(of: find.textContaining('Gehackte Tomaten'), matching: find.byType(AppCard)).first;
    await tester.tap(find.descendant(of: tomatoCard, matching: find.byType(Switch)));
    await tester.pump();
    // Linsen aus dem Vorrat, alles andere (auch die Tomaten) wird eingekauft
    expect(find.text('1 aus dem Vorrat · ${recipe.ingredients.length - 1} auf die Einkaufsliste'), findsOneWidget);
    await tester.tap(find.widgetWithText(ElevatedButton, 'Einplanen'));
    await pumpUntil(tester, find.text('result:true'));

    final batch = (await readDb(tester, () => repo().getBatches(user.uid, sunday, sunday))).single;
    expect((batch.factor, batch.cookTimeLabel, batch.durationMin), (3.0, '17:00', 90));
    final meals = await readDb(tester, () => repo().getBatchMeals(batch.id!));
    expect(meals.map((m) => (m.date.day, m.meal, m.servings)), [(2, Meal.lunch, 3.0), (3, Meal.lunch, 1.0), (4, Meal.dinner, 4.0)]);
    final appointment = (await readDb(tester, () => AppointmentRepository(db: db).getAllAppointments(user.uid))).single;
    expect((appointment.title, appointment.date, appointment.durationMinutes), ('Kochen: Rote-Linsen-Dal', DateTime(2026, 11, 1, 17), 90));
    final reserved = await readDb(tester, () => repo().reservationsOf(batch.id!));
    expect(reserved.map((r) => (r.ingredient, r.amount)), [('Rote Linsen', 0.75)]); // 750 g aus der 1-kg-Packung
    final shopping = await readDb(tester, () => ListsRepository(db: db, inventory: InventoryRepository(db: db)).getShopping(user.uid));
    expect(shopping.where((i) => i.name == 'Rote Linsen'), isEmpty);
    expect(shopping.firstWhere((i) => i.name == 'Gehackte Tomaten').amount, 3);
    expect(shopping.map((i) => i.name), contains('Kokosmilch light'));

    // Zweites Kochen: von den Linsen sind nur noch 250 g frei, sie werden nicht doppelt angeboten
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(testApp(db, launcher(PortionPlannerScreen(userid: user.uid, recipe: recipe, initialDate: DateTime(2026, 11, 5)))));
    await tester.tap(find.text('öffnen'));
    await pumpUntil(tester, find.text('Portionen'));
    for (var i = 0; i < 3; i++) {
      await tester.tap(find.byTooltip('Eine Portion mehr'));
      await tester.pump();
    }
    await tester.tap(find.widgetWithText(ElevatedButton, 'Weiter: Zutaten prüfen'));
    await pumpUntil(tester, find.text('nur 250 g da – Rest wird eingekauft')); // 500 g gebraucht
    await disposeApp(tester, db);
  });

  testWidgets('meal plan: hint for portions not planned yet, cook card with time and pantry; cooking books the reservation', (tester) async {
    useTallScreen(tester);
    final recipe = catalogRecipe('rote-linsen-dal')!;
    final d = today();
    late int lentilsId;
    final user = await seedDb(tester, db, () async {
      final u = await createTestUser(db);
      lentilsId = await InventoryRepository(db: db)
          .createItem(InventoryItem(userid: u.uid, kind: InventoryKind.food, name: 'Rote Linsen', quantity: 1, unit: 'kg'));
      final id = await repo().planBatch(
          uid: u.uid, recipe: recipe, cookDate: d, factor: 2, cookHour: 17, slots: [PortionSlot(d, Meal.dinner, 2), PortionSlot(d, Meal.lunch, 1)]);
      final checks = await repo().checkPantry(u.uid, recipe, 2, batchId: id);
      await repo().saveIngredientPlan(u.uid, id, checks, [for (final c in checks) c.inPantry]);
      return u;
    });
    await tester.pumpWidget(testApp(db, MealPlanScreen(user: user)));
    await pumpUntil(tester, find.text('Rote-Linsen-Dal: 3 Portionen noch nicht eingeplant'));
    expect(find.text('17:00 Uhr · 6 Portionen · 1 aus dem Vorrat'), findsOneWidget);

    await tester.tap(find.text('Verteilen'));
    await pumpUntil(tester, find.text('Koch-Block ändern'));
    expect(find.text('Noch 3 Portionen frei – kannst du auch später verteilen'), findsOneWidget);
    await pageBack(tester);
    await pumpUntil(tester, find.text('Gekocht'));

    // Kochen: die reservierten 500 g Linsen (0,5 kg) sind schon eingetragen
    await tester.tap(find.text('Gekocht'));
    await pumpUntil(tester, find.text('Als gekocht eintragen'));
    await pumpUntil(tester, find.text('0,5')); // Vorrat wird beim Öffnen geladen
    expect(find.text('0,5'), findsOneWidget);
    await tester.ensureVisible(find.text('Als gekocht eintragen'));
    await tester.tap(find.text('Als gekocht eintragen'));
    await pumpUntil(tester, find.textContaining('als gekocht eingetragen'));

    final batch = (await readDb(tester, () => repo().getBatches(user.uid, d, d))).single;
    expect(batch.cooked, isTrue);
    expect(await readDb(tester, () => repo().reservationsOf(batch.id!)), isEmpty);
    final lentils = (await readDb(tester, () => InventoryRepository(db: db).getItems(user.uid))).firstWhere((i) => i.id == lentilsId);
    expect(lentils.quantity, closeTo(0.5, 1e-9)); // 500 g abgebucht
    await disposeApp(tester, db);
  });

  testWidgets('a single food is planned via the nutrition-label photo, then logged as eaten', (tester) async {
    useTallScreen(tester);
    FlutterSecureStorage.setMockInitialValues({});
    final user = await seedDb(tester, db, () => createTestUser(db));
    await tester.pumpWidget(testApp(
      db,
      MealPlanScreen(user: user),
      foodPhotos: FakeFoodPhotoScanner(lines: const ['Nährwerte pro 100 g', 'Brennwert 1550 kJ / 370 kcal', 'Fett 7 g', 'Kohlenhydrate 59 g', 'Eiweiß 13 g']),
    ));
    await pumpUntil(tester, find.text('Frühstück'));
    await tester.tap(find.byTooltip('Frühstück: Gericht hinzufügen'));
    await pumpUntil(tester, find.text('Lebensmittel').hitTestable());
    await tester.tap(find.text('Lebensmittel'));
    await pumpUntil(tester, find.text('Frühstück einplanen'));
    await pumpUntil(tester, find.text('Foto').hitTestable());
    await tester.tap(find.text('Foto'));
    await pumpUntil(tester, find.text('Nährwerttabelle fotografieren').hitTestable());
    await tester.tap(find.text('Nährwerttabelle fotografieren'));
    await pumpUntil(tester, find.text('370'));
    await enterInCard(tester, 'Name', 'Haferflocken Bio');
    await tester.ensureVisible(find.text('Hinzufügen'));
    await tester.tap(find.text('Hinzufügen'));
    await pumpUntil(tester, find.text('Eintragen'));
    await tester.enterText(find.descendant(of: find.byType(AlertDialog), matching: find.byType(TextFormField)), '60');
    await tester.tap(find.text('Eintragen'));
    await pumpUntil(tester, find.text('60 g · 222 kcal')); // Sheet zu, Essensplan neu geladen
    expect(find.text('Haferflocken Bio'), findsOneWidget);

    // Nichts ist schon im Ernährungsprotokoll – erst „Als gegessen eintragen“
    final nutrition = NutritionRepository(db: db, inventory: InventoryRepository(db: db));
    expect((await readDb(tester, () => nutrition.getDay(user.uid, today()))).entries, isEmpty);
    await tester.tap(find.text('Haferflocken Bio'));
    await pumpUntil(tester, find.text('Als gegessen eintragen').hitTestable());
    await tester.tap(find.text('Als gegessen eintragen'));
    await pumpUntil(tester, find.byIcon(Icons.check_circle_rounded));
    final day = await readDb(tester, () => nutrition.getDay(user.uid, today()));
    expect((day.entries.single.name, day.entries.single.grams, day.entries.single.meal), ('Haferflocken Bio', 60.0, Meal.breakfast));
    await disposeApp(tester, db);
  });

  testWidgets('a dish without cooking is planned with portions - no batch, appointment, pantry or shopping', (tester) async {
    useTallScreen(tester);
    final user = await seedDb(tester, db, () => createTestUser(db));
    await tester.pumpWidget(testApp(db, MealPlanScreen(user: user)));
    await pumpUntil(tester, find.text('Mittagessen'));
    await tester.tap(find.byTooltip('Mittagessen: Gericht hinzufügen'));
    await pumpUntil(tester, find.text('Gericht ohne Kochen').hitTestable());
    await tester.tap(find.text('Gericht ohne Kochen'));
    await pumpUntil(tester, find.text('Rote-Linsen-Dal'));
    await tester.ensureVisible(find.text('Rote-Linsen-Dal'));
    await tester.tap(find.text('Rote-Linsen-Dal'));
    await pumpUntil(tester, find.text('Portionen'));
    await tester.enterText(find.descendant(of: find.byType(AlertDialog), matching: find.byType(TextFormField)), '2');
    await tester.tap(find.descendant(of: find.byType(AlertDialog), matching: find.text('Einplanen')));
    await pumpUntilGone(tester, find.byType(AlertDialog));
    await pumpUntil(tester, find.text('Rote-Linsen-Dal'));

    final planned = (await readDb(tester, () => repo().getDay(user.uid, today()))).single;
    expect((planned.name, planned.meal, planned.servings, planned.batchId), ('Rote-Linsen-Dal', Meal.lunch, 2.0, null));
    expect(await readDb(tester, () => repo().getBatches(user.uid, today(), today().add(const Duration(days: 7)))), isEmpty);
    final lists = ListsRepository(db: db, inventory: InventoryRepository(db: db));
    expect(await readDb(tester, () => lists.getShopping(user.uid)), isEmpty);
    expect(await readDb(tester, () => AppointmentRepository(db: db).getAllAppointments(user.uid)), isEmpty);
    expect(find.text('Kochen: Rote-Linsen-Dal'), findsNothing);
    await disposeApp(tester, db);
  });

  testWidgets('cook planning with both switches off: nothing reserved, nothing on the shopping list', (tester) async {
    useTallScreen(tester);
    final dal = catalogRecipe('rote-linsen-dal')!;
    final user = await seedDb(tester, db, () async {
      final u = await createTestUser(db);
      await InventoryRepository(db: db)
          .createItem(InventoryItem(userid: u.uid, kind: InventoryKind.food, name: 'Rote Linsen', quantity: 1, unit: 'kg'));
      return u;
    });
    await tester.pumpWidget(testApp(db, launcher(PortionPlannerScreen(userid: user.uid, recipe: dal, initialDate: today(), presetMeal: Meal.lunch))));
    await tester.tap(find.text('öffnen'));
    await pumpUntil(tester, find.widgetWithText(ElevatedButton, 'Weiter: Zutaten prüfen'));
    await tester.tap(find.widgetWithText(ElevatedButton, 'Weiter: Zutaten prüfen'));
    await pumpUntil(tester, find.text('Vorrat nutzen'));
    await tester.tap(find.text('Vorrat nutzen'));
    await tester.tap(find.text('Fehlendes auf die Einkaufsliste'));
    await tester.pump();
    expect(find.textContaining('nichts auf die Einkaufsliste'), findsOneWidget);
    await tester.tap(find.widgetWithText(ElevatedButton, 'Einplanen'));
    await pumpUntil(tester, find.text('öffnen'));

    final batch = (await readDb(tester, () => repo().getBatches(user.uid, today(), today().add(const Duration(days: 7))))).single;
    expect((batch.usePantry, batch.shop), (false, false));
    expect(await readDb(tester, () => repo().reservationsOf(batch.id!)), isEmpty);
    final lists = ListsRepository(db: db, inventory: InventoryRepository(db: db));
    expect(await readDb(tester, () => lists.getShopping(user.uid)), isEmpty);
    await disposeApp(tester, db);
  });

  testWidgets('editing a planned cooking: "Speichern" keeps the shopping list as it is', (tester) async {
    useTallScreen(tester);
    final dal = catalogRecipe('rote-linsen-dal')!;
    late MealBatch batch;
    final user = await seedDb(tester, db, () async {
      final u = await createTestUser(db);
      final r = repo();
      final id = await r.planBatch(uid: u.uid, recipe: dal, cookDate: today(), factor: 1, slots: [PortionSlot(today(), Meal.lunch, 3)]);
      final checks = await r.checkPantry(u.uid, dal, 1, batchId: id);
      await r.saveIngredientPlan(u.uid, id, checks, [for (final _ in checks) false]);
      batch = (await r.getBatch(id))!;
      return u;
    });
    final lists = ListsRepository(db: db, inventory: InventoryRepository(db: db));
    final before = [for (final i in await readDb(tester, () => lists.getShopping(user.uid))) '${i.name} ${i.amount}'];

    await tester.pumpWidget(testApp(db, launcher(PortionPlannerScreen(userid: user.uid, recipe: dal, initialDate: today(), batch: batch))));
    await tester.tap(find.text('öffnen'));
    await pumpUntil(tester, find.widgetWithText(OutlinedButton, 'Speichern'));
    await tester.tap(find.widgetWithText(OutlinedButton, 'Speichern'));
    await pumpUntil(tester, find.text('öffnen'));
    final after = [for (final i in await readDb(tester, () => lists.getShopping(user.uid))) '${i.name} ${i.amount}'];
    expect(after, before);
    await disposeApp(tester, db);
  });
}
