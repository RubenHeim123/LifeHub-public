import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:frontend/core/ui/app_actions.dart';
import 'package:frontend/core/ui/theme.dart';

Widget _app(Widget home) =>
    MaterialApp(theme: ThemeData(useMaterial3: true, extensions: const [AppColors.light]), home: home);

/// Nachbau der Startseite: schwebende Navigation (66 px) über dem Inhalt, Unterseite mit eigenem Scaffold.
Widget _shell(Widget page) => _app(Builder(
      builder: (context) => Scaffold(
        extendBody: true,
        body: NavBarInset(height: NavBarInset.heightFor(context), child: page),
        bottomNavigationBar: SafeArea(
          minimum: const EdgeInsets.fromLTRB(16, 0, 16, kNavBarMargin),
          child: Container(key: const ValueKey('nav'), height: kNavBarHeight, color: Colors.black12),
        ),
      ),
    ));

void main() {
  for (final inset in [0.0, 48.0]) {
    testWidgets('AppFab sits above the floating navigation (system inset $inset)', (tester) async {
      tester.view.physicalSize = const Size(360, 780);
      tester.view.devicePixelRatio = 1.0;
      tester.view.padding = FakeViewPadding(bottom: inset);
      tester.view.viewPadding = FakeViewPadding(bottom: inset);
      addTearDown(tester.view.reset);

      await tester.pumpWidget(_shell(Scaffold(floatingActionButton: AppFab(label: 'Neu', onPressed: () {}))));
      final fab = tester.getRect(find.byType(FloatingActionButton));
      final nav = tester.getRect(find.byKey(const ValueKey('nav')));
      expect(fab.bottom, lessThanOrEqualTo(nav.top - 8));
      expect(fab.right, greaterThan(300)); // rechts unten
    });
  }

  testWidgets('AppFab on a pushed page uses the normal position', (tester) async {
    tester.view.physicalSize = const Size(360, 780);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(_app(Scaffold(floatingActionButton: AppFab(tooltip: 'Neu', onPressed: () {}))));
    expect(tester.getRect(find.byType(FloatingActionButton)).bottom, greaterThan(740));
  });

  testWidgets('SwipeTile: delete with undo restores the item', (tester) async {
    final items = ['Bad putzen', 'Einkaufen'];
    await tester.pumpWidget(_app(StatefulBuilder(
      builder: (context, setState) => Scaffold(
        body: ListView(children: [
          for (final item in List.of(items))
            SwipeTile(
              id: item,
              onEdit: () {},
              onDelete: () => deleteWithUndo(
                context,
                label: item,
                delete: () async => items.remove(item),
                restore: () async => items.insert(0, item),
                onChanged: () => setState(() {}),
              ),
              child: ListTile(title: Text(item)),
            ),
        ]),
      ),
    )));

    await tester.drag(find.text('Bad putzen'), const Offset(-300, 0));
    await tester.pumpAndSettle();
    expect(find.text('Bearbeiten'), findsOneWidget);
    await tester.tap(find.text('Löschen'));
    await tester.pumpAndSettle();
    expect(find.text('Bad putzen'), findsNothing);
    expect(find.text('„Bad putzen“ gelöscht'), findsOneWidget);

    await tester.tap(find.text('Rückgängig'));
    await tester.pumpAndSettle();
    expect(find.text('Bad putzen'), findsOneWidget);
  });

  testWidgets('runGuarded shows errors as a snackbar instead of throwing', (tester) async {
    String? result = 'unverändert';
    await tester.pumpWidget(_app(Builder(
      builder: (context) => Scaffold(
        body: TextButton(
          onPressed: () async =>
              result = await runGuarded<String>(context, () async => throw Exception('Datenbank gesperrt')),
          child: const Text('los'),
        ),
      ),
    )));
    await tester.tap(find.text('los'));
    await tester.pumpAndSettle();
    expect(result, isNull);
    expect(find.text('Das hat nicht geklappt: Datenbank gesperrt'), findsOneWidget);
  });
}
