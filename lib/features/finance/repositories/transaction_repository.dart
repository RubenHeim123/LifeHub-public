import 'package:sqflite/sqflite.dart';

import 'package:frontend/core/database/database.dart';
import 'package:frontend/core/services/notification_service.dart';
import 'package:frontend/features/finance/models/category.dart';
import 'package:frontend/features/finance/models/fixedtransaction.dart';
import 'package:frontend/features/finance/models/transaction.dart' as tr;
import 'package:frontend/features/finance/models/transaction_type.dart';

/// Transaktionen und wiederkehrende Transaktionen.
///
/// Jede Buchung ändert den Kontostand im selben SQL-Transaktionsblock, damit
/// Buchung und Saldo nie auseinanderlaufen. Konten werden über Name **und**
/// Nutzer gesucht, weil alle Nutzer dieselben Standard-Kontonamen haben.
class TransactionRepository {
  TransactionRepository({DatabaseService? db, NotificationService? notifications})
      : _db = db ?? DatabaseService.instance,
        _notifications = notifications ?? NotificationService();

  final DatabaseService _db;
  final NotificationService _notifications;

  static String _now() => syncStamp();

  Future<void> _adjustBalance(DatabaseExecutor ex, int uid, String accountName, double delta) async {
    await ex.rawUpdate(
      'UPDATE accounts SET accountAmount = accountAmount + ?, last_changed = ? '
      'WHERE accountUserid = ? AND accountName = ? AND is_deleted = 0',
      [delta, _now(), uid, accountName],
    );
  }

  Future<int> _insert(DatabaseExecutor ex, tr.Transaction t) async {
    final id = await ex.insert('transactions', t.toMap());
    await _adjustBalance(ex, t.userid, t.account, t.signedAmount);
    return id;
  }

  // ─── Regular Transactions ───────────────────────────────────────────

  /// Speichert eine Buchung. [together] läuft in derselben SQL-Transaktion – schlägt dort etwas fehl,
  /// wird auch die Buchung nicht gespeichert (z. B. Bon: Buchung + Vorratsartikel). [together] bekommt
  /// die ID der neuen Buchung. Liefert diese ID.
  Future<int> createTransaction(tr.Transaction transaction,
      {Future<void> Function(DatabaseExecutor txn, int id)? together}) async {
    final db = await _db.database;
    final id = await db.transaction((txn) async {
      final id = await _insert(txn, transaction);
      if (together != null) await together(txn, id);
      return id;
    });
    await _checkBudgetAlarms([transaction]);
    return id;
  }

  /// Mehrere Buchungen auf einmal (CSV-Import) – alle oder keine.
  Future<void> createTransactions(List<tr.Transaction> transactions) async {
    if (transactions.isEmpty) return;
    final db = await _db.database;
    await db.transaction((txn) async {
      for (final t in transactions) {
        await _insert(txn, t);
      }
    });
    await _checkBudgetAlarms(transactions);
  }

  /// Umbuchung zwischen zwei eigenen Konten: eine Ausgabe auf [fromAccount] und eine
  /// Einnahme auf [toAccount], atomar gespeichert.
  Future<void> createTransfer({
    required int userid,
    required String fromAccount,
    required String toAccount,
    required double amount,
    required DateTime date,
    String description = '',
    String? imagePath,
  }) async {
    final db = await _db.database;
    await db.transaction((txn) async {
      await _insert(
        txn,
        tr.Transaction(
          date: date,
          amount: amount,
          category: kTransferCategory,
          description: description.isEmpty ? 'Umbuchung an $toAccount' : description,
          account: fromAccount,
          transactionType: TransactionType.expense,
          userid: userid,
          imagePath: imagePath,
        ),
      );
      await _insert(
        txn,
        tr.Transaction(
          date: date,
          amount: amount,
          category: kTransferCategory,
          description: description.isEmpty ? 'Umbuchung von $fromAccount' : description,
          account: toAccount,
          transactionType: TransactionType.income,
          userid: userid,
          imagePath: imagePath,
        ),
      );
    });
  }

  Future<tr.Transaction> getTransaction(int id) async {
    final db = await _db.database;
    final maps = await db.query('transactions', where: 'id = ?', whereArgs: [id]);
    if (maps.isEmpty) throw Exception('Transaction not found');
    return tr.Transaction.fromMap(maps.first);
  }

  /// Hängt das Bild noch an einer Buchung? Gelöschte zählen mit (Rückgängig), ebenso die zweite Umbuchungs-Hälfte.
  Future<bool> isImageUsed(String path) async {
    final db = await _db.database;
    final rows = await db.query('transactions', columns: ['id'], where: 'imagePath = ?', whereArgs: [path], limit: 1);
    return rows.isNotEmpty;
  }

  Future<List<tr.Transaction>> getAllTransactions(int uid) async {
    final db = await _db.database;
    final maps = await db.query(
      'transactions',
      where: 'userid = ? AND is_deleted = 0',
      whereArgs: [uid],
      orderBy: 'date DESC',
    );
    return maps.map(tr.Transaction.fromMap).toList();
  }

