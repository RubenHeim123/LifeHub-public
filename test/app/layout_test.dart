import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'package:frontend/app/app_tabs.dart';
import 'package:frontend/core/database/database.dart';
import 'package:frontend/core/ui/app_actions.dart';
import 'package:frontend/features/auth/models/user.dart';
import 'package:frontend/features/calendar/models/appointment.dart';
import 'package:frontend/features/calendar/repositories/appointment_repository.dart';
import 'package:frontend/features/calendar/screens/add_update_appointment_screen.dart';
import 'package:frontend/features/contacts/models/contact.dart';
import 'package:frontend/features/contacts/repositories/contact_repository.dart';
import 'package:frontend/features/contacts/screens/contact_screen.dart';
import 'package:frontend/features/dashboard/screens/home.dart';
import 'package:frontend/features/finance/screens/account_view.dart';
import 'package:frontend/features/finance/screens/add_update_financial_goal.dart';
import 'package:frontend/features/finance/screens/backups_screen.dart';
import 'package:frontend/features/finance/screens/sync_hub_screen.dart';
import 'package:frontend/features/finance/screens/category_view.dart';
import 'package:frontend/features/finance/screens/financial_goals_view.dart';
import 'package:frontend/features/finance/screens/fixedtransaction_view.dart';
import 'package:frontend/features/finance/screens/transaction_view.dart';
import 'package:frontend/features/fitness/screens/catalog_screen.dart';
import 'package:frontend/features/fitness/screens/progress_screen.dart';
import 'package:frontend/features/fitness/screens/sample_plans_screen.dart';
import 'package:frontend/features/lists/screens/gifts_screen.dart';
import 'package:frontend/features/meals/screens/recipes_screen.dart';
import 'package:frontend/features/vision/screens/vision_board_screen.dart';
import 'package:frontend/features/finance/screens/add_update_transactions.dart';
import 'package:frontend/features/finance/screens/finance_hub_screen.dart';
import 'package:frontend/features/food/screens/food_hub_screen.dart';
import 'package:frontend/features/fitness/screens/training_screen.dart';
import 'package:frontend/core/ui/hub_tabs.dart';
import 'package:frontend/features/more/more_screen.dart';
import 'package:frontend/features/fitness/screens/workout_editor_screen.dart';
import 'package:frontend/features/habits/screens/add_habit_screen.dart';
import 'package:frontend/features/inventory/models/inventory_item.dart';
import 'package:frontend/features/inventory/repositories/inventory_repository.dart';
import 'package:frontend/features/inventory/screens/item_editor_screen.dart';
import 'package:frontend/features/lists/models/lists.dart';
import 'package:frontend/features/lists/repositories/lists_repository.dart';
import 'package:frontend/features/meals/screens/recipe_editor_screen.dart';
import 'package:frontend/features/planning/screens/planning_hub_screen.dart';
import 'package:frontend/features/fitness/models/nutrition.dart';
import 'package:frontend/features/fitness/screens/food_editor_screen.dart';
import 'package:frontend/features/meals/catalog/recipe_catalog.dart';
import 'package:frontend/features/meals/screens/portion_planner_screen.dart';
import 'package:frontend/features/journal/models/journal_entry.dart';
import 'package:frontend/features/journal/repositories/journal_repository.dart';
import 'package:frontend/features/journal/screens/journal_editor_screen.dart';
import 'package:frontend/features/learning/models/flash_card.dart';
import 'package:frontend/features/learning/repositories/learning_repository.dart';
import 'package:frontend/features/learning/screens/deck_screen.dart';
import 'package:frontend/features/learning/screens/study_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:frontend/features/receipts/screens/receipt_review_screen.dart';
import 'package:frontend/features/receipts/services/receipt_scanner.dart';
import 'package:frontend/features/todos/models/todo.dart';
import 'package:frontend/features/todos/repositories/todo_repository.dart';
import 'package:frontend/features/todos/screens/add_update_todo_screen.dart';

