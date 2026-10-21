import 'dart:convert';
import 'dart:io';

import 'package:frontend/features/finance/repositories/account_repository.dart';
import 'package:frontend/features/finance/repositories/category_repository.dart';
import 'package:frontend/features/finance/repositories/transaction_repository.dart';
import 'package:frontend/features/finance/repositories/user_repository.dart';
import 'package:frontend/core/database/database.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

/// Service to export the local SQLite data into shareable JSON/CSV formats.
class ExportService {
  ExportService({
    required DatabaseService db,
    required UserRepository users,
    required AccountRepository accounts,
    required CategoryRepository categories,
    required TransactionRepository transactions,
  })  : _db = db,
        _userRepo = users,
        _accountRepo = accounts,
        _categoryRepo = categories,
        _transactionRepo = transactions;

  final DatabaseService _db;
  final UserRepository _userRepo;
  final AccountRepository _accountRepo;
  final CategoryRepository _categoryRepo;
  final TransactionRepository _transactionRepo;

  // ─── JSON Export ─────────────────────────────────────────────────────

  /// for the given user.
  Future<Map<String, dynamic>> _prepareExportData(int uid, {DateTime? since}) async {
    final user = await _userRepo.getUser(uid);
    final db = await _db.database;

    // Helper to fetch changed records
    Future<List<Map<String, dynamic>>> fetchChanged(String table, String userColumn, {bool isHabitRecord = false}) async {
      String where = '$userColumn = ?';
      List<dynamic> args = [uid];
      
      if (since != null) {
        where += ' AND last_changed > ?';
        args.add(syncStamp(since));
      } else {
        // For full export, we still filter is_deleted = 0 to keep it clean, 
        // UNLESS it's a changeset where we NEED is_deleted = 1 to inform the other side.
        where += ' AND is_deleted = 0';
      }

      if (isHabitRecord) {
         // habit_records doesn't have userid directly, it joins with habits
         return await db.rawQuery('''
           SELECT hr.* FROM habit_records hr
           JOIN habits h ON hr.habitId = h.id
           WHERE h.userid = ? ${since != null ? 'AND hr.last_changed > ?' : 'AND hr.is_deleted = 0'}
         ''', args);
      }

      return await db.query(table, where: where, whereArgs: args);
    }

    final data = {
      'sync_type': since == null ? 'full' : 'delta',
      'exportDate': DateTime.now().toIso8601String(),
      'since': since?.toIso8601String(),
      // Ohne Passwort-Hash: der Export wird geteilt bzw. unverschlüsselt per HTTP gesendet.
      'user': user.toMap()..remove('password'),
      'accounts': await fetchChanged('accounts', 'accountUserid'),
      'categories': await fetchChanged('categories', 'categoryUserid'),
      'transactions': await fetchChanged('transactions', 'userid'),
      'fixed_transactions': await fetchChanged('fixed_transactions', 'userid'),
      'todos': await fetchChanged('todos', 'userid'),
      'appointments': await fetchChanged('appointments', 'userid'),
      'habits': await fetchChanged('habits', 'userid'),
      'habit_records': await fetchChanged('', '', isHabitRecord: true),
      'financial_goals': await fetchChanged('financial_goals', 'userid'),
      'vision_areas': await fetchChanged('vision_areas', 'userid'),
      'vision_goals': await fetchChanged('vision_goals', 'userid'),
      'goal_steps': await fetchChanged('goal_steps', 'userid'),
      for (final table in DatabaseService.lifestyleTables) table: await fetchChanged(table, 'userid'),
    };

    return data;
  }

  /// Generates a structured JSON string containing the full database snapshot.
  Future<String> generateJson(int uid) async {
    final data = await _prepareExportData(uid);
    return const JsonEncoder.withIndent('  ').convert(data);
  }

  /// Generates a delta changeset since the given timestamp.
  Future<String> generateChangeset(int uid, DateTime since) async {
    final data = await _prepareExportData(uid, since: since);
    return const JsonEncoder.withIndent('  ').convert(data);
  }

  // ─── CSV Export ──────────────────────────────────────────────────────

  /// Generates a CSV string for transactions.
  Future<String> generateTransactionsCsv(int uid) async {
    final transactions = await _transactionRepo.getAllTransactions(uid);
    final sb = StringBuffer();
    sb.writeln('Datum;Betrag;Kategorie;Beschreibung;Konto;Typ');
    for (var t in transactions) {
      sb.writeln(
          '${t.date.toIso8601String().split('T').first};${t.amount};${_escapeCsv(t.category)};${_escapeCsv(t.description)};${_escapeCsv(t.account)};${t.transactionType.label}');
    }
    return sb.toString();
  }

  /// Generates a CSV string for accounts.
  Future<String> generateAccountsCsv(int uid) async {
    final accounts = await _accountRepo.getAllAccounts(uid);
    final sb = StringBuffer();
    sb.writeln('Kontoname;Kontostand');
    for (var a in accounts) {
      sb.writeln('${_escapeCsv(a.accountName)};${a.accountAmount}');
    }
    return sb.toString();
  }

  /// Generates a CSV string for categories.
  Future<String> generateCategoriesCsv(int uid) async {
    final categories = await _categoryRepo.getAllCategories(uid);
    final sb = StringBuffer();
    sb.writeln('Kategoriename;Typ');
    for (var c in categories) {
      sb.writeln('${_escapeCsv(c.categoryName)};${c.transactionType.label}');
    }
    return sb.toString();
  }

  // ─── Share helpers ───────────────────────────────────────────────────

  /// Exports the full database as JSON and opens the native Share dialog.
  Future<void> shareJson(int uid) async {
    try {
      final json = await generateJson(uid);
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/LifeHub_Export.json');
      await file.writeAsString(json);
      await Share.shareXFiles(
        [XFile(file.path)],
        subject: 'LifeHub Daten-Export (JSON)',
      );
    } catch (e) {
      throw Exception('Fehler beim Exportieren der JSON-Datei: $e');
    }
  }

  /// Exports transactions as CSV and opens the native Share dialog.
  Future<void> shareCsv(int uid) async {
    try {
      final csv = await generateTransactionsCsv(uid);
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/LifeHub_Transaktionen.csv');
      await file.writeAsString(csv);
      await Share.shareXFiles(
        [XFile(file.path)],
        subject: 'LifeHub Transaktionen (CSV)',
      );
    } catch (e) {
      throw Exception('Fehler beim Exportieren der CSV-Datei: $e');
    }
  }

  // ─── Helpers ─────────────────────────────────────────────────────────

  String _escapeCsv(String value) {
    if (value.contains(';') || value.contains('"') || value.contains('\n')) {
      return '"${value.replaceAll('"', '""')}"';
    }
    return value;
  }
}