  /// Transaktionen ab [since], optional nur für ein Konto und/oder einen Kalendermonat (1–12).
  Future<List<tr.Transaction>> getTransactionsSince(int uid, DateTime since, {String? account, int? month}) async {
    final db = await _db.database;
    var where = 'userid = ? AND is_deleted = 0 AND date >= ?';
    final args = <Object>[uid, since.toIso8601String()];
    if (month != null) {
      where += " AND strftime('%m', date) = ?";
      args.add(month.toString().padLeft(2, '0'));
    }
    if (account != null) {
      where += ' AND account = ?';
      args.add(account);
    }
    final maps = await db.query('transactions', where: where, whereArgs: args, orderBy: 'date DESC');
    return maps.map(tr.Transaction.fromMap).toList();
  }

  /// Ändert eine Buchung samt Kontostand. [together] läuft in derselben SQL-Transaktion.
  Future<void> updateTransaction(tr.Transaction transaction, {Future<void> Function(DatabaseExecutor txn)? together}) async {
    final db = await _db.database;
    await db.transaction((txn) async {
      final original = await txn.query('transactions',
          where: 'id = ? AND is_deleted = 0', whereArgs: [transaction.id]);
      if (original.isNotEmpty) {
        final old = tr.Transaction.fromMap(original.first);
        await _adjustBalance(txn, old.userid, old.account, -old.signedAmount);
      }
      await _adjustBalance(txn, transaction.userid, transaction.account, transaction.signedAmount);
      await txn.update('transactions', {...transaction.toMap(), 'last_changed': _now()},
          where: 'id = ?', whereArgs: [transaction.id]);
      if (together != null) await together(txn);
    });
    await _checkBudgetAlarms([transaction]);
  }

  Future<void> deleteTransaction(int id) async {
    final db = await _db.database;
    await db.transaction((txn) async {
      // Nur nicht gelöschte Zeilen: doppeltes Löschen darf den Saldo nicht zweimal korrigieren.
      final rows = await txn.query('transactions', where: 'id = ? AND is_deleted = 0', whereArgs: [id]);
      if (rows.isEmpty) return;
      final t = tr.Transaction.fromMap(rows.first);
      await _adjustBalance(txn, t.userid, t.account, -t.signedAmount);
      await txn.update('transactions', {'is_deleted': 1, 'last_changed': _now()},
          where: 'id = ?', whereArgs: [id]);
    });
  }

  /// Macht eine gelöschte Buchung wieder gültig und bucht den Betrag erneut aufs Konto.
  Future<void> restoreTransaction(int id) async {
    final db = await _db.database;
    await db.transaction((txn) async {
      final rows = await txn.query('transactions', where: 'id = ? AND is_deleted = 1', whereArgs: [id]);
      if (rows.isEmpty) return;
      final t = tr.Transaction.fromMap(rows.first);
      await _adjustBalance(txn, t.userid, t.account, t.signedAmount);
      await txn.update('transactions', {'is_deleted': 0, 'last_changed': _now()}, where: 'id = ?', whereArgs: [id]);
    });
  }

  Future<void> restoreFixedTransaction(int id) => _db.restoreRow('fixed_transactions', id);

  Future<void> deleteAllTransactions(int uid) async {
    final db = await _db.database;
    await db.transaction((txn) async {
      final rows = await txn.query('transactions', where: 'userid = ? AND is_deleted = 0', whereArgs: [uid]);
      final deltas = <String, double>{};
      for (final row in rows) {
        final t = tr.Transaction.fromMap(row);
        deltas[t.account] = (deltas[t.account] ?? 0) - t.signedAmount;
      }
      for (final e in deltas.entries) {
        await _adjustBalance(txn, uid, e.key, e.value);
      }
      await txn.update('transactions', {'is_deleted': 1, 'last_changed': _now()},
          where: 'userid = ? AND is_deleted = 0', whereArgs: [uid]);
    });
  }

  // ─── Budget alarm ───────────────────────────────────────────────────

  Future<void> _checkBudgetAlarms(List<tr.Transaction> transactions) async {
    for (final t in transactions) {
      if (!t.transactionType.isExpense || t.isTransfer) continue;
      await _checkBudgetAlarm(t);
    }
  }

  Future<void> _checkBudgetAlarm(tr.Transaction transaction) async {
    final db = await _db.database;
    final catMaps = await db.query(
      'categories',
      where: 'categoryName = ? AND categoryUserid = ? AND transactionType = ? AND is_deleted = 0',
      whereArgs: [transaction.category, transaction.userid, TransactionType.expense.dbValue],
    );
    if (catMaps.isEmpty) return;
    final category = Category.fromMap(catMaps.first);
    if (category.monthlyBudget <= 0) return;

    final monthStart = DateTime(transaction.date.year, transaction.date.month, 1);
    final nextMonthStart = DateTime(transaction.date.year, transaction.date.month + 1, 1);
    final result = await db.rawQuery(
      'SELECT COALESCE(SUM(amount), 0) AS total FROM transactions '
      'WHERE userid = ? AND category = ? AND transactionType = ? AND is_deleted = 0 AND date >= ? AND date < ?',
      [
        transaction.userid,
        transaction.category,
        TransactionType.expense.dbValue,
        monthStart.toIso8601String(),
        nextMonthStart.toIso8601String(),
      ],
    );
    final total = (result.first['total'] as num).toDouble();

    if (total > category.monthlyBudget) {
      await _notifications.scheduleNotification(
        id: NotificationService.budgetIdOffset + (category.id ?? 0),
        title: 'Budget überschritten!',
        body: 'Du hast das Budget für ${category.categoryName} (${category.monthlyBudget}€) überschritten.',
        scheduledDate: DateTime.now().add(const Duration(seconds: 1)),
      );
    }
  }

