import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';

import 'package:frontend/features/receipts/models/receipt.dart';
import 'package:frontend/features/receipts/services/receipt_parser.dart';
import 'package:frontend/features/receipts/services/receipt_scanner.dart';

void main() {
  const parser = ReceiptParser();

  const aldi = [
    'ALDI SÜD',
    'Aldi SE & Co. KG',
    'Hauptstraße 12',
    '72070 Tübingen',
    'EUR',
    'HAFERFLOCKEN 500G 0,59 A',
    'BIO TOFU NATUR 200G',
    '2 x 1,79 3,58 A',
    'BANANEN 1,78 A',
    '1,230 kg x 1,45 EUR/kg',
    'SOJADRINK 1L 2 x 0,99 1,98 A',
    'PFAND 0,25 B',
    'Summe 8,18',
    'Kartenzahlung girocard 8,18',
    'MwSt A 7% 0,52',
    '05.10.26 18:23 Filiale 123',
  ];

  test('ALDI receipt: store, date, total, card payment and items with count, weight and pack size', () {
    final r = parser.parse(aldi);
    expect(r.store, 'ALDI SÜD');
    expect(r.date, DateTime(2026, 10, 5, 18, 23));
    expect(r.total, 8.18);
    expect(r.payment, ReceiptPayment.card);
    expect(r.items.map((i) => (i.name, i.price, i.count)), [
      ('HAFERFLOCKEN 500G', 0.59, 1),
      ('BIO TOFU NATUR 200G', 3.58, 2),
      ('BANANEN', 1.78, 1),
      ('SOJADRINK 1L', 1.98, 2),
      ('PFAND', 0.25, 1),
    ]);
    expect(r.sumMatches, isTrue);

    final items = r.items;
    expect(items[0].pantryAmount, (500.0, 'g'));
    expect(items[1].pantryAmount, (400.0, 'g')); // 2 × 200 g
    expect(items[2].weightKg, 1.23);
    expect(items[2].pantryAmount, (1230.0, 'g'));
    expect(items[3].pantryAmount, (2000.0, 'ml'));
    expect(items[4].isNonGoods, isTrue);
    expect(items[0].displayName, 'Haferflocken');
    expect(items[1].displayName, 'Bio Tofu Natur');
  });

  test('REWE receipt with price in the next line, discount and cash payment', () {
    final r = parser.parse(const [
      'REWE Markt GmbH',
      'Bahnhofstr. 3',
      'Rote Linsen',
      '1,49 A',
      'Paprika rot 3 Stk',
      '3 Stk x 0,79 2,37 A',
      'Rabatt Paprika -0,30 A',
      'SUMME EUR 3,56',
      'Gegeben BAR 5,00',
      'Rückgeld 1,44',
      'Datum 01.10.2026',
    ]);
    expect(r.store, 'REWE');
    expect(r.date, DateTime(2026, 10, 1));
    expect(r.total, 3.56);
    expect(r.payment, ReceiptPayment.cash);
    expect(r.items.map((i) => (i.name, i.price, i.count)), [
      ('Rote Linsen', 1.49, 1),
      ('Paprika rot 3 Stk', 2.37, 3),
      ('Rabatt Paprika', -0.30, 1),
    ]);
    expect(r.items.last.isNonGoods, isTrue);
    expect(r.items[1].pantryAmount, (3.0, null)); // Stück
    expect(r.sumMatches, isTrue);
  });

  test('unknown store, no total: amount falls back to the sum of items', () {
    final r = parser.parse(const [
      'Hofladen Müller-Schmid',
      'Eier 10er 3,20',
      'Kartoffeln 2,5kg 4,50',
    ]);
    expect(r.store, 'Hofladen Müller-Schmid');
    expect(r.total, isNull);
    expect(r.amount, 7.70);
    expect(r.items[1].pantryAmount, (2500.0, 'g'));
  });

  test('drugstore: items are found, nothing breaks without a date', () {
    final r = parser.parse(const ['dm-drogerie markt', 'Balea Duschgel 0,95', 'Zahnpasta 1,25', 'Summe 2,20']);
    expect(r.store, 'dm');
    expect(r.date, isNull);
    expect(r.items, hasLength(2));
    expect(r.total, 2.20);
  });

  test('OCR words in columns are joined into receipt rows (left to right, top to bottom)', () {
    Rect box(double x, double y) => Rect.fromLTWH(x, y, 40, 20);
    final rows = ReceiptScanner.rowsFromBoxes([
      ('0,59', box(300, 101)), // Preisspalte, leicht versetzt
      ('HAFERFLOCKEN', box(10, 100)),
      ('A', box(360, 99)),
      ('BANANEN', box(10, 130)),
      ('1,78', box(300, 131)),
      ('ALDI', box(10, 40)),
      ('SÜD', box(60, 42)),
    ]);
    expect(rows, ['ALDI SÜD', 'HAFERFLOCKEN 0,59 A', 'BANANEN 1,78']);
    expect(parser.parse(rows).items.map((i) => i.name), ['HAFERFLOCKEN', 'BANANEN']);
  });

  test('impossible or future dates are ignored (OCR errors)', () {
    final now = DateTime(2026, 10, 10);
    expect(parser.parse(const ['REWE', 'Brot 2,00', 'Summe 2,00', '31.02.2026'], now: now).date, isNull);
    expect(parser.parse(const ['REWE', 'Brot 2,00', 'Summe 2,00', '12.03.52 10:00'], now: now).date, isNull);
    expect(parser.parse(const ['REWE', 'Brot 2,00', 'Summe 2,00', '09.10.26'], now: now).date, DateTime(2026, 10, 9));
  });

  test('ML Kit splits prices and dates at the comma („0, 89“, „05.10,26“) – read like the printed receipt', () {
    // So kam der Bon auf dem Emulator aus der echten Texterkennung zurück.
    final r = parser.parse(const [
      'REWE Markt GmbH',
      'Hauptstrasse 5',
      '72070 Tuebingen',
      'BANANEN 1,78',
      'HAFERFLOCKEN 500G 0, 89',
      'MILCH 1L 1, 15',
      'SUMME EUR 3,82',
      '05.10,26 18:23',
    ], now: DateTime(2026, 10, 11));
    expect(r.items.map((i) => (i.name, i.price)), [('BANANEN', 1.78), ('HAFERFLOCKEN 500G', 0.89), ('MILCH 1L', 1.15)]);
    expect(r.total, 3.82);
    expect(r.date, DateTime(2026, 10, 5, 18, 23));
  });
}
