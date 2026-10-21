import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:frontend/core/database/database.dart';
import 'package:frontend/core/ui/dictation_overlay.dart';
import 'package:frontend/features/todos/repositories/todo_repository.dart';
import 'package:frontend/features/todos/screens/add_update_todo_screen.dart';

import '../helpers/test_app.dart';

/// Formular mit normalem Feld, Passwort und schreibgeschütztem Feld.
class _Form extends StatelessWidget {
  final TextEditingController notes;
  final ValueChanged<String> onChanged;
  const _Form({required this.notes, required this.onChanged});

  @override
  Widget build(BuildContext context) => Scaffold(
        body: Column(children: [
          TextField(key: const Key('notes'), controller: notes, onChanged: onChanged),
          const TextField(key: Key('password'), obscureText: true),
          const TextField(key: Key('readonly'), readOnly: true),
        ]),
      );
}

void main() {
  late DatabaseService db;
  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    db = createTestDatabase();
  });

  final mic = find.byKey(DictationOverlay.micKey);

  testWidgets('the mic appears for a focused field and inserts the dictated words at the cursor', (tester) async {
    final notes = TextEditingController(text: 'Einkaufen: Käse');
    final changes = <String>[];
    await tester.pumpWidget(testApp(db, _Form(notes: notes, onChanged: changes.add), dictation: FakeDictation(words: 'brot und milch')));
    expect(mic, findsNothing); // ohne Fokus kein Knopf

    await tester.tap(find.byKey(const Key('notes')));
    await tester.pump();
    notes.selection = const TextSelection.collapsed(offset: 'Einkaufen:'.length); // Cursor hinter dem Doppelpunkt
    await tester.pump();
    expect(mic, findsOneWidget);

    await tester.tap(mic);
    await tester.pump();
    expect(notes.text, 'Einkaufen: brot und milch Käse'); // Leerzeichen passend ergänzt
    expect(changes.last, notes.text); // wie getippt: onChanged wurde gerufen
    expect(notes.selection.baseOffset, 'Einkaufen: brot und milch'.length);
    await disposeApp(tester, db);
  });

  testWidgets('a sentence start is capitalised; password and read-only fields get no mic', (tester) async {
    final notes = TextEditingController();
    await tester.pumpWidget(testApp(db, _Form(notes: notes, onChanged: (_) {}), dictation: FakeDictation(words: 'heute war ein guter tag')));
    await tester.tap(find.byKey(const Key('notes')));
    await tester.pump();
    await tester.tap(mic);
    await tester.pump();
    expect(notes.text, 'Heute war ein guter tag'); // Satzanfang groß

    await tester.tap(find.byKey(const Key('password')));
    await tester.pump();
    expect(mic, findsNothing);
    await tester.tap(find.byKey(const Key('readonly')));
    await tester.pump();
    expect(mic, findsNothing);
    await disposeApp(tester, db);
  });

  testWidgets('without speech recognition or microphone permission a hint is shown', (tester) async {
    final notes = TextEditingController();
    await tester.pumpWidget(testApp(db, _Form(notes: notes, onChanged: (_) {}), dictation: FakeDictation(available: false)));
    await tester.tap(find.byKey(const Key('notes')));
    await tester.pump();
    await tester.tap(mic);
    await tester.pump();
    expect(find.textContaining('Diktieren ist nicht verfügbar'), findsOneWidget);
    expect(notes.text, isEmpty);
    await disposeApp(tester, db);
  });

  testWidgets('a whole editor can be filled by voice: dictated to-do is saved', (tester) async {
    useTallScreen(tester);
    final user = await seedDb(tester, db, () => createTestUser(db));
    final dictation = FakeDictation(words: 'zahnarzt anrufen');
    await tester.pumpWidget(testApp(db, launcher(AddUpdateTodoScreen(userid: user.uid)), dictation: dictation));
    await tester.tap(find.text('öffnen'));
    await pumpUntil(tester, find.text('Hinzufügen'));

    await tester.tap(find.byType(TextFormField).first);
    await tester.pump();
    await tester.tap(mic);
    await tester.pump();
    expect(find.text('Zahnarzt anrufen'), findsOneWidget);

    await tester.ensureVisible(find.text('Hinzufügen'));
    await tester.tap(find.text('Hinzufügen'));
    await pumpUntil(tester, find.text('result:true'));
    final todos = await readDb(tester, () => TodoRepository(db: db).getAllTodos(user.uid));
    expect(todos.single.title, 'Zahnarzt anrufen');
    await disposeApp(tester, db);
  });

  testWidgets('while a field is focused the app gets room above the keyboard for the mic', (tester) async {
    final notes = TextEditingController();
    double? inset;
    await tester.pumpWidget(testApp(
      db,
      Builder(builder: (context) {
        inset = MediaQuery.viewInsetsOf(context).bottom; // ein Scaffold verkleinert damit seinen Inhalt
        return Scaffold(body: TextField(key: const Key('notes'), controller: notes));
      }),
    ));
    expect(inset, 0);
    await tester.tap(find.byKey(const Key('notes')));
    await tester.pump();
    expect(inset, DictationOverlay.barHeight); // Inhalt rückt über den Knopf
    expect(notes.text, isEmpty); // Feld bleibt erhalten und fokussiert
    expect(FocusManager.instance.primaryFocus?.context?.widget, isA<Focus>());
    await disposeApp(tester, db);
  });

  testWidgets('when nothing was understood the user is told so', (tester) async {
    final notes = TextEditingController(text: 'Bleibt');
    await tester.pumpWidget(testApp(db, _Form(notes: notes, onChanged: (_) {}), dictation: FakeDictation(words: '')));
    await tester.tap(find.byKey(const Key('notes')));
    await tester.pump();
    await tester.tap(mic);
    await tester.pump();
    expect(find.textContaining('Nichts verstanden'), findsOneWidget);
    expect(notes.text, 'Bleibt');
    await disposeApp(tester, db);
  });

  testWidgets('without keyboard the mic stays above the system navigation bar', (tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1.0;
    tester.view.padding = const FakeViewPadding(bottom: 48);
    tester.view.viewPadding = const FakeViewPadding(bottom: 48);
    addTearDown(tester.view.reset);
    final notes = TextEditingController();
    await tester.pumpWidget(testApp(db, _Form(notes: notes, onChanged: (_) {})));
    await tester.tap(find.byKey(const Key('notes')));
    await tester.pump();
    expect(tester.getRect(mic).bottom, lessThanOrEqualTo(800 - 48)); // nicht hinter der Gestenleiste
    await disposeApp(tester, db);
  });

  testWidgets('for screen readers the mic is a small button, not the whole screen', (tester) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(testApp(db, _Form(notes: TextEditingController(), onChanged: (_) {})));
    await tester.tap(find.byKey(const Key('notes')));
    await tester.pump();
    final node = tester.getSemantics(find.byKey(DictationOverlay.micKey));
    expect(node.label, 'Diktieren');
    expect(node.rect.width, lessThan(100));
    expect(node.rect.height, lessThan(100));
    handle.dispose();
    await disposeApp(tester, db);
  });
}
