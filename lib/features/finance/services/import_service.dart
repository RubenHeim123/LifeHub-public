import 'dart:convert';
import 'dart:io';

import 'package:frontend/core/models/app_exceptions.dart';

import 'package:frontend/features/finance/models/transaction.dart' as tr;
import 'package:frontend/features/finance/models/transaction_type.dart';

/// Parsed row from a bank CSV file, ready for user review before import.
class ImportedTransaction {
  final DateTime date;
  final double amount;
  final String recipient;
  final String description;
  String suggestedCategory;
  TransactionType transactionType;

  ImportedTransaction({
    required this.date,
    required this.amount,
    required this.recipient,
    required this.description,
    required this.suggestedCategory,
    required this.transactionType,
  });

  /// Convert to a real Transaction model for database insertion.
  tr.Transaction toTransaction({
    required int userid,
    required String account,
  }) {
    return tr.Transaction(
      date: date,
      amount: amount.abs(),
      category: suggestedCategory,
      description: '$recipient – $description',
      account: account,
      transactionType: transactionType,
      userid: userid,
    );
  }
}

/// Supported bank CSV formats.
enum BankProfile { ing, dkb, generic, c24 }

/// Service to parse bank CSV files and suggest categories.
class ImportService {
  /// Known category keywords.
  static const Map<String, String> _categoryKeywords = {
    'rewe': 'Lebensmittel',
    'edeka': 'Lebensmittel',
    'aldi': 'Lebensmittel',
    'lidl': 'Lebensmittel',
    'netto': 'Lebensmittel',
    'penny': 'Lebensmittel',
    'kaufland': 'Lebensmittel',
    'dm-drogerie': 'Haushaltsmittel',
    'rossmann': 'Haushaltsmittel',
    'amazon': 'Allgemein',
    'paypal': 'Allgemein',
    'shell': 'Tanken',
    'aral': 'Tanken',
    'jet tankstelle': 'Tanken',
    'total': 'Tanken',
    'db bahn': 'Reisen',
    'flixbus': 'Reisen',
    'netflix': 'Freizeit',
    'spotify': 'Musik',
    'apple': 'Technische Ausrüstung',
    'miete': 'Miete',
    'strom': 'Strom/Wasser',
    'stadtwerke': 'Strom/Wasser',
    'versicherung': 'Versicherungen',
    'allianz': 'Versicherungen',
    'huk': 'Versicherungen',
    'arzt': 'Gesundheit',
    'apotheke': 'Gesundheit',
    'schule': 'Schule',
    'uni': 'Schule',
    'fitnessstudio': 'Sport',
    'mcfit': 'Sport',
    'gehalt': 'Gehalt',
    'lohn': 'Gehalt',
  };

  /// Suggests a category based on recipient and description text.
  static String suggestCategory(String text) {
    final lower = text.toLowerCase();
    for (var entry in _categoryKeywords.entries) {
      if (lower.contains(entry.key)) {
        return entry.value;
      }
    }
    return 'Allgemein';
  }

  /// Zeilen, die beim letzten Einlesen wegen unlesbarem Datum oder Betrag übersprungen wurden.
  int skippedRows = 0;

  /// Parses a CSV file using the specified bank profile.
  Future<List<ImportedTransaction>> parseFile(
    File file, {
    BankProfile profile = BankProfile.generic,
  }) async {
    final List<int> bytes;
    try {
      bytes = await file.readAsBytes();
    } catch (e) {
      throw UserFacingException('Die Datei konnte nicht gelesen werden ($e).');
    }
    return parseLines(const LineSplitter().convert(decode(bytes)), profile: profile);
  }

  /// Bank-Exporte sind oft noch Latin-1 / Windows-1252 statt UTF-8 („Empfänger“ wäre sonst kaputt).
  static String decode(List<int> bytes) {
    try {
      final text = utf8.decode(bytes);
      return text.startsWith('\uFEFF') ? text.substring(1) : text;
    } on FormatException {
      return latin1.decode(bytes);
    }
  }

  /// Liest die Zeilen im Format der gewählten Bank. Unlesbare Zeilen werden übersprungen und in [skippedRows] gezählt.
  List<ImportedTransaction> parseLines(List<String> lines, {BankProfile profile = BankProfile.generic}) {
    skippedRows = 0;
    if (lines.isEmpty) return [];
    switch (profile) {
      case BankProfile.ing:
        return _parseIngCsv(lines);
      case BankProfile.dkb:
        return _parseDkbCsv(lines);
      case BankProfile.generic:
        return _parseGenericCsv(lines);
      case BankProfile.c24:
        return _parseC24Csv(lines);
    }
  }

