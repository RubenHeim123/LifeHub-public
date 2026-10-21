import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';

import 'package:frontend/core/database/database.dart';
import 'package:frontend/features/auth/models/user.dart';
import 'package:frontend/features/auth/services/auth.dart';
import 'package:frontend/features/finance/repositories/account_repository.dart';
import 'package:frontend/features/finance/repositories/category_repository.dart';
import 'package:frontend/features/finance/repositories/transaction_repository.dart';
import 'package:frontend/features/finance/repositories/user_repository.dart';
import 'package:frontend/features/dashboard/screens/home.dart';
import 'package:frontend/features/finance/screens/finance_hub_screen.dart';
import 'package:frontend/features/finance/screens/transaction_view.dart';
import 'package:frontend/features/finance/screens/add_update_transactions.dart';
import 'package:frontend/features/food/screens/food_hub_screen.dart';
import 'package:frontend/app/app_tabs.dart';
import 'package:frontend/features/inventory/repositories/inventory_repository.dart';
import 'package:frontend/features/lists/repositories/lists_repository.dart';

import 'package:frontend/features/receipts/screens/receipt_review_screen.dart';

import 'package:frontend/features/receipts/services/receipt_scanner.dart';

import 'package:frontend/features/finance/models/transaction.dart';
import 'package:frontend/features/finance/models/transaction_type.dart';

import '../../helpers/test_app.dart';

