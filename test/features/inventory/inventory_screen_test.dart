import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'package:frontend/core/database/database.dart';
import 'package:frontend/features/auth/models/user.dart';
import 'package:frontend/features/dashboard/screens/home.dart';
import 'package:frontend/features/dashboard/widgets/global_search_delegate.dart';
import 'package:frontend/features/inventory/models/inventory_item.dart';
import 'package:frontend/features/inventory/repositories/inventory_repository.dart';
import 'package:frontend/features/inventory/screens/inventory_screen.dart';

import '../../helpers/test_app.dart';

void main() {
  late DatabaseService db;

  setUpAll(() => initializeDateFormatting('de_DE'));
  setUp(() => db = createTestDatabase());

  DateTime inDays(int d) {
    final n = DateTime.now();
    return DateTime(n.year, n.month, n.day + d);
  }

  Future<UserModel> seed(WidgetTester tester, List<InventoryItem Function(int uid)> items) {
    return seedDb(tester, db, () async {
      final user = await createTestUser(db);
      final repo = InventoryRepository(db: db);
      for (final make in items) {
        await repo.createItem(make(user.uid));
      }
      return user;
    });
  }

  Future<List<InventoryItem>> stored(WidgetTester tester, UserModel user) async =>
      (await readDb(tester, () => InventoryRepository(db: db).getItems(user.uid)));

  Widget pantry(UserModel user) => InventoryScreen(
        user: user,
        kinds: const {InventoryKind.food, InventoryKind.drink},
        addKind: InventoryKind.food,
      );

  InventoryItem Function(int) food(String name, {int? expiresIn, String? location, double quantity = 1}) =>
      (uid) => InventoryItem(
            userid: uid,
            kind: InventoryKind.food,
            name: name,
            location: location,
            quantity: quantity,
            expiryDate: expiresIn == null ? null : inDays(expiresIn),
          );

  testWidgets('+ opens the full editor; the new item shows its expiry badge', (tester) async {
    useTallScreen(tester);
    final user = await seed(tester, []);
    await tester.pumpWidget(testApp(db, pantry(user)));
    await pumpUntil(tester, find.text('Dein Vorrat ist leer'));

    await tester.tap(find.text('Artikel'));
    await pumpUntil(tester, find.text('Lebensmittel hinzufügen'));
    // alle Felder sind da, nicht nur eine Auswahl
    for (final label in ['Name', 'Kategorie', 'Ort', 'Menge', 'Einheit', 'Ablaufdatum', 'Marke', 'Preis (€)', 'Notizen']) {
      expect(find.text(label, skipOffstage: false), findsWidgets, reason: label);
    }
    await enterInCard(tester, 'Name', 'Milch');
    await tester.tap(find.text('Milchprodukte'));
    await tester.tap(find.text('3 Tage'));
    await tester.pump();
    await tester.ensureVisible(find.text('Hinzufügen'));
    await tester.tap(find.text('Hinzufügen'));
    await pumpUntil(tester, find.text('noch 3 Tage'));

    final items = await stored(tester, user);
    expect(items.single.name, 'Milch');
    expect(items.single.category, 'Milchprodukte');
    expect(items.single.expiryDate, inDays(3));
    await disposeApp(tester, db);
  });

  testWidgets('search and status chips find items quickly', (tester) async {
    useTallScreen(tester);
    final user = await seed(tester, [
      food('Milch', expiresIn: 1, location: 'Kühlschrank'),
      food('Joghurt', expiresIn: -2, location: 'Kühlschrank'),
      food('Reis', location: 'Vorratsschrank'),
    ]);
    await tester.pumpWidget(testApp(db, pantry(user)));
    await pumpUntil(tester, find.text('Reis'));
    expect(find.text('3 Einträge'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'vorrat');
    await tester.pump();
    expect(find.text('1 Eintrag'), findsOneWidget);
    expect(find.text('Reis'), findsOneWidget);

    await tester.tap(find.text('Filter zurücksetzen'));
    await tester.pump();
    await tester.tap(find.text('Abgelaufen'));
    await tester.pump();
    expect(find.text('Joghurt'), findsOneWidget);
    expect(find.text('Milch'), findsNothing);
    expect(find.text('seit 2 Tagen abgelaufen'), findsOneWidget);
    await disposeApp(tester, db);
  });

  testWidgets('swipe right uses one, swipe left deletes with undo', (tester) async {
    useTallScreen(tester);
    final user = await seed(tester, [food('Eier', quantity: 6), food('Brot')]);
    await tester.pumpWidget(testApp(db, pantry(user)));
    await pumpUntil(tester, find.text('Eier'));

    await tester.drag(find.text('Eier'), const Offset(400, 0));
    await tester.pumpAndSettle();
    await tester.tap(find.text('−1'));
    await pumpUntil(tester, find.textContaining('noch 5'));

    await tester.drag(find.text('Brot'), const Offset(-400, 0));
    await tester.pumpAndSettle();
    expect(find.text('Bearbeiten'), findsOneWidget);
    await tester.tap(find.text('Löschen'));
    await pumpUntil(tester, find.text('„Brot“ gelöscht'));
    expect(find.text('Brot'), findsNothing);
    expect((await stored(tester, user)).map((i) => (i.name, i.quantity)), [('Eier', 5.0)]);

    await tester.tap(find.text('Rückgängig'));
    await pumpUntil(tester, find.text('Brot'));
    expect((await stored(tester, user)).map((i) => i.name), ['Brot', 'Eier']);
    await disposeApp(tester, db);
  });

  testWidgets('wardrobe: grid, "lange nicht getragen" and editing an item', (tester) async {
    useTallScreen(tester);
    final user = await seed(tester, [
      (uid) => InventoryItem(userid: uid, kind: InventoryKind.clothing, name: 'Anzug', lastUsedAt: DateTime(2025, 1, 1)),
      (uid) => InventoryItem(userid: uid, kind: InventoryKind.clothing, name: 'Hemd', lastUsedAt: DateTime.now()),
    ]);
    await tester.pumpWidget(testApp(
      db,
      InventoryScreen(user: user, kinds: const {InventoryKind.clothing}, addKind: InventoryKind.clothing, gridByDefault: true),
    ));
    await pumpUntil(tester, find.text('Anzug'));
    expect(find.byType(GridView), findsNothing); // Sliver-Grid
    expect(find.byTooltip('Als Liste anzeigen'), findsOneWidget);

    await tester.tap(find.text('Lange nicht getragen'));
    await tester.pump();
    expect(find.text('Hemd'), findsNothing);

    await tester.tap(find.text('Anzug'));
    await pumpUntil(tester, find.text('Bearbeiten'));
    await enterInCard(tester, 'Größe', '52');
    await tester.tap(find.text('Speichern'));
    await pumpUntilGone(tester, find.text('Bearbeiten'));

    final suit = (await stored(tester, user)).firstWhere((i) => i.name == 'Anzug');
    expect(suit.size, '52');
    await disposeApp(tester, db);
  });

  testWidgets('Home shows what expires soon', (tester) async {
    useTallScreen(tester);
    final user = await seed(tester, [food('Hähnchen', expiresIn: 0), food('Nudeln', expiresIn: 200)]);
    await tester.pumpWidget(testApp(db, Home(user: user)));
    await pumpUntil(tester, find.text('Läuft bald ab'));

    expect(find.text('Hähnchen'), findsOneWidget);
    expect(find.text('läuft heute ab'), findsOneWidget);
    expect(find.text('Nudeln'), findsNothing);
    await disposeApp(tester, db);
  });

  testWidgets('global search finds inventory items', (tester) async {
    useTallScreen(tester);
    final user = await seed(tester, [food('Haferflocken', location: 'Vorratsschrank')]);
    await tester.pumpWidget(testApp(
      db,
      Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => showSearch(context: context, delegate: GlobalSearchDelegate(userId: user.uid, db: db)),
            child: const Text('suchen'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('suchen'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'hafer');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await pumpUntil(tester, find.text('INVENTAR')); // GroupLabel in Großbuchstaben

    expect(find.text('Haferflocken'), findsWidgets);
    await disposeApp(tester, db);
  });

  testWidgets('pantry renders on a 360 dp phone without overflow', (tester) async {
    tester.view.physicalSize = const Size(360, 780);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final user = await seed(tester, [food('Ein sehr langer Produktname für den Zeilenumbruch', expiresIn: 2, location: 'Kühlschrank')]);
    await tester.pumpWidget(testApp(db, pantry(user)));
    await pumpUntil(tester, find.textContaining('Ein sehr langer'));

    expect(tester.takeException(), isNull);
    await disposeApp(tester, db);
  });
}
