import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'package:frontend/app/home_shell.dart';
import 'package:frontend/core/database/database.dart';
import 'package:frontend/core/ui/app_ui.dart';
import 'package:frontend/core/ui/hub_tabs.dart';
import 'package:frontend/features/fitness/screens/nutrition_screen.dart';
import 'package:frontend/features/fitness/screens/training_screen.dart';
import 'package:frontend/features/habits/screens/habit_tracker_screen.dart';
import 'package:frontend/features/lists/screens/shopping_list_screen.dart';
import 'package:frontend/features/style/screens/outfit_editor_screen.dart';
import 'package:frontend/features/style/screens/wishlist_screen.dart';
import 'package:frontend/features/todos/screens/todo_list_screen.dart';

import '../helpers/test_app.dart';

void main() {
  setUpAll(() => initializeDateFormatting('de_DE'));

  Future<DatabaseService> openShell(WidgetTester tester, Size size, {double textScale = 1.0}) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    tester.platformDispatcher.textScaleFactorTestValue = textScale;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final db = createTestDatabase();
    await seedDb(tester, db, () => createTestUser(db, email: 'shell@test.de'));
    FlutterSecureStorage.setMockInitialValues({'email': 'shell@test.de'});
    await tester.pumpWidget(testApp(db, const HomeShell(email: 'shell@test.de')));
    await pumpUntil(tester, find.text('Habits heute'));
    return db;
  }

  Future<void> tapTab(WidgetTester tester, String label) async {
    await tester.tap(find.descendant(of: find.byType(FrostedPill), matching: find.text(label)));
    await tester.pump();
  }

  testWidgets('six tabs fit on a 360 dp phone with large text, each opens its area', (tester) async {
    final db = await openShell(tester, const Size(360, 780), textScale: 1.3);
    expect(tester.takeException(), isNull);

    for (final (tab, content) in [
      ('Planen', find.byType(TodoListScreen)),
      ('Essen', find.byType(NutritionScreen)),
      ('Training', find.byType(TrainingScreen)),
      ('Geld', find.text('Gesamtbilanz')),
      ('Mehr', find.text('Kontakte')),
      ('Heute', find.text('Habits heute')),
    ]) {
      await tapTab(tester, tab);
      await pumpUntil(tester, content);
      expect(tester.takeException(), isNull, reason: tab);
      if (tab != 'Heute') {
        // Genau ein Seitenkopf: Tab-Titel bzw. der eigene Kopf von Finanzen – keine Doppelung mehr
        expect(find.byType(TabTitle).evaluate().length + find.byType(ScreenHeader).evaluate().length, 1, reason: tab);
      }
    }
    // Alle Beschriftungen stehen in der Leiste, nicht nur die des aktiven Tabs
    for (final label in ['Heute', 'Planen', 'Essen', 'Training', 'Geld', 'Mehr']) {
      expect(find.text(label), findsWidgets, reason: label);
    }
    await disposeApp(tester, db);
  });

  testWidgets('a tab remembers its area; tapping the active tab again goes back to the first', (tester) async {
    final db = await openShell(tester, const Size(1200, 2800));

    await tapTab(tester, 'Essen');
    await pumpUntil(tester, find.byType(NutritionScreen));
    await tester.tap(find.text('Einkauf'));
    await pumpUntil(tester, find.byType(ShoppingListScreen));

    await tapTab(tester, 'Heute');
    await pumpUntil(tester, find.text('Habits heute'));
    await tapTab(tester, 'Essen');
    await pumpUntil(tester, find.byType(ShoppingListScreen));

    await tapTab(tester, 'Essen');
    await pumpUntil(tester, find.byType(NutritionScreen));
    await disposeApp(tester, db);
  });

  testWidgets('Planen holds To-Dos, Habits, Termine and Journal; Heute jumps straight into Habits', (tester) async {
    final db = await openShell(tester, const Size(1200, 2800));

    await tester.tap(find.text('Heute sind keine Habits geplant.'));
    await pumpUntil(tester, find.byType(HabitTrackerScreen));
    for (final chip in ['To-Dos', 'Habits', 'Termine', 'Journal']) {
      expect(find.widgetWithText(InkWell, chip), findsWidgets, reason: chip);
    }
    expect(find.text('Einkauf'), findsNothing); // zieht zu Essen
    await disposeApp(tester, db);
  });

  testWidgets('Mehr opens each page with its add button above the navigation', (tester) async {
    final db = await openShell(tester, const Size(360, 780));

    Future<void> openTile(String tile, Finder ready) async {
      await tapTab(tester, 'Mehr');
      await pumpUntil(tester, find.text(tile).hitTestable());
      await tester.tap(find.text(tile));
      await pumpUntil(tester, ready);
    }

    await openTile('Outfits', find.text('Noch keine Outfits'));
    await tester.tap(find.text('Outfit'));
    await pumpUntil(tester, find.byType(OutfitEditorScreen));
    await pageBack(tester);
    await pumpUntilGone(tester, find.byType(OutfitEditorScreen));
    await pageBack(tester);

    await openTile('Wunschliste', find.text('Keine offenen Wünsche'));
    await tester.tap(find.text('Wunsch'));
    await pumpUntil(tester, find.byType(WishEditorScreen));
    await pageBack(tester);
    await pumpUntilGone(tester, find.byType(WishEditorScreen));
    await pageBack(tester);

    for (final (tile, fab, sheet) in [
      ('Geschenke', 'Liste', 'Neue Geschenkeliste'),
      ('Kontakte', 'Kontakt', 'Neuer Kontakt'),
      ('Lernen', 'Stapel', 'Neuer Stapel'),
    ]) {
      await openTile(tile, find.text(fab).hitTestable());
      await tester.tap(find.text(fab));
      await pumpUntil(tester, find.text(sheet));
      await tester.binding.handlePopRoute(); // Sheet mit Zurück schließen
      await pumpUntilGone(tester, find.text(sheet));
      await pageBack(tester);
    }

    await openTile('Kleiderschrank', find.text('Kleiderschrank').hitTestable());
    expect(tester.takeException(), isNull);
    await disposeApp(tester, db);
  });
}
