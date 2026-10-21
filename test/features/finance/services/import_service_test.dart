import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/core/models/app_exceptions.dart';
import 'package:frontend/features/finance/services/import_service.dart';
import 'package:frontend/features/finance/models/transaction_type.dart';

void main() {
  group('ImportService Tests', () {
    late ImportService service;

    setUp(() {
      service = ImportService();
    });

    test('Category Suggestion works correctly', () {
      expect(ImportService.suggestCategory('REWE Supermarkt'), 'Lebensmittel');
      expect(ImportService.suggestCategory('Aral Tankstelle'), 'Tanken');
      expect(ImportService.suggestCategory('Unbekannter Shop'), 'Allgemein');
    });

    test('Parses ING CSV correctly', () async {
      final file = File('ing_test_temp.csv');
      await file.writeAsString('''
Buchung;Valuta;Auftraggeber/Empfänger;Buchungstext;Verwendungszweck;Saldo;Währung;Betrag;Währung
15.10.2023;15.10.2023;REWE Supermarkt;Lastschrift;Lebensmittel;1000,00;EUR;-25,50;EUR
16.10.2023;16.10.2023;Arbeitgeber GmbH;Gutschrift;Gehalt Oktober;1500,00;EUR;500,00;EUR
      ''');

      final results = await service.parseFile(file, profile: BankProfile.ing);
      expect(results.length, 2);

      // Check first tx (expense)
      expect(results[0].date, DateTime(2023, 10, 15));
      expect(results[0].amount, 25.50);
      expect(results[0].recipient, 'REWE Supermarkt');
      expect(results[0].description, 'Lebensmittel');
      expect(results[0].transactionType, TransactionType.expense);
      expect(results[0].suggestedCategory, 'Lebensmittel'); // rewe -> Lebensmittel

      // Check second tx (income)
      expect(results[1].amount, 500.0);
      expect(results[1].transactionType, TransactionType.income);
      expect(results[1].suggestedCategory, 'Gehalt'); // gehalt is in keywords

      if (await file.exists()) {
        await file.delete();
      }
    });

    test('Handles malformed CSV gracefully', () async {
      final file = File('malformed_temp.csv');
      await file.writeAsString('''
Buchung;Valuta;Auftraggeber/Empfänger;Buchungstext;Verwendungszweck;Saldo;Währung;Betrag;Währung
15.10.2023;15.10.2023;InvalidRow
      ''');

      final results = await service.parseFile(file, profile: BankProfile.ing);
      expect(results.isEmpty, true);

      if (await file.exists()) {
        await file.delete();
      }
    });

    test('Parses C24 CSV correctly', () async {
      final file = File('c24_test_temp.csv');
      // Transaktionstyp,Buchungsdatum,Karteneinsatz,Betrag,Zahlungsempfänger,IBAN,BIC,Verwendungszweck,Beschreibung,Kontonummer,Kontoname,Kategorie,Unterkategorie,Bargeldabhebung
      await file.writeAsString('''
Transaktionstyp,Buchungsdatum,Karteneinsatz,Betrag,Zahlungsempfänger,IBAN,BIC,Verwendungszweck,Beschreibung,Kontonummer,Kontoname,Kategorie,Unterkategorie,Bargeldabhebung
Lastschrift,15.10.2023,,-25.50,REWE Supermarkt,,,,Lebensmittelkäufe,1234567890,,Supermarkt,,Nein
Gutschrift,16.10.2023,,500,00,Arbeitgeber GmbH,,,,Gehalt Oktober,1234567890,,Gehalt,,Nein
      ''');

      final results = await service.parseFile(file, profile: BankProfile.c24);
      expect(results.length, 2);

      // Check first tx (expense) -> 25.50
      expect(results[0].date, DateTime(2023, 10, 15));
      expect(results[0].amount, 25.50);
      expect(results[0].recipient, 'REWE Supermarkt');
      expect(results[0].description, 'Lebensmittelkäufe');
      expect(results[0].transactionType, TransactionType.expense);

      // Check second tx (income) -> 500.00
      expect(results[1].amount, 500.0);
      expect(results[1].transactionType, TransactionType.income);

      if (await file.exists()) {
        await file.delete();
      }
    });
  
    test('Latin-1 files, two-digit years and unreadable amounts', () {
      final bytes = latin1.encode('Datum;Betrag;Empfänger;Beschreibung\n'
          '05.10.26;-12,50;Bäckerei Müller;Brötchen\n'
          '06.10.2026;abc;Kaputt;Zeile\n'
          '31.02.2026;-1,00;Unmöglich;Datum\n'
          '2026-10-07;1.234,56;Arbeitgeber;Gehalt\n');
      final text = ImportService.decode(bytes);
      expect(text, contains('Empfänger'));
      final rows = service.parseLines(text.split('\n'));
      expect(rows.map((r) => (r.date, r.amount, r.recipient)), [
        (DateTime(2026, 10, 5), 12.5, 'Bäckerei Müller'),
        (DateTime(2026, 10, 7), 1234.56, 'Arbeitgeber'),
      ]);
      expect(service.skippedRows, 2); // nicht still mit 0 € gebucht
      expect(ImportService.decode(utf8.encode('\uFEFFDatum;Betrag')), 'Datum;Betrag');
    });

    test('a missing file gives a readable message instead of a raw exception', () async {
      await expectLater(service.parseFile(File('gibt_es_nicht.csv')),
          throwsA(isA<UserFacingException>().having((e) => e.message, 'message', startsWith('Die Datei konnte nicht gelesen werden'))));
    });
  });
}
