import 'package:flutter_test/flutter_test.dart';

import 'package:frontend/features/finance/screens/import_transactions_view.dart';

import '../../../helpers/test_app.dart';

void main() {
  testWidgets('ImportTransactionsView shows the upload button', (tester) async {
    final db = createTestDatabase();
    final user = await seedDb(tester, db, () => createTestUser(db));

    await tester.pumpWidget(testApp(db, ImportTransactionsView(user: user)));
    await pumpUntil(tester, find.text('CSV hochladen'));

    expect(find.text('CSV hochladen'), findsOneWidget);
    await disposeApp(tester, db);
  });
}
