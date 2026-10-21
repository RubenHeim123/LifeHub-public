import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'package:frontend/core/database/database.dart';
import 'package:frontend/features/fitness/models/nutrition.dart';
import 'package:frontend/features/fitness/repositories/nutrition_repository.dart';
import 'package:frontend/core/ui/app_ui.dart';
import 'package:frontend/features/inventory/models/inventory_item.dart';
import 'package:frontend/features/inventory/repositories/inventory_repository.dart';
import 'package:frontend/features/inventory/screens/inventory_screen.dart';
import 'package:frontend/features/lists/models/lists.dart';
import 'package:frontend/features/lists/repositories/lists_repository.dart';
import 'package:frontend/features/lists/screens/gifts_screen.dart';
import 'package:frontend/features/lists/screens/shopping_list_screen.dart';

import '../../helpers/test_app.dart';

void main() {
  late DatabaseService db;

  setUpAll(() => initializeDateFormatting('de_DE'));
  setUp(() => db = createTestDatabase());

  ListsRepository lists() => ListsRepository(db: db, inventory: InventoryRepository(db: db));

  testWidgets('shopping list: one list with amounts, check off, move into the pantry', (tester) async {
    useTallScreen(tester);
    final user = await seedDb(tester, db, () => createTestUser(db));
    await tester.pumpWidget(testApp(db, ShoppingListScreen(user: user)));
    await pumpUntil(tester, find.text('Alles eingekauft'));

    // + öffnet das Formular mit allen Feldern; Menge im eigenen Feld
    await tester.tap(find.text('Artikel'));
    await pumpUntil(tester, find.text('Auf die Einkaufsliste'));
    expect(find.text('Abteilung'), findsOneWidget);
    await tester.enterText(find.widgetWithText(TextFormField, 'Was?'), 'Magerquark');
    await tester.enterText(find.widgetWithText(TextFormField, 'Menge (optional)'), '600g');
    await tester.tap(find.widgetWithText(ElevatedButton, 'Hinzufügen'));
    await pumpUntil(tester, find.text('600 g  Magerquark', findRichText: true));
    // Menge direkt im Namen; die Abteilung wird erraten
    await tester.tap(find.text('Artikel'));
    await pumpUntil(tester, find.text('Auf die Einkaufsliste'));
    await tester.enterText(find.widgetWithText(TextFormField, 'Was?'), '4x Deo');
    await tester.tap(find.widgetWithText(ElevatedButton, 'Hinzufügen'));
    await pumpUntil(tester, find.text('4×  Deo', findRichText: true));

    expect(find.text('600 g  Magerquark', findRichText: true), findsOneWidget);
    expect(find.text('4×  Deo', findRichText: true), findsOneWidget);
    expect(find.text('Lebensmittel'), findsNothing); // Liste ohne Abteilungen
    final saved = await readDb(tester, () => lists().getShopping(user.uid));
    expect(saved.map((i) => '${i.quantityLabel}|${i.name}|${i.category.name}'), ['600 g|Magerquark|food', '4×|Deo|care']);

    // Abhaken fragt immer, was gekauft wurde (hier ohne Packungsgrößen: Menge selbst eintragen)
    await tester.tap(find.byType(AppCheck).first);
    await pumpUntil(tester, find.text('Was hast du gekauft?'));
    expect(find.widgetWithText(TextField, '600'), findsOneWidget); // vorbelegt mit der geplanten Menge
    await tester.enterText(find.byKey(const Key('boughtAmount')), '500');
    await tester.tap(find.widgetWithText(ElevatedButton, 'Abhaken'));
    await pumpUntil(tester, find.textContaining('ist jetzt im Vorrat – 500 g'));

    final pantry = await readDb(tester, () => InventoryRepository(db: db).getItems(user.uid));
    expect(pantry.single.name, 'Magerquark');
    expect(pantry.single.kind, InventoryKind.food);
    expect(pantry.single.quantity, 500);
    expect(pantry.single.unit, 'g');
    expect(pantry.single.fromShopping, isTrue);
    expect((await readDb(tester, () => lists().getShopping(user.uid))).single.name, 'Deo');
    await disposeApp(tester, db);
  });

  testWidgets('shopping list: buying 500 g asks for the pack size and stores 600 g', (tester) async {
    useTallScreen(tester);
    final user = await seedDb(tester, db, () async {
      final u = await createTestUser(db);
      await NutritionRepository(db: db, inventory: InventoryRepository(db: db))
          .saveFood(Food(userid: u.uid, name: 'Hackfleisch', packSizes: const [400, 600]));
      await lists().addToList(u.uid, name: 'Hackfleisch', amount: 500, unit: 'g', label: 'Bolognese', recipeKey: 'bolo');
      return u;
    });
    await tester.pumpWidget(testApp(db, ShoppingListScreen(user: user)));
    await pumpUntil(tester, find.text('500 g  Hackfleisch', findRichText: true));
    expect(find.text('Packungen: 1× 600 g'), findsOneWidget);

    // Detailansicht: wofür und welche Packungen
    await tester.tap(find.text('500 g  Hackfleisch', findRichText: true));
    await pumpUntil(tester, find.text('Bolognese'));
    expect(find.text('Erhältlich in 400 g, 600 g'), findsOneWidget);
    await tester.tapAt(const Offset(10, 10)); // schließen
    await pumpUntilGone(tester, find.text('Bolognese'));

    await tester.tap(find.byType(AppCheck));
    await pumpUntil(tester, find.text('Was hast du gekauft?'));
    expect(find.text('In den Vorrat: 600 g'), findsOneWidget);
    await tester.tap(find.widgetWithText(ElevatedButton, 'Abhaken'));
    await pumpUntil(tester, find.textContaining('ist jetzt im Vorrat – 600 g'));

    final pantry = await readDb(tester, () => InventoryRepository(db: db).getItems(user.uid));
    expect((pantry.single.name, pantry.single.quantity, pantry.single.unit), ('Hackfleisch', 600.0, 'g'));
    expect(pantry.single.foodId, isNotNull);
    await disposeApp(tester, db);
  });

  testWidgets('shopping list: done items collapse and can be cleared', (tester) async {
    useTallScreen(tester);
    final user = await seedDb(tester, db, () async {
      final u = await createTestUser(db);
      await lists().saveShopping(ShoppingItem(userid: u.uid, name: 'Spülmittel', category: ShoppingCategory.household));
      return u;
    });
    await tester.pumpWidget(testApp(db, ShoppingListScreen(user: user)));
    await pumpUntil(tester, find.text('Spülmittel'));
    await tester.tap(find.byType(AppCheck));
    await pumpUntil(tester, find.text('Erledigt (1)'));
    expect(find.text('Spülmittel'), findsNothing); // eingeklappt
    await tester.tap(find.text('Erledigte entfernen'));
    await pumpUntil(tester, find.textContaining('1 erledigte Artikel entfernt'));
    expect(await readDb(tester, () => lists().getShopping(user.uid)), isEmpty);
    await disposeApp(tester, db);
  });

  testWidgets('shopping list: swipe to delete and undo', (tester) async {
    useTallScreen(tester);
    final user = await seedDb(tester, db, () async {
      final u = await createTestUser(db);
      await lists().saveShopping(ShoppingItem(userid: u.uid, name: 'Haferflocken', quantity: '1 kg'));
      return u;
    });
    await tester.pumpWidget(testApp(db, ShoppingListScreen(user: user)));
    await pumpUntil(tester, find.text('1 kg  Haferflocken', findRichText: true));

    await tester.drag(find.textContaining('Haferflocken', findRichText: true), const Offset(-400, 0));
    await pumpUntil(tester, find.text('Löschen'));
    await tester.tap(find.text('Löschen'));
    await pumpUntil(tester, find.text('„Haferflocken“ gelöscht'));
    expect(await readDb(tester, () => lists().getShopping(user.uid)), isEmpty);

    await tester.tap(find.text('Rückgängig'));
    await pumpUntil(tester, find.textContaining('Haferflocken', findRichText: true));
    expect((await readDb(tester, () => lists().getShopping(user.uid))).single.quantity, '1 kg');
    await disposeApp(tester, db);
  });

  testWidgets('gifts: create a list for a person, add an idea, mark it bought, put it on the shopping list', (tester) async {
    useTallScreen(tester);
    final user = await seedDb(tester, db, () => createTestUser(db));
    await tester.pumpWidget(testApp(db, GiftsScreen(user: user)));
    await pumpUntil(tester, find.text('Noch keine Geschenkelisten'));

    await tester.tap(find.text('Liste'));
    await pumpUntil(tester, find.text('Neue Geschenkeliste'));
    await tester.enterText(find.widgetWithText(TextFormField, 'Für wen?'), 'Schwester');
    expect(find.widgetWithText(TextFormField, 'Notiz (optional)'), findsOneWidget);
    await tester.tap(find.widgetWithText(ElevatedButton, 'Speichern'));
    await pumpUntil(tester, find.text('Schwester · Geburtstag'));

    await tester.tap(find.text('Idee'));
    await pumpUntil(tester, find.text('Neue Geschenkidee'));
    await tester.enterText(find.widgetWithText(TextFormField, 'Idee'), 'Parfüm');
    await tester.enterText(find.widgetWithText(TextFormField, 'Preis in € (optional)'), '45');
    await tester.tap(find.widgetWithText(ElevatedButton, 'Speichern'));
    await pumpUntilGone(tester, find.text('Neue Geschenkidee'));
    await pumpUntil(tester, find.text('Parfüm'));
    expect(find.text('Ideen'), findsOneWidget);

    await tester.tap(find.byTooltip('Auf die Einkaufsliste'));
    await pumpUntil(tester, find.textContaining('steht auf der Einkaufsliste'));
    await tester.tap(find.text('Gekauft'));
    await pumpUntil(tester, find.text('Verschenkt'));

    await pageBack(tester);
    await pumpUntil(tester, find.textContaining('0 Ideen'));
    expect(find.textContaining('45,00'), findsOneWidget);

    final shopping = await readDb(tester, () => lists().getShopping(user.uid));
    expect(shopping.single.quantity, 'für Schwester');
    await disposeApp(tester, db);
  });

  testWidgets('wardrobe: add perfume as care item', (tester) async {
    useTallScreen(tester);
    final user = await seedDb(tester, db, () => createTestUser(db));
    await tester.pumpWidget(testApp(
      db,
      InventoryScreen(
        user: user,
        kinds: const {InventoryKind.clothing, InventoryKind.accessory, InventoryKind.care},
        addKind: InventoryKind.clothing,
        addKinds: const [InventoryKind.clothing, InventoryKind.accessory, InventoryKind.care],
        gridByDefault: true,
      ),
    ));
    await pumpUntil(tester, find.text('Artikel'));
    await tester.tap(find.text('Artikel'));
    await pumpUntil(tester, find.text('Kleidung hinzufügen'));
    await selectDropdown(tester, 'Art', 'Pflege & Duft');
    expect(find.text('Pflege & Duft hinzufügen'), findsOneWidget);
    await enterInCard(tester, 'Name', 'Eau de Parfum');
    await tester.tap(find.text('Parfüm'));
    await tester.pump();
    await tester.ensureVisible(find.text('Hinzufügen'));
    await tester.tap(find.text('Hinzufügen'));
    await pumpUntil(tester, find.text('Eau de Parfum'));

    final items = await readDb(tester, () => InventoryRepository(db: db).getItems(user.uid));
    expect(items.single.kind, InventoryKind.care);
    expect(items.single.category, 'Parfüm');
    await disposeApp(tester, db);
  });

  testWidgets('shopping and gifts render on a 360 dp phone without overflow', (tester) async {
    tester.view.physicalSize = const Size(360, 780);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final user = await seedDb(tester, db, () async {
      final u = await createTestUser(db);
      final r = lists();
      await r.saveShopping(ShoppingItem(userid: u.uid, name: 'Vollkornnudeln mit sehr langem Namen', quantity: '3 Packungen'));
      await r.saveGiftList(GiftList(userid: u.uid, person: 'Schwester', occasion: 'Geburtstag', date: DateTime.now().add(const Duration(days: 5))));
      return u;
    });
    await tester.pumpWidget(testApp(db, ShoppingListScreen(user: user)));
    await pumpUntil(tester, find.textContaining('Vollkornnudeln'));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(testApp(db, GiftsScreen(user: user)));
    await pumpUntil(tester, find.text('Schwester · Geburtstag'));
    expect(tester.takeException(), isNull);
    await disposeApp(tester, db);
  });

  testWidgets('shopping list groups by aisle; the same food in two units is one row and is checked off together', (tester) async {
    useTallScreen(tester);
    final user = await seedDb(tester, db, () async {
      final u = await createTestUser(db);
      final repo = lists();
      await repo.addToList(u.uid, name: 'Zwiebeln', amount: 2);
      await repo.addToList(u.uid, name: 'Zwiebel', amount: 200, unit: 'g', label: 'Dal');
      await repo.addToList(u.uid, name: 'Shampoo');
      return u;
    });
    await tester.pumpWidget(testApp(db, ShoppingListScreen(user: user)));
    await pumpUntil(tester, find.text('OBST & GEMÜSE'));
    expect(find.text('DROGERIE & PFLEGE'), findsOneWidget);
    final onions = find.textContaining('2× + 200 g', findRichText: true);
    expect(onions, findsOneWidget);

    // Abhaken der Gruppe fragt je Menge nach und legt beide in den Vorrat
    final row = find.ancestor(of: onions, matching: find.byType(ListTile));
    await tester.tap(find.descendant(of: row, matching: find.byType(AppCheck)));
    for (final need in ['gebraucht: 2×', 'gebraucht: 200 g']) {
      await pumpUntil(tester, find.textContaining(need));
      await tester.tap(find.text('Wie geplant'));
      await pumpUntilGone(tester, find.textContaining(need));
    }
    await pumpUntilGone(tester, onions);
    final items = await readDb(tester, () => lists().getShopping(user.uid));
    expect(items.map((i) => i.name), ['Shampoo']);
    expect(items.single.done, isFalse);
    final pantry = await readDb(tester, () => InventoryRepository(db: db).getItems(user.uid));
    expect({for (final p in pantry) (p.quantity, p.unit)}, {(2.0, null), (200.0, 'g')});
    await disposeApp(tester, db);
  });

  testWidgets('checking off: scan the barcode → pack size from Open Food Facts, barcode goes into the pantry', (tester) async {
    useTallScreen(tester);
    final user = await seedDb(tester, db, () async {
      final u = await createTestUser(db);
      await lists().addToList(u.uid, name: 'Skyr');
      return u;
    });
    await tester.pumpWidget(testApp(
      db,
      ShoppingListScreen(user: user),
      barcodeScanner: const FakeBarcodeScanner('4001234567890'),
      openFoodFacts: fakeOpenFoodFacts({
        '4001234567890': {
          'product_name': 'Skyr Natur',
          'product_quantity': 450,
          'nutriments': {'energy-kcal_100g': 63, 'proteins_100g': 11, 'carbohydrates_100g': 4, 'fat_100g': 0.2},
        },
      }),
    ));
    await pumpUntil(tester, find.text('Skyr'));
    await tester.tap(find.byType(AppCheck));
    await pumpUntil(tester, find.text('Was hast du gekauft?'));
    await tester.tap(find.text('Barcode scannen'));
    await pumpUntil(tester, find.textContaining('Barcode 4001234567890 · Skyr Natur · 450 g'));
    expect(find.text('Packung 450 g'), findsOneWidget);
    expect(find.text('In den Vorrat: 450 g'), findsOneWidget);
    await tester.tap(find.widgetWithText(ElevatedButton, 'Abhaken'));
    await pumpUntil(tester, find.textContaining('ist jetzt im Vorrat – 450 g'));

    final pantry = (await readDb(tester, () => InventoryRepository(db: db).getItems(user.uid))).single;
    expect((pantry.name, pantry.quantity, pantry.unit, pantry.barcode), ('Skyr', 450.0, 'g', '4001234567890'));
    expect(pantry.foodId, isNotNull);
    await disposeApp(tester, db);
  });

  testWidgets('checking off can be undone; the receipt hint appears and can be closed without a receipt', (tester) async {
    useTallScreen(tester);
    final user = await seedDb(tester, db, () async {
      final u = await createTestUser(db);
      await lists().addToList(u.uid, name: 'Haferflocken', amount: 500, unit: 'g');
      await lists().addToList(u.uid, name: 'Tofu', amount: 200, unit: 'g');
      return u;
    });
    await tester.pumpWidget(testApp(db, ShoppingListScreen(user: user)));
    await pumpUntil(tester, find.text('500 g  Haferflocken', findRichText: true));
    expect(find.textContaining('noch kein Kassenzettel', findRichText: true), findsNothing);

    // Abhaken und gleich wieder zurück
    final oats = find.ancestor(of: find.text('500 g  Haferflocken', findRichText: true), matching: find.byType(ListTile));
    await tester.tap(find.descendant(of: oats, matching: find.byType(AppCheck)));
    await pumpUntil(tester, find.text('Was hast du gekauft?'));
    await tester.tap(find.widgetWithText(ElevatedButton, 'Abhaken'));
    await pumpUntil(tester, find.text('Rückgängig'));
    await tester.tap(find.text('Rückgängig'));
    await pumpUntil(tester, find.text('500 g  Haferflocken', findRichText: true));
    expect(await readDb(tester, () => InventoryRepository(db: db).getItems(user.uid)), isEmpty);
    expect((await readDb(tester, () => lists().getShopping(user.uid))).every((i) => !i.done), isTrue);

    // Tofu kaufen → Hinweis: Einkauf von heute ohne Kassenzettel
    final tofu = find.ancestor(of: find.text('200 g  Tofu', findRichText: true), matching: find.byType(ListTile));
    await tester.tap(find.descendant(of: tofu, matching: find.byType(AppCheck)));
    await pumpUntil(tester, find.text('Was hast du gekauft?'));
    await tester.tap(find.widgetWithText(ElevatedButton, 'Abhaken'));
    await pumpUntil(tester, find.textContaining('Noch kein Kassenzettel'));
    expect(find.textContaining('· 1 Artikel'), findsOneWidget);

    await tester.tap(find.text('Ohne Bon'));
    await pumpUntilGone(tester, find.textContaining('Noch kein Kassenzettel'));
    expect(await readDb(tester, () => InventoryRepository(db: db).tripsWithoutReceipt(user.uid)), isEmpty);
    await disposeApp(tester, db);
  });
}
