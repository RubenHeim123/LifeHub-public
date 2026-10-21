import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:frontend/app/app.dart';
import 'package:frontend/core/ui/theme.dart';

import '../helpers/test_app.dart';

/// Startet die echte App (mit echtem Theme) gegen eine Test-Datenbank.
void main() {
  testWidgets('app starts on the login screen without a session', (tester) async {
    AppTheme.useGoogleFonts = false;
    FlutterSecureStorage.setMockInitialValues({});
    final db = createTestDatabase();

    await tester.pumpWidget(MyApp(database: db));
    await pumpUntil(tester, find.text('Willkommen zurück'));

    await disposeApp(tester, db);
  });
}
