import 'package:flutter_test/flutter_test.dart';

import 'package:frontend/core/database/database.dart';
import 'package:frontend/features/auth/models/user.dart';
import 'package:frontend/features/inventory/models/inventory_item.dart';
import 'package:frontend/features/inventory/repositories/inventory_repository.dart';
import 'package:frontend/features/lists/models/lists.dart';
import 'package:frontend/features/lists/repositories/lists_repository.dart';

import '../../helpers/test_app.dart';

void main() {
  late DatabaseService db;
  late InventoryRepository inventory;
  late ListsRepository repo;
  late UserModel user;

  setUp(() async {
    db = createTestDatabase();
    inventory = InventoryRepository(db: db);
    repo = ListsRepository(db: db, inventory: inventory);
    user = await createTestUser(db);
  });
  tearDown(() => db.close());

  group('shopping list', () {
    test('one list in entry order, done items last; clear removes done ones', () async {
      await repo.saveShopping(ShoppingItem(userid: user.uid, name: 'T-Shirt', category: ShoppingCategory.clothing));
      await repo.saveShopping(ShoppingItem(userid: user.uid, name: 'Tofu', category: ShoppingCategory.food));
      await repo.saveShopping(ShoppingItem(userid: user.uid, name: 'Haferdrink', category: ShoppingCategory.drinks, quantity: '2'));
      await repo.saveShopping(ShoppingItem(userid: user.uid, name: 'Bananen', category: ShoppingCategory.food));

      var items = await repo.getShopping(user.uid);
      expect(items.map((i) => i.name), ['T-Shirt', 'Tofu', 'Haferdrink', 'Bananen']);

      final done = await repo.toggleShopping(items[1], at: DateTime(2026, 10, 1));
      expect(done.done, isTrue);
      items = await repo.getShopping(user.uid);
      expect(items.last.name, 'Tofu');
      expect(items.last.doneAt, DateTime(2026, 10, 1));

      await repo.toggleShopping(items.last); // wieder öffnen
      expect((await repo.getShopping(user.uid)).where((i) => i.done), isEmpty);

      await repo.toggleShopping((await repo.getShopping(user.uid)).first);
      expect(await repo.clearDone(user.uid), 1);
      expect(await repo.getShopping(user.uid), hasLength(3));
    });

    test('quantities are parsed and normalised; department is guessed', () {
      expect(parseShoppingInput('600g Magerquark'), ('Magerquark', '600 g'));
      expect(parseShoppingInput('Magerquark 600 g'), ('Magerquark', '600 g'));
      expect(parseShoppingInput('4x Deo'), ('Deo', '4×'));
      expect(parseShoppingInput('Deo 4x'), ('Deo', '4×'));
      expect(parseShoppingInput('10 Eier'), ('Eier', '10×'));
      expect(parseShoppingInput('1,5 l Haferdrink'), ('Haferdrink', '1,5 l'));
      expect(parseShoppingInput('2 Lauch'), ('Lauch', '2×'));
      expect(parseShoppingInput('Tofu'), ('Tofu', null));
      expect(splitQuantity('600 g'), (600, 'g'));
      expect(splitQuantity('4×'), (4, null));
      expect(ShoppingCategory.guess('Deo'), ShoppingCategory.care);
      expect(ShoppingCategory.guess('Magerquark'), ShoppingCategory.food);
      expect(ShoppingCategory.guess('Hafermilch'), ShoppingCategory.drinks);
      expect(ShoppingCategory.guess('T-Shirt'), ShoppingCategory.clothing);
    });

    test('bought items move to pantry, wardrobe or care with quantity and unit', () async {
      final quarkId = await repo.saveShopping(
          ShoppingItem(userid: user.uid, name: 'Magerquark', category: ShoppingCategory.food, quantity: '600 g'));
      final drinkId = await repo.saveShopping(
          ShoppingItem(userid: user.uid, name: 'Haferdrink', category: ShoppingCategory.drinks, quantity: '2 Packungen'));
      final shirtId = await repo.saveShopping(ShoppingItem(userid: user.uid, name: 'T-Shirt', category: ShoppingCategory.clothing));
      final perfumeId = await repo.saveShopping(ShoppingItem(userid: user.uid, name: 'Parfüm', category: ShoppingCategory.care));
      final items = await repo.getShopping(user.uid);

      final quark = await inventory.getItem((await repo.moveToInventory(items.firstWhere((i) => i.id == quarkId)))!);
      expect(quark!.quantity, 600);
      expect(quark.unit, 'g');
      final drink = await inventory.getItem((await repo.moveToInventory(items.firstWhere((i) => i.id == drinkId)))!);
      expect(drink!.kind, InventoryKind.drink);
      expect(drink.quantity, 2);
      final shirt = await inventory.getItem((await repo.moveToInventory(items.firstWhere((i) => i.id == shirtId)))!);
      expect(shirt!.kind, InventoryKind.clothing);
      expect(shirt.condition, ItemCondition.newItem);
      final perfume = await inventory.getItem((await repo.moveToInventory(items.firstWhere((i) => i.id == perfumeId)))!);
      expect(perfume!.kind, InventoryKind.care);
      expect(await repo.getShopping(user.uid), isEmpty);
    });

    test('moving the same bought item twice (double tap, snackbar + swipe) books it only once', () async {
      final id = await repo.saveShopping(ShoppingItem(userid: user.uid, name: 'Haferflocken', category: ShoppingCategory.food, quantity: '500 g'));
      final item = (await repo.getShopping(user.uid)).firstWhere((i) => i.id == id);
      final results = await Future.wait([repo.moveToInventory(item), repo.moveToInventory(item)]);
      expect(results.whereType<int>(), hasLength(1));
      expect((await inventory.getItems(user.uid)).where((i) => i.name == 'Haferflocken'), hasLength(1));
      expect(await repo.moveToInventory(item), isNull);
    });
  });

  group('gift lists', () {
    test('lists are ordered by upcoming date and carry their ideas', () async {
      final now = DateTime(2026, 10, 1);
      final sister = await repo.saveGiftList(
          GiftList(userid: user.uid, person: 'Schwester', occasion: 'Geburtstag', date: DateTime(2026, 11, 3)));
      await repo.saveGiftList(GiftList(userid: user.uid, person: 'Bruder', occasion: 'Weihnachten', date: DateTime(2026, 12, 24)));
      await repo.saveGiftList(GiftList(userid: user.uid, person: 'Mama', occasion: 'Einfach so'));
      await repo.saveGiftList(GiftList(userid: user.uid, person: 'Papa', occasion: 'Geburtstag', date: DateTime(2026, 9, 1)));

      final ideaId = await repo.saveGift(GiftItem(listId: sister, userid: user.uid, name: 'Parfüm', price: 45));
      await repo.saveGift(GiftItem(listId: sister, userid: user.uid, name: 'Buch', price: 15));

      final lists = await repo.getGiftLists(user.uid, now: now);
      expect(lists.map((l) => l.person), ['Schwester', 'Bruder', 'Mama', 'Papa']);
      expect(lists.first.title, 'Schwester · Geburtstag');
      expect(lists.first.daysUntil(now), 33);
      expect(lists.first.openCount, 2);

      final perfume = (await repo.getGiftList(sister))!.items.firstWhere((i) => i.id == ideaId);
      await repo.setGiftStatus(perfume, perfume.status.next);
      final updated = (await repo.getGiftList(sister))!;
      expect(updated.items.firstWhere((i) => i.id == ideaId).status, GiftStatus.bought);
      expect(updated.plannedSum, 45);
      expect(updated.openCount, 1);
    });

    test('an idea goes onto the shopping list and deleting a list removes its ideas', () async {
      final id = await repo.saveGiftList(GiftList(userid: user.uid, person: 'Bruder', occasion: 'Weihnachten'));
      await repo.saveGift(GiftItem(listId: id, userid: user.uid, name: 'Kopfhörer'));
      final list = (await repo.getGiftList(id))!;

      await repo.giftToShopping(list.items.single, list);
      final shopping = (await repo.getShopping(user.uid)).single;
      expect(shopping.name, 'Kopfhörer');
      expect(shopping.quantity, 'für Bruder');

      await repo.deleteGiftList(id);
      expect(await repo.getGiftLists(user.uid), isEmpty);
      final orphan = await (await db.database).query('gift_items', where: 'is_deleted = 0');
      expect(orphan, isEmpty);
    });
  });

  group('amounts and sources', () {
    test('parse, normalise and format amounts', () {
      expect(parseAmount('600 g'), (600.0, 'g'));
      expect(parseAmount('1,5 kg'), (1500.0, 'g'));
      expect(parseAmount('4x'), (4.0, null));
      expect(parseAmount('2 Dosen'), (2.0, 'Dose'));
      expect(parseAmount('für Schwester'), isNull);
      expect(formatAmount(1500, 'g'), '1,5 kg');
      expect(formatAmount(2, 'Dose'), '2 Dosen');
      expect(formatAmount(3, null), '3×');
    });

    test('pack plan: least leftover, then fewest packs', () {
      expect(packPlan(500, [400, 600]), [(600.0, 1)]);
      expect(packPlan(900, [400, 600]), [(400.0, 1), (600.0, 1)]);
      expect(packPlan(1200, [400, 600]), [(600.0, 2)]);
      expect(packPlanLabel(packPlan(900, [400, 600]), 'g'), '1× 400 g + 1× 600 g');
      expect(packPlan(100, const []), isEmpty);
    });

    test('same item is added up per unit; each source is listed and removable', () async {
      final a = await repo.addToList(user.uid, name: 'Kartoffeln', amount: 400, unit: 'g', label: 'Ofenkartoffeln', recipeKey: 'ofen', batchId: 7);
      final b = await repo.addToList(user.uid, name: 'kartoffeln', amount: 0.5, unit: 'kg', label: 'Linsensuppe', recipeKey: 'suppe', batchId: 8);
      expect(b, a);
      await repo.addToList(user.uid, name: 'Kartoffeln', amount: 2); // Stück: eigener Eintrag
      final items = await repo.getShopping(user.uid);
      expect(items.map((i) => '${i.quantityLabel} ${i.name}'), ['900 g Kartoffeln', '2× Kartoffeln']);

      final sources = await repo.getSources(a);
      expect(sources.map((s) => (s.label, s.amount)), [('Ofenkartoffeln', 400.0), ('Linsensuppe', 500.0)]);
      await repo.removeSource(sources.first);
      expect((await repo.getShopping(user.uid)).first.amount, 500);
      await repo.restoreSource(sources.first);
      expect((await repo.getShopping(user.uid)).first.amount, 900);

      // Vertippt: alle Zutaten eines Koch-Blocks wieder herunter – und zurück
      final at = await repo.removeFromList(user.uid, batchId: 8);
      expect((await repo.getShopping(user.uid)).first.amount, 400);
      final onlyOven = await repo.removeFromList(user.uid, batchId: 7);
      expect((await repo.getShopping(user.uid)).map((i) => i.name), ['Kartoffeln']); // Artikel ohne Herkunft weg
      await repo.restoreRemoved(user.uid, onlyOven);
      await repo.restoreRemoved(user.uid, at);
      expect((await repo.getShopping(user.uid)).first.amount, 900);
    });

    test('editing the amount keeps the recipe split; bought packs go into the pantry', () async {
      final id = await repo.addToList(user.uid, name: 'Hackfleisch', amount: 300, unit: 'g', label: 'Bolognese', recipeKey: 'bolo');
      var item = (await repo.getShopping(user.uid)).single;
      await repo.saveShopping(item.copyWith(amount: 500)); // +200 g selbst
      item = (await repo.getShopping(user.uid)).single;
      expect(item.quantityLabel, '500 g');
      expect((await repo.getSources(id)).map((s) => (s.label, s.amount)), [('Bolognese', 300.0), (ShoppingSource.manualLabel, 200.0)]);

      // Gekauft wird eine 600-g-Packung → 600 g in den Vorrat
      final done = await repo.toggleShopping(item, bought: 600);
      expect(done.boughtAmount, 600);
      final pantry = await inventory.getItem((await repo.moveToInventory(done))!);
      expect((pantry!.quantity, pantry.unit), (600.0, 'g'));
    });
  });

  group('same food, grouped', () {
    test('shoppingKey: case, plural, parentheses and extra spaces do not matter', () {
      for (final (a, b) in [
        ('Zwiebel', 'Zwiebeln'),
        ('Ei', 'Eier'),
        ('Tomate', 'Tomaten'),
        ('Möhren', 'möhre'),
        ('Rote Linsen', 'rote  linse'),
        ('Kidneybohnen (Dose, abgetropft)', 'Kidneybohnen'),
        ('Avocados', 'Avocado'),
      ]) {
        expect(shoppingKey(a), shoppingKey(b), reason: '$a = $b');
      }
      expect(shoppingKey('Zwiebel'), isNot(shoppingKey('Knoblauch')));
      expect(shoppingKey('Milch'), isNot(shoppingKey('Haferdrink')));
    });

    test('adding "Zwiebeln" to an open "Zwiebel" adds up in one row', () async {
      await repo.addToList(user.uid, name: 'Zwiebel', amount: 1);
      await repo.addToList(user.uid, name: 'Zwiebeln', amount: 2, label: 'Dal');
      final items = await repo.getShopping(user.uid);
      expect(items, hasLength(1));
      expect((items.single.name, items.single.amount), ('Zwiebel', 3.0));
    });

    test('duplicates already on the list (older versions, sync) are merged when the list is loaded', () async {
      final database = await db.database;
      for (final name in ['Zwiebeln', 'zwiebel']) {
        final id = await database.insert('shopping_items', {'userid': user.uid, 'name': name, 'amount': 1, 'category': 'food', 'done': 0});
        await database.insert('shopping_sources', {'itemId': id, 'userid': user.uid, 'amount': 1, 'label': 'Selbst eingetragen'});
      }
      final items = await repo.getShopping(user.uid);
      expect(items, hasLength(1));
      expect(items.single.amount, 2);
      expect(await repo.getSources(items.single.id!), hasLength(2));
    });

    test('groups: same food with different units is one group; groups follow the aisles', () async {
      await repo.addToList(user.uid, name: 'Zwiebeln', amount: 2);
      await repo.addToList(user.uid, name: 'Zwiebel', amount: 200, unit: 'g');
      await repo.addToList(user.uid, name: 'Shampoo');
      await repo.addToList(user.uid, name: 'Haferflocken', amount: 500, unit: 'g');
      await repo.addToList(user.uid, name: 'Joghurt', amount: 500, unit: 'g');
      final groups = groupShopping((await repo.getShopping(user.uid)).where((i) => !i.done).toList());
      final onions = groups.firstWhere((g) => g.name == 'Zwiebeln');
      expect(onions.items, hasLength(2));
      expect(onions.quantityLabel, '2× + 200 g');
      expect([for (final g in groups) (g.aisle, g.name)], [
        (ShoppingAisle.produce, 'Zwiebeln'),
        (ShoppingAisle.chilled, 'Joghurt'),
        (ShoppingAisle.pantry, 'Haferflocken'),
        (ShoppingAisle.care, 'Shampoo'),
      ]);
    });

    test('canned and dried goods go to the pantry aisle even if they name a vegetable', () {
      for (final name in ['Gehackte Tomaten', 'Gemüsebrühe', 'Tomatenmark', 'Kidneybohnen (Dose, abgetropft)', 'Paprikapulver', 'Getrocknete Tomaten']) {
        expect(ShoppingAisle.of(ShoppingItem(userid: 1, name: name)), ShoppingAisle.pantry, reason: name);
      }
      for (final name in ['Tomaten', 'Rote Paprika', 'Frische Petersilie']) {
        expect(ShoppingAisle.of(ShoppingItem(userid: 1, name: name)), ShoppingAisle.produce, reason: name);
      }
    });
  });
}
