import 'package:flutter_test/flutter_test.dart';

import 'package:frontend/core/database/database.dart';
import 'package:frontend/core/models/app_exceptions.dart';
import 'package:frontend/features/auth/models/user.dart';
import 'package:frontend/features/finance/models/category.dart';
import 'package:frontend/features/finance/models/transaction_type.dart';
import 'package:frontend/features/finance/repositories/category_repository.dart';
import 'package:frontend/features/finance/repositories/transaction_repository.dart';
import 'package:frontend/features/inventory/models/inventory_item.dart';
import 'package:frontend/features/inventory/repositories/inventory_repository.dart';
import 'package:frontend/features/style/models/style.dart';
import 'package:frontend/features/style/repositories/style_repository.dart';

import '../../helpers/test_app.dart';

void main() {
  late DatabaseService db;
  late InventoryRepository inventory;
  late StyleRepository repo;
  late UserModel user;

  setUp(() async {
    db = createTestDatabase();
    inventory = InventoryRepository(db: db);
    repo = StyleRepository(
      db: db,
      inventory: inventory,
      transactions: TransactionRepository(db: db),
    );
    user = await createTestUser(db);
  });
  tearDown(() => db.close());

  Future<InventoryItem> clothing(String name) async {
    final id = await inventory.createItem(InventoryItem(userid: user.uid, kind: InventoryKind.clothing, name: name));
    return (await inventory.getItem(id))!;
  }

  test('outfits keep their items; deleted items drop out', () async {
    final shirt = await clothing('Hemd');
    final jeans = await clothing('Jeans');
    final id = await repo.saveOutfit(Outfit(userid: user.uid, name: 'Büro', items: [shirt, jeans]));

    var outfit = (await repo.getOutfits(user.uid)).single;
    expect(outfit.items.map((i) => i.name), ['Hemd', 'Jeans']);
    expect(outfit.neverWorn, isTrue);

    await inventory.deleteItem(jeans.id!);
    outfit = (await repo.getOutfits(user.uid)).single;
    expect(outfit.items.map((i) => i.name), ['Hemd']);

    await repo.saveOutfit(Outfit(id: id, userid: user.uid, name: 'Büro', items: []));
    expect((await repo.getOutfits(user.uid)).single.items, isEmpty);
  });

  test('wearing an outfit counts for the outfit and every item', () async {
    final shirt = await clothing('Hemd');
    await repo.saveOutfit(Outfit(userid: user.uid, name: 'Büro', items: [shirt]));
    final outfit = (await repo.getOutfits(user.uid)).single;

    await repo.wearOutfit(outfit, at: DateTime(2026, 9, 27));
    await repo.wearOutfit(outfit, at: DateTime(2026, 9, 28));

    final after = (await repo.getOutfits(user.uid)).single;
    expect(after.wearCount, 2);
    expect(after.lastWornAt, DateTime(2026, 9, 28));
    final item = (await inventory.getItem(shirt.id!))!;
    expect(item.wearCount, 2);
    expect(item.lastUsedAt, DateTime(2026, 9, 28));
  });

  test('buying a wish books an expense and adds the item to the wardrobe', () async {
    await createTestAccount(db, user.uid, 'Giro', amount: 500);
    final id = await repo.saveWish(WishlistItem(userid: user.uid, name: 'Laufschuhe', price: 120, priority: WishPriority.high));
    final wish = (await repo.getWishlist(user.uid)).firstWhere((w) => w.id == id);

    final itemId = await repo.buy(wish, account: 'Giro', date: DateTime(2026, 9, 27));

    expect(await balanceOf(db, user.uid, 'Giro'), 380);
    final item = (await inventory.getItem(itemId))!;
    expect(item.kind, InventoryKind.clothing);
    expect(item.name, 'Laufschuhe');
    expect(item.price, 120);
    expect(item.condition, ItemCondition.newItem);
    final bought = (await repo.getWishlist(user.uid)).single;
    expect(bought.status, WishStatus.bought);
    expect(bought.boughtItemId, itemId);
  });

  test('buying the same wish twice (double tap) books it only once', () async {
    await createTestAccount(db, user.uid, 'Giro', amount: 500);
    final id = await repo.saveWish(WishlistItem(userid: user.uid, name: 'Mütze', price: 20));
    final wish = (await repo.getWishlist(user.uid)).firstWhere((w) => w.id == id);
    await repo.buy(wish, account: 'Giro');
    await expectLater(repo.buy(wish, account: 'Giro'), throwsA(isA<UserFacingException>()));
    expect(await balanceOf(db, user.uid, 'Giro'), 480);
    expect((await inventory.getItems(user.uid)).where((i) => i.name == 'Mütze'), hasLength(1));
  });

  test('budget compares open wishes with the clothing budget of this month', () async {
    await createTestAccount(db, user.uid, 'Giro', amount: 500);
    await CategoryRepository(db: db).createCategory(Category(
      categoryName: 'Kleidung',
      categoryUserid: user.uid,
      categoryFontFamily: 'MaterialIcons',
      categoryCodePoint: 0,
      categoryIconName: 'checkroom',
      transactionType: TransactionType.expense,
      monthlyBudget: 100,
    ));
    final now = DateTime.now();
    await repo.saveWish(WishlistItem(userid: user.uid, name: 'Jacke', price: 80));
    final shirtId = await repo.saveWish(WishlistItem(userid: user.uid, name: 'Shirt', price: 25));
    final shirt = (await repo.getWishlist(user.uid)).firstWhere((w) => w.id == shirtId);
    await repo.buy(shirt, account: 'Giro', date: now);

    final budget = await repo.getBudget(user.uid, now: now);
    expect(budget.openSum, 80);
    expect(budget.monthlyBudget, 100);
    expect(budget.spentThisMonth, 25);
    expect(budget.remaining, 75);
  });

  test('wishlist lists open wishes by priority before bought ones', () async {
    await repo.saveWish(WishlistItem(userid: user.uid, name: 'A', priority: WishPriority.low));
    await repo.saveWish(WishlistItem(userid: user.uid, name: 'B', priority: WishPriority.high));
    await repo.saveWish(WishlistItem(userid: user.uid, name: 'C', priority: WishPriority.high, status: WishStatus.bought));
    expect((await repo.getWishlist(user.uid)).map((w) => w.name), ['B', 'A', 'C']);
  });
}
