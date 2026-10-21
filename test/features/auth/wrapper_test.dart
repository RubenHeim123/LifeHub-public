import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:frontend/features/auth/screens/authenticate.dart';
import 'package:frontend/features/auth/screens/wrapper.dart';

import '../../helpers/test_app.dart';

void main() {
  testWidgets('Wrapper shows the login screen when nobody is signed in', (tester) async {
    FlutterSecureStorage.setMockInitialValues({});
    final db = createTestDatabase();

    await tester.pumpWidget(testApp(db, const Wrapper()));
    await pumpUntil(tester, find.byType(Authenticate));

    expect(find.byType(Authenticate), findsOneWidget);
    await disposeApp(tester, db);
  });

  testWidgets('signing out removes all reminders of the account', (tester) async {
    FlutterSecureStorage.setMockInitialValues({'email': 'test@example.com'});
    final db = createTestDatabase();
    final notifications = RecordingNotifications()..scheduled[1] = ('Zahnarzt', '', DateTime(2030));
    await tester.pumpWidget(testApp(
      db,
      Builder(builder: (context) => TextButton(onPressed: () => Wrapper.signOut(context), child: const Text('abmelden'))),
      notifications: notifications,
    ));
    await tester.tap(find.text('abmelden'));
    await pumpUntil(tester, find.byType(Authenticate));
    expect(notifications.scheduled, isEmpty);
    await disposeApp(tester, db);
  });
}