import '../helpers/test_app.dart';

/// Jeder Screen auf einem kleinen Handy (360 × 780 dp), mit großer Schrift (130 %) und
/// Gestennavigation (48 px Systemleiste): kein Overflow, keine Ausnahme.
void main() {
  late DatabaseService db;

  setUpAll(() => initializeDateFormatting('de_DE'));
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    db = createTestDatabase();
  });

  const long = 'Ein ziemlich langer Name, der auf schmalen Handys umbrechen muss';

  void smallPhone(WidgetTester tester) {
    tester.view.physicalSize = const Size(360, 780);
    tester.view.devicePixelRatio = 1.0;
    tester.view.padding = const FakeViewPadding(bottom: 48);
    tester.view.viewPadding = const FakeViewPadding(bottom: 48);
    tester.platformDispatcher.textScaleFactorTestValue = 1.3;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  }

  Future<UserModel> seed(WidgetTester tester) => seedDb(tester, db, () async {
        final u = await createTestUser(db);
        final now = DateTime.now();
        await TodoRepository(db: db).createTodo(Todo(title: long, userid: u.uid, dueDate: now));
        await AppointmentRepository(db: db)
            .createAppointment(Appointment(title: long, date: DateTime(now.year, now.month, now.day, 23, 59), userid: u.uid)); // heute, auch kurz vor Mitternacht
        final lists = ListsRepository(db: db, inventory: InventoryRepository(db: db));
        await lists.saveShopping(ShoppingItem(userid: u.uid, name: long, quantity: '1500 g'));
        await lists.saveGiftList(GiftList(userid: u.uid, person: long, occasion: 'Geburtstag', date: now));
        await InventoryRepository(db: db)
            .createItem(InventoryItem(userid: u.uid, kind: InventoryKind.food, name: long, expiryDate: now));
        await InventoryRepository(db: db)
            .createItem(InventoryItem(userid: u.uid, kind: InventoryKind.clothing, name: long, size: 'XXL'));
        await JournalRepository(db: db).saveEntry(JournalEntry(
          userid: u.uid,
          date: now,
          mood: Mood.great,
          text: '$long. $long',
          answers: {JournalEntry.prompts[0]: long},
        ));
        return u;
      });

  /// Seite wie in der App: unter der schwebenden Navigation.
  Widget inShell(Widget page) => Builder(
        builder: (context) => Scaffold(
          extendBody: true,
          body: NavBarInset(height: NavBarInset.heightFor(context), child: page),
          bottomNavigationBar: const SafeArea(
            minimum: EdgeInsets.fromLTRB(16, 0, 16, kNavBarMargin),
            child: SizedBox(height: kNavBarHeight),
          ),
        ),
      );

  Future<void> check(WidgetTester tester, Widget page, Finder ready, {bool dark = false}) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(testApp(db, page, dark: dark));
    await pumpUntil(tester, ready);
    expect(tester.takeException(), isNull);
    // Auch weiter unten liegende Inhalte aufbauen lassen und prüfen
    final scrollables = find.byWidgetPredicate((w) => w is Scrollable && w.axisDirection == AxisDirection.down);
    for (var i = 0; i < 4 && scrollables.evaluate().isNotEmpty; i++) {
      await tester.drag(scrollables.first, const Offset(0, -700), warnIfMissed: false);
      await tester.pump(const Duration(milliseconds: 300));
    }
    expect(tester.takeException(), isNull);
  }

  testWidgets('tab pages', (tester) async {
    smallPhone(tester);
    final user = await seed(tester);

    await check(tester, inShell(Home(user: user)), find.text('Habits heute'));
    for (final (section, ready) in [
      (PlanSection.todos, find.textContaining('Ein ziemlich langer')),
      (PlanSection.habits, find.text('Habits')),
      (PlanSection.appointments, find.textContaining('Ein ziemlich langer')),
      (PlanSection.journal, find.text('Stimmung · 30 Tage')),
    ]) {
      await check(tester, inShell(PlanningHubScreen(user: user, initialSection: section)), ready);
    }
    for (final (section, ready) in [
      (FoodSection.nutrition, find.text('Heute')),
      (FoodSection.mealPlan, find.text('Mittagessen')),
      (FoodSection.shopping, find.textContaining('Ein ziemlich langer', findRichText: true)),
      (FoodSection.pantry, find.textContaining('Ein ziemlich langer')),
    ]) {
      await check(tester, inShell(FoodHubScreen(user: user, initialSection: section)), ready);
    }
    await check(tester, inShell(TabPage(title: 'Training', child: TrainingScreen(user: user))), find.text('Mein Training'));
    await check(tester, inShell(MoreScreen(user: user)), find.text('Kleiderschrank'));
    for (final (section, ready) in [
      (MoreSection.gifts, find.textContaining('Ein ziemlich langer')),
      (MoreSection.wardrobe, find.textContaining('Ein ziemlich langer')),
      (MoreSection.outfits, find.text('Noch keine Outfits')),
      (MoreSection.wishlist, find.text('Keine offenen Wünsche')),
    ]) {
      await check(tester, MoreSectionPage(user: user, section: section), ready);
    }
    await check(tester, inShell(FinanceHubScreen(user: user)), find.text('Finanzen'));
    await disposeApp(tester, db);
  });

  testWidgets('editors', (tester) async {
    smallPhone(tester);
    final user = await seed(tester);
    final uid = user.uid;

    await check(tester, AddUpdateTodoScreen(userid: uid), find.byType(TextFormField));
    await check(tester, AddUpdateAppointmentScreen(userid: uid), find.text('Als Geburtstag'));
    await check(tester, AddHabitScreen(userid: uid), find.byType(TextFormField));
    await check(tester, ItemEditorScreen(userid: uid, kind: InventoryKind.food), find.text('Lebensmittel hinzufügen'));
    await check(tester, ItemEditorScreen(userid: uid, kind: InventoryKind.clothing), find.text('Kleidung hinzufügen'));
    await check(tester, WorkoutEditorScreen(userid: uid), find.text('Neues Workout'));
    await check(tester, RecipeEditorScreen(userid: uid), find.text('Neues Rezept'));
    await check(tester, JournalEditorScreen(userid: uid), find.text('Eintrag bearbeiten'));
    // Bearbeiten: drei Knöpfe (Speichern, Abbrechen, Löschen) auf schmalem Handy
    final todo = (await readDb(tester, () => TodoRepository(db: db).getAllTodos(uid))).first;
    await check(tester, AddUpdateTodoScreen(userid: uid, todo: todo), find.text('Löschen'));
    await check(tester, AddUpdateTransaction(userid: uid), find.byType(TextFormField));
    await check(
      tester,
      ReceiptReviewScreen(
        userid: uid,
        scan: const ReceiptScan(lines: [
          'ALDI SÜD',
          'BIO VOLLKORN-DINKEL-SPAGHETTI MIT EINEM SEHR LANGEN NAMEN 500G 1,29 A',
          'BANANEN 1,78 A',
          'Summe 3,07',
        ]),
      ),
      find.text('BUCHUNG'),
    );
    await disposeApp(tester, db);
  });

  testWidgets('pushed lists', (tester) async {
    smallPhone(tester);
    final user = await seed(tester);
    final uid = user.uid;
    final giftListId = (await readDb(
      tester,
      () => ListsRepository(db: db, inventory: InventoryRepository(db: db)).getGiftLists(uid),
    )).single.id!;

    await check(tester, AccountView(user: user), find.text('Konten'));
    await check(tester, CategoryView(user: user), find.text('Kategorien'));
    await check(tester, FixedTransactionView(user: user), find.byType(AppFab));
    await check(tester, TransactionView(user: user), find.byType(AppFab));
    await check(tester, FinancialGoalsView(user: user), find.byType(AppFab));
    await check(tester, RecipesScreen(userid: uid), find.text('Overnight Oats mit Beeren'));
    await check(tester, GiftListScreen(listId: giftListId), find.text('Idee'));
    await check(tester, CatalogScreen(userid: uid), find.byType(TextField));
    await check(tester, SamplePlansScreen(userid: uid), find.text('Basisprogramm'));
    await check(tester, ProgressScreen(userid: uid), find.byType(Scaffold));
    await check(tester, VisionBoardScreen(user: user), find.text('Meine Ziele'));
    await readDb(tester, db.backupNow);
    await check(tester, const BackupsScreen(), find.textContaining('Von Hand gesichert'));
    await check(tester, const BackupsScreen(), find.textContaining('Von Hand gesichert'), dark: true);
    await disposeApp(tester, db);
  });

  testWidgets('dark mode: main screens and editors render without errors', (tester) async {
    smallPhone(tester);
    final user = await seed(tester);
    final uid = user.uid;

    await check(tester, inShell(Home(user: user)), find.text('Habits heute'), dark: true);
    await check(tester, inShell(PlanningHubScreen(user: user, initialSection: PlanSection.todos)),
        find.textContaining('Ein ziemlich langer'), dark: true);
    await check(tester, inShell(FoodHubScreen(user: user, initialSection: FoodSection.pantry)),
        find.textContaining('Ein ziemlich langer'), dark: true);
    await check(tester, inShell(MoreScreen(user: user)), find.text('Kleiderschrank'), dark: true);
    await check(tester, inShell(FinanceHubScreen(user: user)), find.text('Finanzen'), dark: true);
    await check(tester, SyncHubScreen(user: user), find.text('Sicherungen & Wiederherstellen'), dark: true);
    await check(tester, FinancialGoalsView(user: user), find.text('Noch keine Sparziele'), dark: true);
    await check(tester, AddUpdateFinancialGoal(user: user), find.text('Konten verknüpfen'.toUpperCase()), dark: true);
    await check(tester, AddHabitScreen(userid: uid), find.text('Wochentags'), dark: true);
    await check(tester, AddUpdateAppointmentScreen(userid: uid), find.text('Als Geburtstag'), dark: true);
    await check(tester, RecipeEditorScreen(userid: uid), find.text('Neues Rezept'), dark: true);
    await check(tester, inShell(PlanningHubScreen(user: user, initialSection: PlanSection.journal)),
        find.text('Stimmung · 30 Tage'), dark: true);
    await check(tester, JournalEditorScreen(userid: uid), find.text('Eintrag bearbeiten'), dark: true);
    await disposeApp(tester, db);
  });

  testWidgets('cook planner: portions, time and the ingredients step fit a small phone, light and dark', (tester) async {
    smallPhone(tester);
    final user = await seed(tester);
    final recipe = catalogRecipe('chili-sin-carne')!;
    await seedDb(tester, db, () => InventoryRepository(db: db)
        .createItem(InventoryItem(userid: user.uid, kind: InventoryKind.food, name: 'Rote Linsen', quantity: 0.05, unit: 'kg')));
    for (final dark in [false, true]) {
      await check(tester, PortionPlannerScreen(userid: user.uid, recipe: recipe, initialDate: DateTime.now()), find.text('Portionen'), dark: dark);
      await tester.tap(find.widgetWithText(ElevatedButton, 'Weiter: Zutaten prüfen'));
      await pumpUntil(tester, find.textContaining('auf die Einkaufsliste'));
      expect(tester.takeException(), isNull);
      final list = find.byType(Scrollable).first;
      for (var i = 0; i < 4; i++) {
        await tester.drag(list, const Offset(0, -700), warnIfMissed: false);
        await tester.pump(const Duration(milliseconds: 300));
      }
      expect(tester.takeException(), isNull);
    }
    await disposeApp(tester, db);
  });

  testWidgets('photo review: food editor with photo and a long hint fits a small phone, light and dark', (tester) async {
    smallPhone(tester);
    final user = await seed(tester);
    final png = base64Decode('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==');
    for (final dark in [false, true]) {
      await check(
        tester,
        FoodEditorScreen(
          userid: user.uid,
          draft: Food(userid: user.uid, name: long, per100: const Macros(kcal: 150, protein: 7, carbs: 20, fat: 5), servingGrams: 400),
          photo: png,
          photoHint: 'Geschätzt aus dem Foto – bitte prüfen: etwa 400 g, 600 kcal. Erkannt: 250 g Spaghetti, 150 g Bolognese-Soße, Parmesan.',
        ),
        find.text('Nährwerte pro 100 g'),
        dark: dark,
      );
    }
    await disposeApp(tester, db);
  });

  testWidgets('learning: decks, a deck and the study round fit a small phone, light and dark', (tester) async {
    smallPhone(tester);
    final user = await seed(tester);
    final repo = LearningRepository(db: db);
    final deckId = await seedDb(tester, db, () async {
      final id = await repo.saveDeck(Deck(userid: user.uid, name: long));
      await repo.importCards(user.uid, id, '$long – $long\nkurz – auch kurz');
      return id;
    });
    final deck = (await readDb(tester, () => repo.getDecks(user.uid))).single;
    for (final dark in [false, true]) {
      await check(tester, MoreSectionPage(user: user, section: MoreSection.learning), find.text('2 Karten fällig'), dark: dark);
      await check(tester, DeckScreen(userid: user.uid, deckId: deckId), find.text('2 fällig'), dark: dark);
      await check(tester, StudyScreen(userid: user.uid, deck: deck), find.text('Antwort zeigen'), dark: dark);
      await tester.tap(find.text('Antwort zeigen'));
      await pumpUntil(tester, find.text('Leicht'));
      expect(tester.takeException(), isNull);
    }
    await disposeApp(tester, db);
  });

  testWidgets('contacts: list, a full contact with notes and the Menschen section on Heute fit a small phone, light and dark', (tester) async {
    smallPhone(tester);
    final user = await seed(tester);
    final now = DateTime.now();
    final repo = ContactRepository(db: db, notifications: RecordingNotifications(), appointments: AppointmentRepository(db: db, notifications: RecordingNotifications()));
    final id = await seedDb(tester, db, () async {
      final id = await repo.saveContact(Contact(
        userid: user.uid,
        name: long,
        nickname: 'Spitzname mit Länge',
        relation: 'Arbeitskollegin aus dem Nachbarteam',
        phone: '+49 170 1234567890',
        email: 'eine.sehr.lange.adresse@beispiel-firma.de',
        address: 'Lange Straße 123, 12345 Irgendwo an der Weinstraße',
        birthday: DateTime(1990, now.month, now.day + 2),
        notes: '$long. $long',
      ));
      await repo.saveNote(ContactNote(userid: user.uid, contactId: id, text: long, date: now, followUp: true, created: now));
      await repo.saveNote(ContactNote(userid: user.uid, contactId: id, text: long, date: now.subtract(const Duration(days: 1)), followUp: true, created: now));
      await repo.saveNote(ContactNote(userid: user.uid, contactId: id, text: long, created: now));
      return id;
    });
    for (final dark in [false, true]) {
      await check(tester, MoreSectionPage(user: user, section: MoreSection.contacts), find.textContaining('Geburtstag in 2 Tagen'), dark: dark);
      await check(tester, ContactScreen(contactId: id), find.text('Geschenkliste'), dark: dark);
      await tester.drag(find.byType(Scrollable).first, const Offset(0, 3000));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.text('Neue Notiz'), 200, scrollable: find.byType(Scrollable).first);
      await tester.enterText(find.widgetWithText(TextField, 'Neue Notiz'), 'nächste Woche Mittwoch $long');
      await tester.pump();
      expect(tester.takeException(), isNull);
      await check(tester, inShell(Home(user: user)), find.text('Habits heute'), dark: dark);
    }
    await disposeApp(tester, db);
  });
}