  /// dd.MM.yyyy, dd.MM.yy (→ 20yy) oder ISO (yyyy-MM-dd). Wirft bei unmöglichen Daten.
  static DateTime parseDate(String raw) {
    final text = raw.replaceAll('"', '').trim();
    final m = RegExp(r'^(\d{1,2})\.(\d{1,2})\.(\d{2}|\d{4})$').firstMatch(text);
    if (m == null) return DateTime.parse(text);
    final d = int.parse(m.group(1)!), mo = int.parse(m.group(2)!);
    var y = int.parse(m.group(3)!);
    if (y < 100) y += 2000;
    if (mo < 1 || mo > 12 || d < 1 || d > DateTime(y, mo + 1, 0).day) throw FormatException('Ungültiges Datum', raw);
    return DateTime(y, mo, d);
  }

  /// Deutscher Betrag („-1.234,56“) – wirft, wenn nichts Lesbares drinsteht (statt still 0 € zu buchen).
  static double parseGermanAmount(String raw) {
    final text = raw.replaceAll('"', '').replaceAll('€', '').replaceAll(' ', '').trim();
    final value = double.tryParse(text.replaceAll('.', '').replaceAll(',', '.'));
    if (value == null) throw FormatException('Ungültiger Betrag', raw);
    return value;
  }

  // ─── ING-DiBa Format ───────────────────────────────────────────────
  // Columns: Buchung;Valuta;Auftraggeber/Empfänger;Buchungstext;Verwendungszweck;Saldo;Währung;Betrag;Währung
  List<ImportedTransaction> _parseIngCsv(List<String> lines) {
    final List<ImportedTransaction> results = [];

    // Skip header lines until we find the actual column headers
    int dataStart = 0;
    for (int i = 0; i < lines.length; i++) {
      if (lines[i].startsWith('Buchung;')) {
        dataStart = i + 1;
        break;
      }
    }

    for (int i = dataStart; i < lines.length; i++) {
      final line = lines[i].trim();
      if (line.isEmpty) continue;

      final parts = line.split(';');
      if (parts.length < 8) continue;

      try {
        final date = parseDate(parts[0]); // dd.MM.yyyy

        final recipient = parts[2].trim();
        final description = parts[4].trim();
        final amount = parseGermanAmount(parts[7]);

        final fullText = '$recipient $description';
        final suggested = suggestCategory(fullText);
        final type = amount >= 0 ? TransactionType.income : TransactionType.expense;

        results.add(ImportedTransaction(
          date: date,
          amount: amount.abs(),
          recipient: recipient,
          description: description,
          suggestedCategory: suggested,
          transactionType: type,
        ));
      } catch (_) {
        skippedRows++; // unlesbares Datum oder unlesbarer Betrag
      }
    }
    return results;
  }

  // ─── DKB Format ─────────────────────────────────────────────────────
  List<ImportedTransaction> _parseDkbCsv(List<String> lines) {
    final List<ImportedTransaction> results = [];

    int dataStart = 0;
    for (int i = 0; i < lines.length; i++) {
      if (lines[i].startsWith('"Buchungsdatum"') || lines[i].startsWith('Buchungsdatum')) {
        dataStart = i + 1;
        break;
      }
    }

    for (int i = dataStart; i < lines.length; i++) {
      final line = lines[i].trim();
      if (line.isEmpty) continue;

      // Handle quoted CSV
      final parts = _splitCsvLine(line);
      if (parts.length < 5) continue;

      try {
        final date = parseDate(parts[0]);

        final recipient = parts[3].replaceAll('"', '').trim();
        final description = parts[4].replaceAll('"', '').trim();
        final amount = parseGermanAmount(parts[7]);

        final fullText = '$recipient $description';
        final suggested = suggestCategory(fullText);
        final type = amount >= 0 ? TransactionType.income : TransactionType.expense;

        results.add(ImportedTransaction(
          date: date,
          amount: amount.abs(),
          recipient: recipient,
          description: description,
          suggestedCategory: suggested,
          transactionType: type,
        ));
      } catch (_) {
        skippedRows++;
      }
    }
    return results;
  }

  // ─── Generic CSV ────────────────────────────────────────────────────
  // Expected: Datum;Betrag;Empfänger;Beschreibung
  List<ImportedTransaction> _parseGenericCsv(List<String> lines) {
    final List<ImportedTransaction> results = [];
    final startIdx = lines.isNotEmpty && lines[0].toLowerCase().contains('datum') ? 1 : 0;

    for (int i = startIdx; i < lines.length; i++) {
      final line = lines[i].trim();
      if (line.isEmpty) continue;

      final parts = line.split(';');
      if (parts.length < 4) continue;

      try {
        final date = parseDate(parts[0]);
        final amount = parseGermanAmount(parts[1]);
        final recipient = parts[2].trim();
        final description = parts.length > 3 ? parts[3].trim() : '';

        final fullText = '$recipient $description';
        final suggested = suggestCategory(fullText);
        final type = amount >= 0 ? TransactionType.income : TransactionType.expense;

        results.add(ImportedTransaction(
          date: date,
          amount: amount.abs(),
          recipient: recipient,
          description: description,
          suggestedCategory: suggested,
          transactionType: type,
        ));
      } catch (_) {
        skippedRows++;
      }
    }
    return results;
  }

