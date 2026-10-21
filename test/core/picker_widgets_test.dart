import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:frontend/core/models/repeat.dart';
import 'package:frontend/core/ui/form_widgets.dart';
import 'package:frontend/core/ui/hub_tabs.dart';
import 'package:frontend/core/ui/repeat_picker.dart';
import 'package:frontend/core/ui/theme.dart';

Widget _app(Widget child) => MaterialApp(
      theme: ThemeData(useMaterial3: true, extensions: const [AppColors.light]),
      home: Scaffold(body: SingleChildScrollView(child: child)),
    );

/// Hält den Wert wie ein Editor und baut den Picker damit neu.
class _RepeatHost extends StatefulWidget {
  final ValueChanged<Repeat> onValue;
  const _RepeatHost(this.onValue);

  @override
  State<_RepeatHost> createState() => _RepeatHostState();
}

class _RepeatHostState extends State<_RepeatHost> {
  Repeat _value = Repeat.none;

  @override
  Widget build(BuildContext context) => RepeatPicker(
        value: _value,
        start: DateTime(2026, 10, 7), // Mittwoch
        onChanged: (r) {
          setState(() => _value = r);
          widget.onValue(r);
        },
      );
}

void main() {
  testWidgets('RepeatPicker: weekly every 2 weeks on Mon and Wed; the last weekday cannot be removed', (tester) async {
    late Repeat value;
    await tester.pumpWidget(_app(_RepeatHost((r) => value = r)));
    expect(find.text('Alle'), findsNothing); // einmalig: keine Abstands-Auswahl

    await tester.tap(find.text('Wöchentlich'));
    await tester.pump();
    expect(find.text('Wöchentlich (Mi)'), findsOneWidget); // Startdatum gibt den Wochentag vor

    await tester.tap(find.byTooltip('Längerer Abstand'));
    await tester.pump();
    await tester.tap(find.text('Mo'));
    await tester.pump();
    expect((value.freq, value.interval), (RepeatFreq.weekly, 2));
    expect(value.weekdays, {1, 3});
    expect(find.text('Alle 2 Wochen (Mo, Mi)'), findsOneWidget);

    await tester.tap(find.text('Mo'));
    await tester.pump();
    await tester.tap(find.text('Mi'));
    await tester.pump();
    expect(value.weekdays, {3}); // mindestens ein Tag bleibt

    expect(tester.widget<IconButton>(find.widgetWithIcon(IconButton, Icons.remove_circle_outline)).onPressed, isNotNull);
    await tester.tap(find.byTooltip('Kürzerer Abstand'));
    await tester.pump();
    expect(tester.widget<IconButton>(find.widgetWithIcon(IconButton, Icons.remove_circle_outline)).onPressed, isNull);

    await tester.tap(find.text('Einmalig'));
    await tester.pump();
    expect(value.isNone, isTrue);
    expect(find.text('Alle'), findsNothing);
  });

  testWidgets('HubTabs shows the chosen section and builds only that one', (tester) async {
    var built = <String>[];
    await tester.pumpWidget(MaterialApp(
      theme: ThemeData(useMaterial3: true, extensions: const [AppColors.light]),
      home: HubTabs(initialIndex: 1, tabs: [
        for (final name in ['To-Dos', 'Termine', 'Habits'])
          HubTab(name, (_) {
            built.add(name);
            return Center(child: Text('Seite $name'));
          }),
      ]),
    ));
    expect(find.text('Seite Termine'), findsOneWidget);
    expect(built, ['Termine']);

    built = [];
    await tester.tap(find.text('Habits'));
    await tester.pump();
    expect(find.text('Seite Habits'), findsOneWidget);
    expect(find.text('Seite Termine'), findsNothing);
    expect(built, ['Habits']);
  });

  testWidgets('HubTabs scrolls the chosen section into view on a narrow phone (e.g. Journal from Heute)', (tester) async {
    tester.view.physicalSize = const Size(360, 780);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    const names = ['To-Dos', 'Termine', 'Einkauf', 'Habits', 'Geschenke', 'Journal'];
    await tester.pumpWidget(MaterialApp(
      theme: ThemeData(useMaterial3: true, extensions: const [AppColors.light]),
      home: HubTabs(initialIndex: 5, tabs: [for (final n in names) HubTab(n, (_) => Center(child: Text('Seite $n')))]),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Seite Journal'), findsOneWidget);
    final chip = tester.getRect(find.text('Journal'));
    expect(chip.right, lessThanOrEqualTo(360)); // der aktive Chip ist sichtbar
    expect(chip.left, greaterThanOrEqualTo(0));

    await tester.tap(find.text('Habits'));
    await tester.pumpAndSettle();
    final habits = tester.getRect(find.text('Habits'));
    expect(habits.left, greaterThanOrEqualTo(0));
    expect(habits.right, lessThanOrEqualTo(360));
  });

  testWidgets('icon picker: search, pick, the field shows the chosen icon (name, codepoint, font)', (tester) async {
    final controller = TextEditingController(text: 'home_outlined');
    (int, String)? picked;
    await tester.pumpWidget(_app(IconPickerField(controller: controller, onPicked: (cp, font) => picked = (cp, font))));
    expect(find.byIcon(Icons.home_outlined), findsOneWidget);
    expect(find.text('Icon ändern'), findsOneWidget);

    await tester.tap(find.text('Icon ändern'));
    await tester.pumpAndSettle();
    expect(find.text('Wähle ein Icon'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'shopping cart');
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.shopping_cart_outlined), findsOneWidget);
    expect(find.byIcon(Icons.account_balance), findsNothing);
    await tester.tap(find.byIcon(Icons.shopping_cart_outlined));
    await tester.pumpAndSettle();

    expect(controller.text, 'shopping_cart_outlined');
    expect(picked, (Icons.shopping_cart_outlined.codePoint, 'MaterialIcons'));
    expect(find.byIcon(Icons.shopping_cart_outlined), findsOneWidget);
    controller.dispose();
  });
}