  // ─── Fixed (Recurring) Transactions ─────────────────────────────────

  /// Legt wiederkehrende Transaktionen an und bucht sofort alle bereits fälligen Termine
  /// (Startdatum in der Vergangenheit). `nextTime` sollte dafür dem Startdatum entsprechen.
  Future<void> createFixedTransactions(List<FixedTransaction> transactions) async {
    if (transactions.isEmpty) return;
    final db = await _db.database;
    await db.transaction((txn) async {
      for (final ft in transactions) {
        await txn.insert('fixed_transactions', ft.toMap());
      }
    });
    await bookDueFixedTransactions(transactions.first.userid);
  }

  Future<void> createFixedTransaction(FixedTransaction transaction) =>
      createFixedTransactions([transaction]);

  Future<FixedTransaction> getFixedTransaction(int id) async {
    final db = await _db.database;
    final maps = await db.query('fixed_transactions', where: 'id = ?', whereArgs: [id]);
    if (maps.isEmpty) throw Exception('Fixed transaction not found');
    return FixedTransaction.fromMap(maps.first);
  }

  Future<List<FixedTransaction>> getAllFixedTransactions(int uid) async {
    final db = await _db.database;
    final maps = await db.query(
      'fixed_transactions',
      where: 'userid = ? AND is_deleted = 0',
      whereArgs: [uid],
    );
    return maps.map(FixedTransaction.fromMap).toList();
  }

  /// Ändert eine Serie. Vorher werden noch offene fällige Termine nach den alten Daten gebucht –
  /// sonst ginge z. B. die heute fällige Miete verloren, wenn die App seit gestern offen ist.
  Future<void> updateFixedTransaction(FixedTransaction transaction) async {
    await bookDueFixedTransactions(transaction.userid);
    final db = await _db.database;
    await db.update('fixed_transactions', {...transaction.toMap(), 'last_changed': _now()},
        where: 'id = ?', whereArgs: [transaction.id]);
  }

  Future<void> deleteFixedTransaction(int id) async {
    final db = await _db.database;
    await db.update(
      'fixed_transactions',
      {'is_deleted': 1, 'last_changed': _now()},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Bucht alle fälligen Termine (Datum ≤ heute) aller wiederkehrenden Transaktionen –
  /// auch mehrere verpasste pro Serie – und setzt `nextTime` auf den ersten künftigen
  /// Termin. Serien nach ihrem Enddatum werden beendet.
  ///
  /// Läuft komplett in einem SQL-Transaktionsblock. Gleichzeitige Aufrufe werden von
  /// sqflite serialisiert und sehen dadurch das bereits aktualisierte `nextTime`,
  /// es wird also nichts doppelt gebucht.
  Future<void> bookDueFixedTransactions(int uid, {DateTime? now}) async {
    final today = _day(now ?? DateTime.now());
    final booked = <tr.Transaction>[];
    final db = await _db.database;

    await db.transaction((txn) async {
      final rows = await txn.query('fixed_transactions', where: 'userid = ? AND is_deleted = 0', whereArgs: [uid]);
      for (final row in rows) {
        final ft = FixedTransaction.fromMap(row);
        if (_day(ft.nextTime).isAfter(today)) continue;

        final nextDay = _day(ft.nextTime);
        final endDay = _day(ft.endTime);
        var n = 0;
        while (_day(ft.interval.occurrence(ft.startTime, n)).isBefore(nextDay)) {
          n++;
        }

        DateTime? upcoming;
        for (;; n++) {
          final occ = ft.interval.occurrence(ft.startTime, n);
          if (_day(occ).isAfter(endDay)) break;
          if (_day(occ).isAfter(today)) {
            upcoming = occ;
            break;
          }
          final t = tr.Transaction(
            date: occ,
            amount: ft.amount,
            category: ft.category,
            description: ft.description,
            account: ft.account,
            transactionType: ft.transactionType,
            userid: ft.userid,
          );
          await _insert(txn, t);
          booked.add(t);
        }

        await txn.update(
          'fixed_transactions',
          upcoming == null
              ? {'is_deleted': 1, 'last_changed': _now()}
              : {'next_time': upcoming.toIso8601String(), 'last_changed': _now()},
          where: 'id = ?',
          whereArgs: [ft.id],
        );
      }
    });

    await _checkBudgetAlarms(booked);
  }

  static DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);
}