  // ─── C24 Bank Format ────────────────────────────────────────────────
  // Transaktionstyp,Buchungsdatum,Karteneinsatz,Betrag,Zahlungsempfänger,IBAN,BIC,Verwendungszweck,Beschreibung,Kontonummer,Kontoname,Kategorie,Unterkategorie,Bargeldabhebung
  List<ImportedTransaction> _parseC24Csv(List<String> lines) {
    final List<ImportedTransaction> results = [];
    int dataStart = 0;
    for (int i = 0; i < lines.length; i++) {
      if (lines[i].contains('Transaktionstyp') || lines[i].contains('Buchungsdatum')) {
        dataStart = i + 1;
        break;
      }
    }

    for (int i = dataStart; i < lines.length; i++) {
      final line = lines[i].trim();
      if (line.isEmpty) continue;

      // C24 uses comma as delimiter
      final parts = _splitCsvLine(line, delimiter: ',');
      if (parts.length < 9) continue;

      try {
        final date = parseDate(parts[1]);

        final recipient = parts[4].replaceAll('"', '').trim();

        final vZweck = parts[7].replaceAll('"', '').trim();
        final beschreibung = parts[8].replaceAll('"', '').trim();
        final fullDescription = [vZweck, beschreibung].where((s) => s.isNotEmpty).join(' ');

        final amountStr = parts[3].replaceAll('"', '').trim();
        final cleanAmt = amountStr.replaceAll(RegExp(r'[^\d.,-]'), '');
        final double? parsed;
        if (cleanAmt.lastIndexOf(',') > cleanAmt.lastIndexOf('.')) {
          parsed = double.tryParse(cleanAmt.replaceAll('.', '').replaceAll(',', '.'));
        } else if (cleanAmt.lastIndexOf('.') > cleanAmt.lastIndexOf(',')) {
          parsed = double.tryParse(cleanAmt.replaceAll(',', ''));
        } else {
          parsed = double.tryParse(cleanAmt.replaceAll(',', '.'));
        }
        if (parsed == null) throw FormatException('Ungültiger Betrag', amountStr);
        final amount = parsed;

        final fullText = '$recipient $fullDescription';
        final suggested = suggestCategory(fullText);
        final type = amount >= 0 ? TransactionType.income : TransactionType.expense;

        results.add(ImportedTransaction(
          date: date,
          amount: amount.abs(),
          recipient: recipient.isEmpty ? 'Unbekannt' : recipient,
          description: fullDescription,
          suggestedCategory: suggested,
          transactionType: type,
        ));
      } catch (_) {
        skippedRows++;
      }
    }
    return results;
  }

  // ─── CSV Utility ────────────────────────────────────────────────────

  List<String> _splitCsvLine(String line, {String delimiter = ';'}) {
    final List<String> result = [];
    bool inQuotes = false;
    StringBuffer current = StringBuffer();

    for (int i = 0; i < line.length; i++) {
      final ch = line[i];
      if (ch == '"') {
        inQuotes = !inQuotes;
      } else if (ch == delimiter && !inQuotes) {
        result.add(current.toString());
        current = StringBuffer();
      } else {
        current.write(ch);
      }
    }
    result.add(current.toString());
    return result;
  }

  // ─── Open Banking (vorbereitet, auskommentiert) ──────────────────────
  //
  // /// Fetches transactions from a bank account via the GoCardless/Nordigen API.
  // /// Requires a valid access token and account ID.
  // Future<List<ImportedTransaction>> fetchOpenBankingTransactions({
  //   required String accessToken,
  //   required String accountId,
  // }) async {
  //   final url = Uri.parse(
  //       'https://bankaccountdata.gocardless.com/api/v2/accounts/$accountId/transactions/');
  //   final response = await http.get(url, headers: {
  //     'Authorization': 'Bearer $accessToken',
  //     'Accept': 'application/json',
  //   });
  //
  //   if (response.statusCode != 200) {
  //     throw Exception('Open Banking API error: ${response.statusCode}');
  //   }
  //
  //   final data = json.decode(response.body);
  //   final booked = data['transactions']['booked'] as List<dynamic>;
  //
  //   return booked.map((tx) {
  //     final amount = double.tryParse(tx['transactionAmount']['amount'] ?? '0') ?? 0;
  //     return ImportedTransaction(
  //       date: DateTime.parse(tx['bookingDate']),
  //       amount: amount.abs(),
  //       recipient: tx['creditorName'] ?? tx['debtorName'] ?? 'Unbekannt',
  //       description: tx['remittanceInformationUnstructured'] ?? '',
  //       suggestedCategory: suggestCategory(
  //           '${tx['creditorName'] ?? ''} ${tx['remittanceInformationUnstructured'] ?? ''}'),
  //       transactionType: amount >= 0 ? TransactionType.income : TransactionType.expense,
  //     );
  //   }).toList();
  // }
}
