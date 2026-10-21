import 'package:flutter_test/flutter_test.dart';

import 'package:frontend/features/auth/services/default_user_data.dart';
import 'package:frontend/features/finance/models/transaction.dart';
import 'package:frontend/features/finance/models/transaction_type.dart';
import 'package:frontend/features/fitness/catalog/standard_foods.dart';
import 'package:frontend/features/receipts/models/receipt.dart';
import 'package:frontend/features/receipts/services/receipt_analyzer.dart';
import 'package:frontend/features/receipts/services/receipt_parser.dart';

void main() {
  const analyzer = ReceiptAnalyzer();
  final categories = DefaultUserData.categories(1);
  final accounts = DefaultUserData.accounts(1);
  final foods = [for (final f in standardFoods) f.toFood(1)];

  Transaction booked(String description, String category, {String account = 'Girokonto', DateTime? date}) => Transaction(
        date: date ?? DateTime(2026, 9, 1),
        amount: 10,
        category: category,
        description: description,
        account: account,
        transactionType: TransactionType.expense,
        userid: 1,
      );

  test('supermarket receipt: Lebensmittel first, card → Girokonto, foods matched despite abbreviations', () {
    final receipt = const ReceiptParser().parse(const [
      'ALDI SÜD',
      'HAFERFL. ZART 500G 0,59 A',
      'BIO TOFU NATUR 200G 1,79 A',
      'ROTE LINSEN 500G 1,49 A',
      'SOJADRINK 1L 0,99 A',
      'BANANEN 1,78 A',
      'SPÜLMITTEL 0,85 B',
      'PFAND 0,25 B',
      'Summe 7,74',
      'girocard 7,74',
    ]);
    final s = analyzer.analyze(receipt: receipt, categories: categories, accounts: accounts, history: const [], foods: foods);
    expect(s.categories.first, 'Lebensmittel');
    expect(s.account, 'Girokonto');
    final names = [for (final (food, _) in s.items) food?.name];
    expect(names, ['Haferflocken', 'Tofu natur', 'Rote Linsen (trocken)', 'Sojadrink ungesüßt', 'Banane', null, null]);
    expect([for (final (_, pantry) in s.items) pantry], [true, true, true, true, true, false, false]);
  });

  test('learned from history: the category chosen before for this store wins', () {
    final s = analyzer.suggestCategories(
      store: 'dm',
      categories: categories,
      history: [booked('dm Einkauf', 'Gesundheit'), booked('dm', 'Gesundheit'), booked('REWE', 'Lebensmittel')],
    );
    expect(s.first, 'Gesundheit');
    expect(s, contains('Haushaltsmittel')); // Drogerie-Stichwort als Alternative
  });

  test('cash goes to the cash account; unknown payment uses the last account; fuel → Tanken', () {
    expect(analyzer.suggestAccount(ReceiptPayment.cash, accounts, const []), 'Barvermögen');
    expect(analyzer.suggestAccount(ReceiptPayment.unknown, accounts, [booked('x', 'Allgemein', account: 'Kreditkarte')]), 'Kreditkarte');
    expect(analyzer.suggestCategories(store: 'Aral', categories: categories, history: const []).first, 'Tanken');
    expect(analyzer.suggestCategories(store: 'Kiosk am Eck', categories: categories, history: const []), ['Allgemein']);
  });
}
