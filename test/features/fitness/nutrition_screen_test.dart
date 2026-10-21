import 'package:flutter/material.dart';
import 'package:frontend/features/meals/catalog/recipe_catalog.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/features/profile/widgets/ai_key_card.dart';
import 'package:frontend/features/fitness/services/meal_photo_ai.dart';
import 'package:frontend/core/models/app_exceptions.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'package:frontend/core/database/database.dart';
import 'package:frontend/features/auth/models/user.dart';
import 'package:frontend/features/fitness/models/nutrition.dart';
import 'package:frontend/features/fitness/repositories/nutrition_repository.dart';
import 'package:frontend/features/fitness/screens/food_editor_screen.dart';
import 'package:frontend/features/fitness/screens/nutrition_screen.dart';
import 'package:frontend/features/fitness/widgets/food_actions.dart';
import 'package:frontend/features/inventory/models/inventory_item.dart';
import 'package:frontend/features/inventory/repositories/inventory_repository.dart';
import 'package:frontend/features/inventory/screens/inventory_screen.dart';

import '../../helpers/test_app.dart';

void main() {
  late DatabaseService db;

  setUpAll(() => initializeDateFormatting('de_DE'));
  setUp(() => db = createTestDatabase());

  const skyr = {
    'product_name': 'Skyr Natur',
    'brands': 'Arla',
    'serving_quantity': 150,
    'nutriments': {'energy-kcal_100g': 60, 'proteins_100g': 11, 'carbohydrates_100g': 4, 'fat_100g': 0.2},
  };

  DateTime today() {
    final n = DateTime.now();
    return DateTime(n.year, n.month, n.day);
  }

  Future<NutritionDay> dayOf(WidgetTester tester, UserModel user) async =>
      readDb(tester, () => NutritionRepository(db: db).getDay(user.uid, today()));

  Future<void> confirmGrams(WidgetTester tester, String grams) async {
    await pumpUntil(tester, find.text('Eintragen'));
    await tester.enterText(find.descendant(of: find.byType(AlertDialog), matching: find.byType(TextFormField)), grams);
    await tester.tap(find.text('Eintragen'));
    await pumpUntilGone(tester, find.byType(AlertDialog));
  }

  testWidgets('create a new food and log it for breakfast', (tester) async {
    useTallScreen(tester);
    final user = await seedDb(tester, db, () => createTestUser(db));
    await tester.pumpWidget(testApp(db, NutritionScreen(user: user)));
    await pumpUntil(tester, find.text('Frühstück hinzufügen'));

    await tester.tap(find.text('Frühstück hinzufügen'));
    await pumpUntil(tester, find.text('Neues Lebensmittel'));
    await tester.tap(find.text('Neues Lebensmittel'));
    await pumpUntil(tester, find.byType(FoodEditorScreen));
    await enterInCard(tester, 'Name', 'Banane');
    await enterInCard(tester, 'Kalorien (kcal)', '89');
    await enterInCard(tester, 'Eiweiß (g)', '1,1');
    await tester.tap(find.text('Hinzufügen'));
    await confirmGrams(tester, '120');
    await pumpUntil(tester, find.text('Banane'));

    final day = await dayOf(tester, user);
    expect(day.entries.single.meal, Meal.breakfast);
    expect(day.total.kcal, closeTo(106.8, 0.01));
    await pumpUntil(tester, find.text('107')); // kcal im Ring (wird nach dem Neuladen gezeichnet)
    await disposeApp(tester, db);
  });

  testWidgets('scanning a known barcode fills name and nutrients from Open Food Facts', (tester) async {
    useTallScreen(tester);
    final user = await seedDb(tester, db, () => createTestUser(db));
    await tester.pumpWidget(testApp(
      db,
      NutritionScreen(user: user),
      barcodeScanner: const FakeBarcodeScanner('4001234567890'),
      openFoodFacts: fakeOpenFoodFacts({'4001234567890': skyr}),
    ));
    await pumpUntil(tester, find.text('Snacks hinzufügen'));

    await tester.tap(find.text('Snacks hinzufügen'));
    await pumpUntil(tester, find.text('Barcode'));
    await tester.tap(find.text('Barcode'));
    await confirmGrams(tester, '150');
    await pumpUntil(tester, find.text('Skyr Natur'));

    final day = await dayOf(tester, user);
    expect(day.total.protein, closeTo(16.5, 0.01));
    await disposeApp(tester, db);
  });

  testWidgets('an unknown barcode opens the editor with the barcode prefilled', (tester) async {
    useTallScreen(tester);
    final user = await seedDb(tester, db, () => createTestUser(db));
    await tester.pumpWidget(testApp(db, NutritionScreen(user: user), barcodeScanner: const FakeBarcodeScanner('999')));
    await pumpUntil(tester, find.text('Mittagessen hinzufügen'));

    await tester.tap(find.text('Mittagessen hinzufügen'));
    await pumpUntil(tester, find.text('Barcode'));
    await tester.tap(find.text('Barcode'));
    await pumpUntil(tester, find.text('Produkt unbekannt'));
    await tester.tap(find.text('Nährwerte selbst eintragen'));
    await pumpUntil(tester, find.byType(FoodEditorScreen));

    expect(find.text('Barcode 999'), findsOneWidget);
    await disposeApp(tester, db);
  });

  testWidgets('offline: an unknown barcode is linked to a standard product and found offline next time', (tester) async {
    useTallScreen(tester);
    final user = await seedDb(tester, db, () => createTestUser(db));
    await tester.pumpWidget(testApp(
      db,
      NutritionScreen(user: user),
      barcodeScanner: const FakeBarcodeScanner('4061458000000'),
      openFoodFacts: offlineOpenFoodFacts(),
    ));
    await pumpUntil(tester, find.text('Frühstück hinzufügen'));
    await tester.tap(find.text('Frühstück hinzufügen'));
    await pumpUntil(tester, find.text('Barcode'));
    await tester.tap(find.text('Barcode'));
    await pumpUntil(tester, find.text('Keine Verbindung'));

    await tester.tap(find.text('Vorhandenem Lebensmittel zuordnen'));
    await pumpUntil(tester, find.text('Lebensmittel zuordnen'));
    await tester.enterText(find.byType(TextField).last, 'haferfl');
    await pumpUntil(tester, find.text('Haferflocken'));
    await tester.tap(find.text('Haferflocken').last);
    await confirmGrams(tester, '60');
    await pumpUntil(tester, find.text('Haferflocken'));

    final repo = NutritionRepository(db: db);
    final linked = await readDb(tester, () => repo.findByBarcode(user.uid, '4061458000000'));
    expect(linked!.name, 'Haferflocken');
    expect(linked.brand, isNull);
    expect(linked.per100.kcal, closeTo(372, 0.1));
    final day = await dayOf(tester, user);
    expect(day.entries.single.grams, 60);

    // Zweiter Scan: sofort aus der eigenen Datenbank, ohne Internet
    await tester.tap(find.text('Frühstück hinzufügen'));
    await pumpUntil(tester, find.text('Barcode'));
    await tester.tap(find.text('Barcode'));
    await confirmGrams(tester, '40');
    expect(find.text('Keine Verbindung'), findsNothing);
    for (var i = 0; i < 50 && (await dayOf(tester, user)).entries.length < 2; i++) {
      await settleDb(tester);
    }
    expect((await dayOf(tester, user)).entries.map((e) => e.grams), unorderedEquals([60, 40]));
    await disposeApp(tester, db);
  });

  testWidgets('drink water with quick buttons and log drinks in ml', (tester) async {
    useTallScreen(tester);
    final user = await seedDb(tester, db, () => createTestUser(db));
    await tester.pumpWidget(testApp(db, NutritionScreen(user: user)));
    await pumpUntil(tester, find.text('Getrunken'));
    expect(find.text('0 ml / 2,5 l'), findsOneWidget);

    await tester.tap(find.text('+ 250 ml'));
    await pumpUntil(tester, find.text('250 ml / 2,5 l'));
    await tester.tap(find.text('+ 500 ml'));
    await pumpUntil(tester, find.text('750 ml / 2,5 l'));

    await tester.ensureVisible(find.text('Getränke hinzufügen'));
    await tester.tap(find.text('Getränke hinzufügen'));
    await pumpUntil(tester, find.byType(TextField));
    await tester.enterText(find.byType(TextField), 'apfelschorle');
    await pumpUntil(tester, find.text('Apfelschorle'));
    await tester.tap(find.text('Apfelschorle'));
    await pumpUntil(tester, find.text('Menge in ml'));
    await confirmGrams(tester, '330');
    await pumpUntil(tester, find.text('1,1 l / 2,5 l'));

    final day = await dayOf(tester, user);
    expect(day.drankMl, 1080);
    expect(day.total.kcal, closeTo(79.2, 0.01));
    await disposeApp(tester, db);
  });

  testWidgets('standard products are ready to pick without entering nutrients', (tester) async {
    useTallScreen(tester);
    final user = await seedDb(tester, db, () => createTestUser(db));
    await tester.pumpWidget(testApp(db, NutritionScreen(user: user)));
    await pumpUntil(tester, find.text('Mittagessen hinzufügen'));
    await tester.tap(find.text('Mittagessen hinzufügen'));
    await pumpUntil(tester, find.byType(TextField));
    await tester.enterText(find.byType(TextField), 'kichererbsen');
    await pumpUntil(tester, find.text('Kichererbsen (Dose, abgetropft)'));
    expect(find.textContaining('Standardprodukt'), findsWidgets);
    await tester.tap(find.text('Kichererbsen (Dose, abgetropft)'));
    await confirmGrams(tester, '130');
    await pumpUntil(tester, find.text('Kichererbsen (Dose, abgetropft)'));

    final day = await dayOf(tester, user);
    expect(day.total.kcal, closeTo(156, 0.1));
    await disposeApp(tester, db);
  });

  testWidgets('eating from the pantry logs the meal and reduces the stock', (tester) async {
    useTallScreen(tester);
    late int itemId;
    final user = await seedDb(tester, db, () async {
      final user = await createTestUser(db);
      final food = await NutritionRepository(db: db)
          .saveFood(Food(userid: user.uid, name: 'Haferflocken', per100: const Macros(kcal: 370), servingGrams: 50));
      itemId = await InventoryRepository(db: db).createItem(InventoryItem(
          userid: user.uid, kind: InventoryKind.food, name: 'Haferflocken', quantity: 500, unit: 'g', foodId: food.id));
      return user;
    });
    await tester.pumpWidget(testApp(db, NutritionScreen(user: user)));
    await pumpUntil(tester, find.text('Frühstück hinzufügen'));

    await tester.tap(find.text('Frühstück hinzufügen'));
    await pumpUntil(tester, find.text('Aus Vorrat (1)', skipOffstage: false));
    await tester.ensureVisible(find.text('Aus Vorrat (1)', skipOffstage: false)); // Chip-Leiste scrollt (Sheet ist höchstens 640 dp breit)
    await tester.pumpAndSettle();
    await tester.tap(find.text('Aus Vorrat (1)'));
    await tester.pump();
    await tester.tap(find.textContaining('Vorrat: 500'));
    await confirmGrams(tester, '80');
    await pumpUntil(tester, find.text('296 kcal'));

    final stock = (await readDb(tester, () => InventoryRepository(db: db).getItem(itemId)))!;
    expect(stock.quantity, 420);
    await disposeApp(tester, db);
  });

  testWidgets('daily goals can be edited', (tester) async {
    useTallScreen(tester);
    final user = await seedDb(tester, db, () => createTestUser(db));
    await tester.pumpWidget(testApp(db, NutritionScreen(user: user)));
    await pumpUntil(tester, find.byTooltip('Tagesziele'));

    await tester.tap(find.byTooltip('Tagesziele'));
    await pumpUntil(tester, find.widgetWithText(TextFormField, 'Kalorien (kcal)'));
    await tester.enterText(find.widgetWithText(TextFormField, 'Kalorien (kcal)'), '2800');
    await tester.tap(find.widgetWithText(ElevatedButton, 'Speichern'));
    await pumpUntil(tester, find.text('von 2800 kcal'));
    await disposeApp(tester, db);
  });

  testWidgets('pantry: barcode in the editor creates an item linked to the food', (tester) async {
    useTallScreen(tester);
    final user = await seedDb(tester, db, () => createTestUser(db));
    await tester.pumpWidget(testApp(
      db,
      Builder(
        builder: (context) => InventoryScreen(
          user: user,
          kinds: const {InventoryKind.food, InventoryKind.drink},
          addKind: InventoryKind.food,
          onScanBarcode: () => scanPantryItem(context, user.uid),
        ),
      ),
      barcodeScanner: const FakeBarcodeScanner('4001234567890'),
      openFoodFacts: fakeOpenFoodFacts({'4001234567890': skyr}),
    ));
    await pumpUntil(tester, find.text('Dein Vorrat ist leer'));

    await tester.tap(find.text('Artikel'));
    await pumpUntil(tester, find.byTooltip('Barcode scannen'));
    await tester.tap(find.byTooltip('Barcode scannen'));
    await pumpUntil(tester, find.widgetWithText(TextFormField, 'Skyr Natur'));
    await tester.ensureVisible(find.text('Hinzufügen'));
    await tester.tap(find.text('Hinzufügen'));
    await pumpUntil(tester, find.text('Skyr Natur'));

    final item = (await readDb(tester, () => InventoryRepository(db: db).getItems(user.uid))).single;
    expect(item.barcode, '4001234567890');
    expect(item.brand, 'Arla');
    expect(item.foodId, isNotNull);
    await disposeApp(tester, db);
  });

  testWidgets('nutrition day renders on a 360 dp phone without overflow', (tester) async {
    tester.view.physicalSize = const Size(360, 780);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final user = await seedDb(tester, db, () async {
      final user = await createTestUser(db);
      final repo = NutritionRepository(db: db);
      final food = await repo.saveFood(Food(userid: user.uid, name: 'Ein sehr langer Lebensmittelname mit Marke', per100: const Macros(kcal: 500)));
      await repo.addEntry(uid: user.uid, food: food, grams: 900, meal: Meal.lunch, date: today());
      return user;
    });
    await tester.pumpWidget(testApp(db, NutritionScreen(user: user)));
    await pumpUntil(tester, find.textContaining('über dem Ziel'));

    expect(tester.takeException(), isNull);
    await disposeApp(tester, db);
  });

  group('dishes', () {
    Future<void> openDish(WidgetTester tester, String choice) async {
      await tester.tap(find.text('Abendessen hinzufügen'));
      await pumpUntil(tester, find.text('Gericht').hitTestable());
      await tester.tap(find.text('Gericht'));
      await pumpUntil(tester, find.text(choice).hitTestable());
      await tester.tap(find.text(choice));
    }

    testWidgets('an own dish is logged in portions and offered again in the search', (tester) async {
      useTallScreen(tester);
      final user = await seedDb(tester, db, () => createTestUser(db));
      await tester.pumpWidget(testApp(db, NutritionScreen(user: user)));
      await pumpUntil(tester, find.text('Abendessen hinzufügen'));
      await openDish(tester, 'Eigenes Gericht');
      await pumpUntil(tester, find.text('Neues Gericht'));
      await tester.enterText(find.widgetWithText(TextFormField, 'Name'), 'Pizza vom Italiener');
      await tester.enterText(find.widgetWithText(TextFormField, 'kcal pro Portion'), '900');
      await tester.enterText(find.widgetWithText(TextFormField, 'Portionen'), '1,5');
      await tester.ensureVisible(find.text('Eintragen'));
      await tester.tap(find.text('Eintragen'));
      await pumpUntil(tester, find.textContaining('1,5 Portionen'));
      expect((await dayOf(tester, user)).total.kcal, closeTo(1350, 0.01));

      // Nächstes Mal: in der Suche, gefragt wird nach Portionen
      await tester.tap(find.text('Abendessen hinzufügen'));
      await pumpUntil(tester, find.text('Gericht').hitTestable());
      await tester.enterText(find.widgetWithText(TextField, 'Lebensmittel suchen'), 'pizza');
      await pumpUntil(tester, find.textContaining('je Portion'));
      await tester.tap(find.text('Pizza vom Italiener').last);
      await pumpUntil(tester, find.text('Portionen'));
      await confirmGrams(tester, '1');
      await pumpUntilGone(tester, find.byType(BottomSheet));
      expect((await dayOf(tester, user)).total.kcal, closeTo(2250, 0.01));
      await disposeApp(tester, db);
    });

    testWidgets('a recipe is logged with its nutrients per portion', (tester) async {
      useTallScreen(tester);
      final user = await seedDb(tester, db, () => createTestUser(db));
      await tester.pumpWidget(testApp(db, NutritionScreen(user: user)));
      await pumpUntil(tester, find.text('Abendessen hinzufügen'));
      await openDish(tester, 'Aus Rezept');
      await pumpUntil(tester, find.text('Rote-Linsen-Dal'));
      await tester.ensureVisible(find.text('Rote-Linsen-Dal'));
      await tester.tap(find.text('Rote-Linsen-Dal'));
      await pumpUntil(tester, find.text('Portionen'));
      await confirmGrams(tester, '2');
      await pumpUntil(tester, find.textContaining('2 Portionen'));
      final dal = catalogRecipe('rote-linsen-dal')!;
      final entry = (await dayOf(tester, user)).entries.single;
      expect((entry.name, entry.meal, entry.portions), ('Rote-Linsen-Dal', Meal.dinner, 2.0));
      expect(entry.macros.kcal, closeTo(dal.perServing.kcal * 2, 0.01));
      await disposeApp(tester, db);
    });
  });

  group('photo', () {
    const label = [
      'Nährwerte pro 100 g pro Portion (40 g)',
      'Brennwert 1550 kJ / 370 kcal',
      'Fett 7,0 g',
      'Kohlenhydrate 59 g',
      'davon Zucker 1,0 g',
      'Eiweiß 13 g',
    ];

    Future<void> openPhoto(WidgetTester tester, String option) async {
      await tester.tap(find.text('Frühstück hinzufügen'));
      await pumpUntil(tester, find.text('Foto').hitTestable());
      await tester.tap(find.text('Foto'));
      await pumpUntil(tester, find.text(option).hitTestable());
      await tester.tap(find.text(option));
    }

    testWidgets('nutrition label: values per 100 g are read, the portion is suggested, 40 g are logged', (tester) async {
      useTallScreen(tester);
      FlutterSecureStorage.setMockInitialValues({});
      final user = await seedDb(tester, db, () => createTestUser(db));
      await tester.pumpWidget(testApp(db, NutritionScreen(user: user), foodPhotos: FakeFoodPhotoScanner(lines: label)));
      await pumpUntil(tester, find.text('Frühstück hinzufügen'));
      await openPhoto(tester, 'Nährwerttabelle fotografieren');

      await pumpUntil(tester, find.byType(FoodEditorScreen));
      expect(find.textContaining('von der Nährwerttabelle'), findsOneWidget);
      expect(find.text('370'), findsOneWidget);
      expect(find.text('13'), findsOneWidget);
      expect(find.text('59'), findsOneWidget);
      expect(find.text('7'), findsOneWidget);
      await enterInCard(tester, 'Name', 'Haferflocken Marke X');
      await tester.ensureVisible(find.text('Hinzufügen'));
      await tester.tap(find.text('Hinzufügen'));
      await pumpUntil(tester, find.text('Eintragen'));
      expect(find.text('40'), findsOneWidget); // Portion von der Verpackung vorgeschlagen
      await tester.tap(find.text('Eintragen'));
      await pumpUntil(tester, find.text('Haferflocken Marke X'));

      final day = await dayOf(tester, user);
      expect(day.entries.single.grams, 40);
      expect(day.total.kcal, closeTo(148, 0.01));
      expect(day.total.protein, closeTo(5.2, 0.01));
      await disposeApp(tester, db);
    });

    testWidgets('dish photo: the AI estimate is shown as an estimate and logged with the guessed amount', (tester) async {
      useTallScreen(tester);
      FlutterSecureStorage.setMockInitialValues({'anthropic_api_key': 'sk-ant-test'});
      final ai = FakeMealPhotoAi(
        result: const MealEstimate(
          name: 'Spaghetti Bolognese',
          grams: 400,
          kcal: 600,
          protein: 28,
          carbs: 80,
          fat: 20,
          components: ['250 g Spaghetti', '150 g Soße'],
        ),
      );
      final user = await seedDb(tester, db, () => createTestUser(db));
      await tester.pumpWidget(testApp(db, NutritionScreen(user: user), mealPhotoAi: ai));
      await pumpUntil(tester, find.text('Frühstück hinzufügen'));
      await openPhoto(tester, 'Gericht fotografieren');

      await pumpUntil(tester, find.byType(FoodEditorScreen));
      expect(find.textContaining('Geschätzt aus dem Foto'), findsOneWidget);
      expect(find.textContaining('250 g Spaghetti'), findsOneWidget);
      expect(find.text('150'), findsOneWidget); // 600 kcal / 400 g → 150 kcal pro 100 g
      await tester.ensureVisible(find.text('Hinzufügen'));
      await tester.tap(find.text('Hinzufügen'));
      await confirmGrams(tester, '0,75'); // Portionen: doch nur 300 der geschätzten 400 g gegessen
      await pumpUntil(tester, find.text('Spaghetti Bolognese'));

      final day = await dayOf(tester, user);
      expect(day.total.kcal, closeTo(450, 0.01));
      expect(ai.calls, 1);
      final foods = await readDb(tester, () => NutritionRepository(db: db, inventory: InventoryRepository(db: db)).searchFoods(user.uid, search: 'spaghetti'));
      expect(foods.map((f) => f.name), contains('Spaghetti Bolognese')); // später in der Suche
      expect(foods.firstWhere((f) => f.name == 'Spaghetti Bolognese').isDish, isTrue); // als Gericht gemerkt
      await disposeApp(tester, db);
    });

    testWidgets('without an API key the AI option explains where to add one; nothing is sent', (tester) async {
      useTallScreen(tester);
      FlutterSecureStorage.setMockInitialValues({});
      final ai = FakeMealPhotoAi();
      final user = await seedDb(tester, db, () => createTestUser(db));
      await tester.pumpWidget(testApp(db, NutritionScreen(user: user), mealPhotoAi: ai));
      await pumpUntil(tester, find.text('Frühstück hinzufügen'));
      await openPhoto(tester, 'Gericht fotografieren');
      await pumpUntil(tester, find.text('Zum Profil').hitTestable());
      expect(find.textContaining('API-Schlüssel'), findsOneWidget);
      await tester.tap(find.text('Zum Profil'));
      await pumpUntil(tester, find.text('KI-Schätzung (Fotos)'));
      expect(ai.calls, 0);
      await disposeApp(tester, db);
    });

    testWidgets('an unreadable label offers manual entry; AI errors are shown', (tester) async {
      useTallScreen(tester);
      FlutterSecureStorage.setMockInitialValues({'anthropic_api_key': 'sk-ant-test'});
      final user = await seedDb(tester, db, () => createTestUser(db));
      await tester.pumpWidget(testApp(
        db,
        NutritionScreen(user: user),
        foodPhotos: FakeFoodPhotoScanner(lines: const ['Zutaten: Hafer']),
        mealPhotoAi: FakeMealPhotoAi(error: const UserFacingException('Keine Internetverbindung – die KI-Schätzung braucht Internet.')),
      ));
      await pumpUntil(tester, find.text('Frühstück hinzufügen'));
      await openPhoto(tester, 'Nährwerttabelle fotografieren');
      await pumpUntil(tester, find.text('Manuell eingeben').hitTestable());
      expect(find.text('Auf dem Foto wurde keine Nährwerttabelle erkannt.'), findsOneWidget);
      await tester.tap(find.text('Manuell eingeben'));
      await pumpUntil(tester, find.byType(FoodEditorScreen));
      await pageBack(tester);
      await pumpUntil(tester, find.text('Foto').hitTestable());

      await tester.tap(find.text('Foto'));
      await pumpUntil(tester, find.text('Gericht fotografieren').hitTestable());
      await tester.tap(find.text('Gericht fotografieren'));
      await pumpUntil(tester, find.textContaining('Keine Internetverbindung'));
      expect(find.byType(FoodEditorScreen), findsNothing);
      await tester.tap(find.text('Schließen'));
      await pumpUntil(tester, find.text('Foto').hitTestable());
      await disposeApp(tester, db);
    });
  });

  testWidgets('profile: the API key is checked before it is saved and can be removed', (tester) async {
    useTallScreen(tester);
    FlutterSecureStorage.setMockInitialValues({});
    final user = await seedDb(tester, db, () => createTestUser(db));
    await tester.pumpWidget(testApp(db, const Scaffold(body: SingleChildScrollView(child: AiKeyCard())), mealPhotoAi: FakeMealPhotoAi(keyProblem: 'Der Schlüssel wurde abgelehnt.')));
    await pumpUntil(tester, find.text('Testen und speichern'));
    await tester.enterText(find.byType(TextField), 'sk-ant-falsch');
    await tester.tap(find.text('Testen und speichern'));
    await pumpUntil(tester, find.textContaining('abgelehnt'));
    expect(await const AiKeyStore().read(), isNull);

    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(testApp(db, const Scaffold(body: SingleChildScrollView(child: AiKeyCard())), mealPhotoAi: FakeMealPhotoAi()));
    await pumpUntil(tester, find.text('Testen und speichern'));
    await tester.enterText(find.byType(TextField), 'sk-ant-richtig');
    await tester.tap(find.text('Testen und speichern'));
    await pumpUntil(tester, find.text('eingerichtet'));
    expect(await const AiKeyStore().read(), 'sk-ant-richtig');
    await tester.tap(find.text('Schlüssel entfernen'));
    await pumpUntil(tester, find.text('Testen und speichern'));
    expect(await const AiKeyStore().read(), isNull);
    expect(user.uid, isNotNull);
    await disposeApp(tester, db);
  });
}