void main() {
  late DatabaseService db;

  setUpAll(() => initializeDateFormatting('de_DE'));
  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    db = createTestDatabase();
  });

  const bon = [
    'ALDI SÜD',
    'Hauptstraße 12',
    '72070 Tübingen',
    'HAFERFL. ZART 500G 0,59 A',
    'BIO TOFU NATUR 200G',
    '2 x 1,79 3,58 A',
    'BANANEN 1,78 A',
    '1,230 kg x 1,45 EUR/kg',
    'SPÜLMITTEL 0,85 B',
    'PFAND 0,25 B',
    'Summe 7,05',
    'Kartenzahlung girocard 7,05',
    '05.10.26 18:23',
  ];

  /// Nutzer mit den Standardkonten und -kategorien (wie nach der Registrierung).
  Future<UserModel> seedUser(WidgetTester tester) => seedDb(tester, db, () async {
        await AuthService(
          users: UserRepository(db: db),
          accounts: AccountRepository(db: db),
          categories: CategoryRepository(db: db),
        ).registerWithEmailAndPassword('bon@test.de', 'geheim123');
        return (await UserRepository(db: db).getUserFromEmail('bon@test.de'))!;
      });

  testWidgets('photo a receipt: review, adjust and confirm → transaction and pantry items', (tester) async {
    useTallScreen(tester);
    final user = await seedUser(tester);
    await tester.pumpWidget(testApp(db, TransactionView(user: user), receiptScanner: FakeReceiptScanner(bon)));
    await pumpUntil(tester, find.byTooltip('Kassenzettel fotografieren'));

    await tester.tap(find.byTooltip('Kassenzettel fotografieren'));
    await pumpUntil(tester, find.text('Kassenzettel fotografieren'));
    await tester.tap(find.text('Kassenzettel fotografieren').last);
    await pumpUntil(tester, find.text('Kassenzettel prüfen'));
    await pumpUntil(tester, find.text('Bestätigen und speichern'));

    // Erkannt: Händler, Betrag, Konto (Karte → Girokonto), Kategorie (Lebensmittel als Vorschlag)
    expect(find.widgetWithText(TextFormField, 'ALDI SÜD'), findsOneWidget);
    expect(find.widgetWithText(TextFormField, '7,05'), findsOneWidget);
    expect(find.text('Montag, 5. Oktober 2026'), findsOneWidget);
    expect(find.text('Girokonto'), findsOneWidget);
    expect(find.text('Lebensmittel'), findsWidgets);
    expect(find.text('5 Positionen erkannt'), findsOneWidget);
    expect(find.text('3 von 5'), findsOneWidget); // Haferflocken, Tofu, Bananen – nicht Spülmittel/Pfand

    // Vorschlag passt: Mengen aus dem Bon
    expect(find.widgetWithText(TextField, 'Haferflocken'), findsOneWidget);
    expect(find.widgetWithText(TextField, '400'), findsOneWidget); // 2 × 200 g Tofu
    expect(find.widgetWithText(TextField, '1230'), findsOneWidget); // Bananen gewogen

    // Nachjustieren: Betrag korrigieren, Bananen als Stück, Haferflocken nicht in den Vorrat
    await tester.enterText(find.widgetWithText(TextFormField, '7,05'), '7,10');
    await tester.enterText(find.widgetWithText(TextField, '1230'), '6');
    final bananaCard = find.ancestor(of: find.text('BANANEN'), matching: find.byType(Column)).first;
    await tester.tap(find.descendant(of: bananaCard, matching: find.byType(DropdownButtonFormField<String>)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Stück').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byWidgetPredicate((w) => w is Checkbox && w.semanticLabel == 'HAFERFL. ZART 500G in den Vorrat'));
    await tester.pump();
    expect(find.text('2 von 5'), findsOneWidget);

    await tester.ensureVisible(find.text('Bestätigen und speichern'));
    await tester.tap(find.text('Bestätigen und speichern'));
    await pumpUntil(tester, find.textContaining('Buchung über 7,10 € gespeichert · 2 Artikel im Vorrat'));

    final tx = (await readDb(tester, () => TransactionRepository(db: db).getAllTransactions(user.uid))).single;
    expect((tx.description, tx.amount, tx.category, tx.account), ('ALDI SÜD', 7.10, 'Lebensmittel', 'Girokonto'));
    expect(tx.date, DateTime(2026, 10, 5, 18, 23));
    final pantry = await readDb(tester, () => InventoryRepository(db: db).getItems(user.uid));
    final byName = {for (final i in pantry) i.name: i};
    expect(byName.keys.toSet(), {'Tofu natur', 'Banane'});
    expect((byName['Tofu natur']!.quantity, byName['Tofu natur']!.unit), (400.0, 'g'));
    expect((byName['Banane']!.quantity, byName['Banane']!.unit), (6.0, null));
    expect(byName['Banane']!.foodId, isNotNull);
    await disposeApp(tester, db);
  });

  testWidgets('pantry offers the receipt scan next to the search', (tester) async {
    useTallScreen(tester);
    final user = await seedUser(tester);
    await tester.pumpWidget(testApp(
      db,
      FoodHubScreen(user: user, initialSection: FoodSection.pantry),
      receiptScanner: FakeReceiptScanner(const ['Hofladen', 'Eier 10 Stk 3,20', 'Summe 3,20']),
    ));
    await pumpUntil(tester, find.byTooltip('Kassenzettel fotografieren'));
    await tester.tap(find.byTooltip('Kassenzettel fotografieren'));
    await pumpUntil(tester, find.text('Foto aus der Galerie'));
    await tester.tap(find.text('Foto aus der Galerie'));
    await pumpUntil(tester, find.text('Bestätigen und speichern'));
    expect(find.text('1 Positionen erkannt'), findsOneWidget);
    await disposeApp(tester, db);
  });

  testWidgets('no text on the photo shows a hint instead of an empty review', (tester) async {
    useTallScreen(tester);
    final user = await seedUser(tester);
    await tester.pumpWidget(testApp(db, TransactionView(user: user), receiptScanner: FakeReceiptScanner(const [])));
    await pumpUntil(tester, find.byTooltip('Kassenzettel fotografieren'));
    await tester.tap(find.byTooltip('Kassenzettel fotografieren'));
    await pumpUntil(tester, find.text('Foto aus der Galerie'));
    await tester.tap(find.text('Kassenzettel fotografieren').last);
    await pumpUntil(tester, find.textContaining('kein Text erkannt'));
    await disposeApp(tester, db);
  });

  testWidgets('duplicate category or account names in old data do not crash the review', (tester) async {
    useTallScreen(tester);
    final user = await seedUser(tester);
    await seedDb(tester, db, () async {
      final raw = await db.database;
      // Alte Daten vor der Namensprüfung: zwei gleichnamige Ausgabenkategorien und Konten
      final cat = (await raw.query('categories', where: 'categoryUserid = ? AND categoryName = ?', whereArgs: [user.uid, 'Lebensmittel'])).first;
      await raw.insert('categories', {...cat}..remove('id'));
      final acc = (await raw.query('accounts', where: 'accountUserid = ? AND accountName = ?', whereArgs: [user.uid, 'Girokonto'])).first;
      await raw.insert('accounts', {...acc}..remove('id'));
    });
    await tester.pumpWidget(testApp(db, TransactionView(user: user), receiptScanner: FakeReceiptScanner(bon)));
    await pumpUntil(tester, find.byTooltip('Kassenzettel fotografieren'));
    await tester.tap(find.byTooltip('Kassenzettel fotografieren'));
    await pumpUntil(tester, find.text('Foto aus der Galerie'));
    await tester.tap(find.text('Kassenzettel fotografieren').last);
    await pumpUntil(tester, find.text('Bestätigen und speichern'));
    expect(tester.takeException(), isNull);
    await disposeApp(tester, db);
  });

  testWidgets('a broken data row shows a message instead of an endless spinner (Home, Finanzen)', (tester) async {
    useTallScreen(tester);
    final user = await seedUser(tester);
    await seedDb(tester, db, () async {
      final raw = await db.database;
      await raw.insert('transactions', {
        'date': 'kein-datum',
        'amount': 5,
        'category': 'Lebensmittel',
        'description': 'kaputt',
        'account': 'Girokonto',
        'transactionType': 'Ausgabe',
        'userid': user.uid,
      });
    });
    await tester.pumpWidget(testApp(db, Home(user: user)));
    await pumpUntil(tester, find.textContaining('nicht vollständig geladen'));
    expect(find.byType(CircularProgressIndicator), findsNothing);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(testApp(db, FinanceHubScreen(user: user)));
    await pumpUntil(tester, find.textContaining('nicht vollständig geladen'));
    expect(find.byType(CircularProgressIndicator), findsNothing);
    await disposeApp(tester, db);
  });

  testWidgets('a receipt without readable items still books the total, nothing goes to the pantry', (tester) async {
    useTallScreen(tester);
    final user = await seedUser(tester);
    await tester.pumpWidget(testApp(db, launcher(ReceiptReviewScreen(userid: user.uid, scan: const ReceiptScan(lines: ['REWE', 'Summe 4,20'])))));
    await tester.tap(find.text('öffnen'));
    await pumpUntil(tester, find.text('Keine Positionen erkannt – es wird nur die Buchung gespeichert.'));
    await tester.ensureVisible(find.text('Bestätigen und speichern'));
    await tester.tap(find.text('Bestätigen und speichern'));
    await pumpUntil(tester, find.text('result:true'));

    final booked = (await readDb(tester, () => TransactionRepository(db: db).getAllTransactions(user.uid))).single;
    expect((booked.amount, booked.description), (4.2, 'REWE'));
    expect(await readDb(tester, () => InventoryRepository(db: db).getItems(user.uid)), isEmpty);
    await disposeApp(tester, db);
  });

  testWidgets('without any expense category the review is no dead end: „Allgemein“ is created', (tester) async {
    useTallScreen(tester);
    final user = await seedUser(tester);
    await seedDb(tester, db, () async {
      final raw = await db.database;
      await raw.delete('categories', where: 'categoryUserid = ? AND transactionType = ?', whereArgs: [user.uid, 'Ausgabe']);
    });
    await tester.pumpWidget(testApp(db, launcher(ReceiptReviewScreen(userid: user.uid, scan: const ReceiptScan(lines: bon)))));
    await tester.tap(find.text('öffnen'));
    await pumpUntil(tester, find.textContaining('„Allgemein“ wird angelegt'));
    await tester.ensureVisible(find.text('Bestätigen und speichern'));
    await tester.tap(find.text('Bestätigen und speichern'));
    await pumpUntil(tester, find.text('result:true'));

    final booked = (await readDb(tester, () => TransactionRepository(db: db).getAllTransactions(user.uid))).single;
    expect(booked.category, 'Allgemein');
    final categories = await readDb(tester, () => CategoryRepository(db: db).getAllCategories(user.uid));
    expect(categories.where((c) => c.categoryName == 'Allgemein' && c.transactionType == TransactionType.expense), hasLength(1));
    await disposeApp(tester, db);
  });

  group('receipt photos', () {
    // 1×1-PNG
    final png = base64Decode('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==');

    /// Bildablage mit einem Foto unter `receipt_images/bon.png`.
    ReceiptImageStore storeWithPhoto() {
      final dir = Directory.systemTemp.createTempSync('lifehub_receipt_photo_');
      Directory('${dir.path}/receipt_images').createSync();
      File('${dir.path}/receipt_images/bon.png').writeAsBytesSync(png);
      return ReceiptImageStore(baseDir: () async => dir);
    }

    testWidgets('the review shows the photo from its relative path and the booking keeps that path', (tester) async {
      useTallScreen(tester);
      final user = await seedUser(tester);
      await tester.pumpWidget(testApp(
        db,
        launcher(ReceiptReviewScreen(userid: user.uid, scan: const ReceiptScan(imagePath: 'receipt_images/bon.png', lines: ['REWE', 'Summe 4,20']))),
        receiptImages: storeWithPhoto(),
      ));
      await tester.tap(find.text('öffnen'));
      await pumpUntil(tester, find.byType(Image));
      await tester.ensureVisible(find.text('Bestätigen und speichern'));
      await tester.tap(find.text('Bestätigen und speichern'));
      await pumpUntil(tester, find.text('result:true'));

      final booked = (await readDb(tester, () => TransactionRepository(db: db).getAllTransactions(user.uid))).single;
      expect(booked.imagePath, 'receipt_images/bon.png'); // relativ: übersteht Restore und Gerätewechsel
      await disposeApp(tester, db);
    });

    testWidgets('the booking editor shows the stored photo, and a hint when the file is gone', (tester) async {
      useTallScreen(tester);
      final user = await seedUser(tester);
      final booking = await seedDb(tester, db, () async {
        final repo = TransactionRepository(db: db);
        await repo.createTransaction(Transaction(
          date: DateTime(2026, 10, 5),
          amount: 4.2,
          category: 'Lebensmittel',
          description: 'REWE',
          account: 'Girokonto',
          transactionType: TransactionType.expense,
          userid: user.uid,
          imagePath: 'receipt_images/bon.png',
        ));
        return (await repo.getAllTransactions(user.uid)).single;
      });
      await tester.pumpWidget(testApp(db, AddUpdateTransaction(userid: user.uid, transaction: booking), receiptImages: storeWithPhoto()));
      await pumpUntil(tester, find.byType(Image));
      expect(find.text('Bild ändern'), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(testApp(db, AddUpdateTransaction(userid: user.uid, transaction: booking)));
      await pumpUntil(tester, find.text('Bild nicht mehr vorhanden'));
      expect(find.byType(Image), findsNothing);
      await disposeApp(tester, db);
    });

    testWidgets('a removed photo is deleted on save, but kept while another booking or a cancelled edit still uses it', (tester) async {
      useTallScreen(tester);
      final user = await seedUser(tester);
      final dir = Directory.systemTemp.createTempSync('lifehub_receipt_cleanup_');
      Directory('${dir.path}/receipt_images').createSync();
      final photo = File('${dir.path}/receipt_images/bon.png')..writeAsBytesSync(png);
      final store = ReceiptImageStore(baseDir: () async => dir);
      final repo = TransactionRepository(db: db);
      final halves = await seedDb(tester, db, () async {
        for (final name in ['REWE', 'dm']) {
          await repo.createTransaction(Transaction(
            date: DateTime(2026, 10, 5),
            amount: 4.2,
            category: 'Lebensmittel',
            description: name,
            account: 'Girokonto',
            transactionType: TransactionType.expense,
            userid: user.uid,
            imagePath: 'receipt_images/bon.png', // ein Bon, auf zwei Buchungen aufgeteilt
          ));
        }
        return repo.getAllTransactions(user.uid);
      });

      Future<void> removePhoto(Transaction booking, {required bool save}) async {
        await tester.pumpWidget(testApp(db, launcher(AddUpdateTransaction(userid: user.uid, transaction: booking)), receiptImages: store));
        await tester.tap(find.text('öffnen'));
        await pumpUntil(tester, find.byIcon(Icons.close));
        await tester.tap(find.byIcon(Icons.close));
        await tester.pump();
        if (save) {
          await pumpUntil(tester, find.text('Lebensmittel')); // Kategorien geladen, sonst schlägt die Prüfung fehl
          await tester.ensureVisible(find.text('Speichern'));
          await tester.tap(find.text('Speichern'));
          await pumpUntil(tester, find.text('result:true'));
        }
        await tester.pumpWidget(const SizedBox()); // Editor schließen (bei save = false: abbrechen)
        await settleDb(tester);
      }

      await removePhoto(halves[0], save: false);
      expect(photo.existsSync(), isTrue); // abgebrochen: Buchung hat das Bild noch

      await removePhoto(halves[0], save: true);
      expect(photo.existsSync(), isTrue); // die andere Buchung zeigt es noch

      await removePhoto(halves[1], save: true);
      for (var i = 0; i < 20 && photo.existsSync(); i++) {
        await settleDb(tester);
      }
      expect(photo.existsSync(), isFalse); // an keiner Buchung mehr → Datei weg
      await disposeApp(tester, db);
    });

    testWidgets('leaving the review without saving deletes the new photo', (tester) async {
      useTallScreen(tester);
      final user = await seedUser(tester);
      final dir = Directory.systemTemp.createTempSync('lifehub_receipt_cancel_');
      Directory('${dir.path}/receipt_images').createSync();
      final photo = File('${dir.path}/receipt_images/bon.png')..writeAsBytesSync(png);
      await tester.pumpWidget(testApp(
        db,
        TransactionView(user: user),
        receiptScanner: FakeReceiptScanner(bon, imagePath: 'receipt_images/bon.png'),
        receiptImages: ReceiptImageStore(baseDir: () async => dir),
      ));
      await pumpUntil(tester, find.byTooltip('Kassenzettel fotografieren'));
      await tester.tap(find.byTooltip('Kassenzettel fotografieren'));
      await pumpUntil(tester, find.text('Kassenzettel fotografieren'));
      await tester.tap(find.text('Kassenzettel fotografieren').last);
      await pumpUntil(tester, find.text('Bestätigen und speichern'));

      await pageBack(tester);
      await pumpUntilGone(tester, find.text('Kassenzettel prüfen'));
      for (var i = 0; i < 20 && photo.existsSync(); i++) {
        await settleDb(tester);
      }
      expect(photo.existsSync(), isFalse); // keine Buchung → kein liegengebliebenes Foto
      expect(await readDb(tester, () => TransactionRepository(db: db).getAllTransactions(user.uid)), isEmpty);
      await disposeApp(tester, db);
    });
  });

  /// Kauft über die Einkaufsliste ein (abhaken → Vorrat) – wie beim Einkaufen am Tag [at].
  Future<void> shop(int uid, DateTime at, List<(String, double)> items) async {
    final lists = ListsRepository(db: db, inventory: InventoryRepository(db: db));
    for (final (name, grams) in items) {
      await lists.addToList(uid, name: name, amount: grams, unit: 'g');
      final item = (await lists.getShopping(uid)).firstWhere((i) => i.name == name);
      await lists.moveToInventory(await lists.toggleShopping(item, at: at, bought: grams));
    }
  }

  testWidgets('receipt of a shopping day: compared with what was checked off, linked instead of added twice', (tester) async {
    useTallScreen(tester);
    final user = await seedUser(tester);
    await seedDb(tester, db, () async {
      await shop(user.uid, DateTime(2026, 10, 5, 17), [('Haferflocken', 500), ('Tofu', 200), ('Hackfleisch', 400)]);
      await shop(user.uid, DateTime(2026, 10, 4, 17), [('Bananen', 1000)]); // anderer Tag: wird nicht verglichen
    });
    await tester.pumpWidget(testApp(db, TransactionView(user: user), receiptScanner: FakeReceiptScanner(bon)));
    await pumpUntil(tester, find.byTooltip('Kassenzettel fotografieren'));
    await tester.tap(find.byTooltip('Kassenzettel fotografieren'));
    await pumpUntil(tester, find.text('Kassenzettel fotografieren'));
    await tester.tap(find.text('Kassenzettel fotografieren').last);
    await pumpUntil(tester, find.text('Bestätigen und speichern'));

    expect(find.text('ABGLEICH MIT DEINEM EINKAUF VOM 5.10.'), findsOneWidget);
    expect(find.text('2 von 3'), findsOneWidget);
    expect(find.text('Haferflocken – passt'), findsOneWidget);
    expect(find.text('Tofu: Vorrat 200 g · Bon 400 g'), findsOneWidget);
    expect(find.text('Hackfleisch: abgehakt, aber nicht auf dem Bon'), findsOneWidget);
    expect(find.textContaining('nur auf dem Bon'), findsOneWidget); // Bananen
    // Schon im Vorrat → nicht noch einmal anlegen
    expect(find.text('1 von 5'), findsOneWidget);
    expect(find.textContaining('Schon über die Einkaufsliste im Vorrat'), findsNWidgets(2));

    await tester.tap(find.text('Bon-Menge übernehmen'));
    await tester.pump();
    await tester.ensureVisible(find.text('Bestätigen und speichern'));
    await tester.tap(find.text('Bestätigen und speichern'));
    await pumpUntil(tester, find.textContaining('Buchung über 7,05 € gespeichert · 1 Artikel im Vorrat'));

    final tx = (await readDb(tester, () => TransactionRepository(db: db).getAllTransactions(user.uid))).single;
    final pantry = await readDb(tester, () => InventoryRepository(db: db).getItems(user.uid));
    final byName = {for (final i in pantry) i.name: i};
    expect(pantry, hasLength(5)); // Haferflocken, Tofu, Hackfleisch, Bananen (4.10.), Banane vom Bon
    expect((byName['Haferflocken']!.price, byName['Haferflocken']!.receiptTxId), (0.59, tx.id));
    expect((byName['Tofu']!.quantity, byName['Tofu']!.receiptTxId), (400.0, tx.id));
    expect(byName['Hackfleisch']!.receiptTxId, tx.id); // gehört zum Einkauf des Tages
    expect(byName['Bananen']!.receiptTxId, isNull); // 4.10. braucht seinen eigenen Bon
    expect(byName['Banane']!.receiptTxId, tx.id);
    await disposeApp(tester, db);
  });

  testWidgets('a receipt on a day without shopping compares nothing', (tester) async {
    useTallScreen(tester);
    final user = await seedUser(tester);
    await seedDb(tester, db, () => shop(user.uid, DateTime(2026, 10, 6, 17), [('Haferflocken', 500)]));
    await tester.pumpWidget(testApp(db, TransactionView(user: user), receiptScanner: FakeReceiptScanner(bon)));
    await pumpUntil(tester, find.byTooltip('Kassenzettel fotografieren'));
    await tester.tap(find.byTooltip('Kassenzettel fotografieren'));
    await pumpUntil(tester, find.text('Kassenzettel fotografieren'));
    await tester.tap(find.text('Kassenzettel fotografieren').last);
    await pumpUntil(tester, find.text('Bestätigen und speichern'));
    expect(find.textContaining('nichts von der Einkaufsliste in den Vorrat gewandert'), findsOneWidget);
    expect(find.text('3 von 5'), findsOneWidget); // wie bisher: Haferflocken, Tofu, Bananen
    await disposeApp(tester, db);
  });

  testWidgets('an existing booking gets its receipt from the editor; the hint about the missing receipt disappears', (tester) async {
    useTallScreen(tester);
    final user = await seedUser(tester);
    final now = DateTime.now();
    final day = DateTime(now.year, now.month, now.day, 9);
    final lines = ['REWE', 'TOFU NATUR 200G 1,79 A', 'Summe 1,79', DateFormat('dd.MM.yy HH:mm').format(day)];
    await seedDb(tester, db, () async {
      await shop(user.uid, day, [('Tofu', 200)]);
      await TransactionRepository(db: db).createTransaction(Transaction(
        date: day,
        amount: 2,
        category: 'Lebensmittel',
        description: 'Einkauf',
        account: 'Girokonto',
        transactionType: TransactionType.expense,
        userid: user.uid,
      ));
    });
    await tester.pumpWidget(testApp(db, FinanceHubScreen(user: user), receiptScanner: FakeReceiptScanner(lines)));
    await pumpUntil(tester, find.textContaining('Noch kein Kassenzettel'));

    final tx = (await readDb(tester, () => TransactionRepository(db: db).getAllTransactions(user.uid))).single;
    await tester.pumpWidget(testApp(db, AddUpdateTransaction(userid: user.uid, transaction: tx), receiptScanner: FakeReceiptScanner(lines)));
    await pumpUntil(tester, find.text('Kassenzettel scannen & abgleichen'));
    await tester.ensureVisible(find.text('Kassenzettel scannen & abgleichen'));
    await tester.tap(find.text('Kassenzettel scannen & abgleichen'));
    await pumpUntil(tester, find.text('Foto aus der Galerie'));
    await tester.tap(find.text('Foto aus der Galerie'));
    await pumpUntil(tester, find.text('Bestätigen und speichern'));
    expect(find.text('Tofu – passt'), findsOneWidget);
    await tester.ensureVisible(find.text('Bestätigen und speichern'));
    await tester.tap(find.text('Bestätigen und speichern'));
    await pumpUntil(tester, find.textContaining('Buchung über 1,79 € gespeichert'));

    final all = await readDb(tester, () => TransactionRepository(db: db).getAllTransactions(user.uid));
    expect(all.map((t) => (t.id, t.description, t.amount)), [(tx.id, 'REWE', 1.79)]); // ergänzt, nicht doppelt gebucht
    expect(await readDb(tester, () => InventoryRepository(db: db).tripsWithoutReceipt(user.uid)), isEmpty);
    await disposeApp(tester, db);
  });
}
