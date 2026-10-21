import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'package:frontend/core/database/database.dart';
import 'package:frontend/features/auth/models/user.dart';
import 'package:frontend/features/finance/models/category.dart';
import 'package:frontend/features/finance/models/transaction_type.dart';
import 'package:frontend/features/finance/repositories/category_repository.dart';
import 'package:frontend/features/finance/repositories/transaction_repository.dart';
import 'package:frontend/features/inventory/models/inventory_item.dart';
import 'package:frontend/features/inventory/repositories/inventory_repository.dart';
import 'package:frontend/features/style/models/style.dart';
import 'package:frontend/features/style/repositories/style_repository.dart';
import 'package:frontend/features/style/screens/outfit_editor_screen.dart';
import 'package:frontend/features/style/screens/outfits_screen.dart';
import 'package:frontend/features/style/screens/wishlist_screen.dart';

import '../../helpers/test_app.dart';

void main() {
  late DatabaseService db;

  setUpAll(() => initializeDateFormatting('de_DE'));
  setUp(() => db = createTestDatabase());

  StyleRepository styleRepo() {
    final inventory = InventoryRepository(db: db);
    return StyleRepository(db: db, inventory: inventory, transactions: TransactionRepository(db: db));
  }

  Future<UserModel> seedWardrobe(WidgetTester tester) => seedDb(tester, db, () async {
        final user = await createTestUser(db);
        final inventory = InventoryRepository(db: db);
        for (final (name, category) in [('Weißes Hemd', 'Oberteile'), ('Jeans', 'Hosen'), ('Sneaker', 'Schuhe')]) {
          await inventory.createItem(InventoryItem(userid: user.uid, kind: InventoryKind.clothing, name: name, category: category));
        }
        return user;
      });

  testWidgets('compose an outfit from the wardrobe and wear it today', (tester) async {
    useTallScreen(tester);
    final user = await seedWardrobe(tester);
    await tester.pumpWidget(testApp(db, OutfitsScreen(user: user)));
    await pumpUntil(tester, find.text('Noch keine Outfits'));
    expect(find.textContaining('3 Teile wurden noch nie getragen'), findsOneWidget);

    await tester.tap(find.text('Outfit'));
    await pumpUntil(tester, find.byType(OutfitEditorScreen));
    await pumpUntil(tester, find.text('Jeans'));
    await tester.tap(find.text('Hinzufügen'));
    await pumpUntil(tester, find.text('Name erforderlich'));
    await enterInCard(tester, 'Name', 'Casual');
    await tester.tap(find.text('Hinzufügen'));
    await pumpUntil(tester, find.text('Wähle mindestens ein Teil aus.'));

    await tester.tap(find.text('Weißes Hemd'));
    await tester.tap(find.text('Jeans'));
    await tester.pump();
    expect(find.text('2 gewählt'), findsOneWidget);
    await tester.tap(find.text('Hinzufügen'));
    await pumpUntilGone(tester, find.byType(OutfitEditorScreen));
    await pumpUntil(tester, find.text('Heute tragen'));
    expect(find.text('Nie getragen · 2 Teile'), findsOneWidget);

    await tester.tap(find.text('Heute tragen'));
    await pumpUntil(tester, find.text('Heute getragen'));
    expect(find.textContaining('1 Teil wurde noch nie getragen'), findsOneWidget); // nur noch die Sneaker

    final outfit = (await readDb(tester, () => styleRepo().getOutfits(user.uid))).single;
    expect(outfit.wearCount, 1);
    expect(outfit.items.map((i) => i.name), unorderedEquals(['Weißes Hemd', 'Jeans']));
    await disposeApp(tester, db);
  });

  testWidgets('add a wish and buy it: expense booked, item in wardrobe', (tester) async {
    useTallScreen(tester);
    final user = await seedDb(tester, db, () async {
      final user = await createTestUser(db);
      await createTestAccount(db, user.uid, 'Girokonto', amount: 300);
      await CategoryRepository(db: db).createCategory(Category(
        categoryName: 'Kleidung',
        categoryUserid: user.uid,
        categoryFontFamily: 'MaterialIcons',
        categoryCodePoint: Icons.checkroom_outlined.codePoint,
        categoryIconName: 'checkroom_outlined',
        transactionType: TransactionType.expense,
        monthlyBudget: 150,
      ));
      return user;
    });
    await tester.pumpWidget(testApp(db, WishlistScreen(user: user)));
    await pumpUntil(tester, find.text('Keine offenen Wünsche'));

    await tester.tap(find.text('Wunsch'));
    await pumpUntil(tester, find.byType(WishEditorScreen));
    await enterInCard(tester, 'Name', 'Laufjacke');
    await enterInCard(tester, 'Preis', '89,90');
    await tester.tap(find.text('Dringend'));
    await tester.tap(find.text('Hinzufügen'));
    await pumpUntilGone(tester, find.byType(WishEditorScreen));
    await pumpUntil(tester, find.text('Laufjacke'));
    expect(find.textContaining('Dringend'), findsOneWidget);

    await tester.tap(find.text('Gekauft'));
    await pumpUntil(tester, find.text('Girokonto'));
    expect(find.text('Kleidung'), findsOneWidget);
    await tester.tap(find.text('Kauf buchen'));
    await pumpUntilGone(tester, find.byType(AlertDialog));
    await pumpUntil(tester, find.text('Keine offenen Wünsche'));
    expect(find.textContaining('89,90'), findsWidgets);

    expect(await readDb(tester, () => balanceOf(db, user.uid, 'Girokonto')), closeTo(210.10, 0.001));
    final wardrobe = await readDb(tester, () => InventoryRepository(db: db).getItems(user.uid, kinds: {InventoryKind.clothing}));
    expect(wardrobe.single.name, 'Laufjacke');
    final budget = await readDb(tester, () => styleRepo().getBudget(user.uid));
    expect(budget.spentThisMonth, closeTo(89.90, 0.001));
    await disposeApp(tester, db);
  });

  testWidgets('style screens render on a 360 dp phone without overflow', (tester) async {
    tester.view.physicalSize = const Size(360, 780);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final user = await seedWardrobe(tester);
    await seedDb(tester, db, () async {
      final repo = styleRepo();
      final items = await InventoryRepository(db: db).getItems(user.uid);
      await repo.saveOutfit(Outfit(userid: user.uid, name: 'Ein sehr langer Outfit-Name für den Alltag', items: items));
      await repo.saveWish(WishlistItem(userid: user.uid, name: 'Wintermantel mit langem Namen', price: 249.99));
    });

    await tester.pumpWidget(testApp(db, OutfitsScreen(user: user)));
    await pumpUntil(tester, find.text('Heute tragen'));
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(testApp(db, WishlistScreen(user: user)));
    await pumpUntil(tester, find.text('Gekauft'));
    expect(tester.takeException(), isNull);
    await disposeApp(tester, db);
  });
}
