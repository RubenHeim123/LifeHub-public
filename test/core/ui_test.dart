import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:frontend/core/ui/app_ui.dart';
import 'package:frontend/core/ui/dialogs.dart';

void main() {
  group('formatEuro', () {
    test('uses German separators', () {
      expect(formatEuro(8412.5, decimals: 2), '8.412,50 €');
      expect(formatEuro(1234567), '1.234.567 €');
    });

    test('signs', () {
      expect(formatEuro(-12.3, decimals: 2), '−12,30 €');
      expect(formatEuro(5, sign: true), '+5 €');
      expect(formatEuro(0, sign: true), '+0 €');
    });
  });

  group('confirmAndDelete', () {
    Future<bool?> run(WidgetTester tester, {required String tap, Future<void> Function()? action}) async {
      bool? result;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async => result = await confirmAndDelete(
                context,
                title: 'Löschen?',
                message: 'Wirklich?',
                action: action ?? () async {},
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tap(find.text(tap));
      await tester.pumpAndSettle();
      return result;
    }

    testWidgets('runs the action only after confirming', (tester) async {
      var called = false;
      expect(await run(tester, tap: 'Löschen', action: () async => called = true), isTrue);
      expect(called, isTrue);
    });

    testWidgets('cancel does nothing', (tester) async {
      var called = false;
      expect(await run(tester, tap: 'Abbrechen', action: () async => called = true), isFalse);
      expect(called, isFalse);
    });

    testWidgets('shows errors instead of throwing', (tester) async {
      expect(await run(tester, tap: 'Löschen', action: () async => throw Exception('kaputt')), isFalse);
      expect(find.textContaining('Löschen fehlgeschlagen'), findsOneWidget);
    });
  });
}
