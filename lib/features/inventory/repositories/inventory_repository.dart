import 'package:sqflite/sqflite.dart';

import 'package:frontend/core/database/database.dart';
import 'package:frontend/core/services/notification_service.dart';
import 'package:frontend/features/inventory/models/inventory_item.dart';

/// Vorrat und Kleiderschrank.
class InventoryRepository {
  InventoryRepository({DatabaseService? db, NotificationService? notifications})
      : _db = db ?? DatabaseService.instance,
        _notifications = notifications ?? NotificationService();

  final DatabaseService _db;
  final NotificationService _notifications;

  static String _now() => syncStamp();

  Future<int> createItem(InventoryItem item) async {
    final db = await _db.database;
    final id = await insertItem(db, item);
    await scheduleExpiryReminder(item, id);
    return id;
  }

  /// Legt [item] innerhalb einer laufenden SQL-Transaktion an – die Erinnerung plant der Aufrufer
  /// danach mit [scheduleExpiryReminder].
  Future<int> insertItem(DatabaseExecutor ex, InventoryItem item) => ex.insert('inventory_items', item.toMap()..remove('id'));

  // ─── Einkauf ↔ Kassenzettel ───────────────────────────────────────────

  static String _day(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  /// Was am Kalendertag [day] von der Einkaufsliste in den Vorrat gewandert ist und noch keinen
  /// Kassenzettel hat – nur damit wird ein Bon von diesem Tag abgeglichen. Schon Verbrauchtes zählt mit.
  Future<List<InventoryItem>> shoppingTrip(int uid, DateTime day) async {
    final db = await _db.database;
    final rows = await db.query('inventory_items',
        where: 'userid = ? AND fromShopping = 1 AND receiptTxId IS NULL AND substr(purchaseDate, 1, 10) = ?',
        whereArgs: [uid, _day(day)],
        orderBy: 'id');
    return rows.map(InventoryItem.fromMap).toList();
  }

  /// Einkaufstage ohne Kassenzettel, neueste zuerst: (Tag, Anzahl Artikel). Nur heute und die letzten
  /// [days] Tage – danach erinnert der Hinweis nicht mehr (ein Bon ist kein Muss).
  Future<List<(DateTime, int)>> tripsWithoutReceipt(int uid, {int days = 1, DateTime? now}) async {
    final db = await _db.database;
    final since = (now ?? DateTime.now()).subtract(Duration(days: days));
    final rows = await db.rawQuery('''
        SELECT substr(purchaseDate, 1, 10) AS day, COUNT(*) AS n FROM inventory_items
        WHERE userid = ? AND fromShopping = 1 AND receiptTxId IS NULL AND substr(purchaseDate, 1, 10) >= ?
        GROUP BY day ORDER BY day DESC''', [uid, _day(since)]);
    return [for (final r in rows) (DateTime.parse(r['day'] as String), r['n'] as int)];
  }

  /// Ordnet den Einkauf vom Tag [day] einem Bon zu ([txId]) – `0` = bewusst ohne Bon erledigt.
  Future<void> assignTrip(DatabaseExecutor ex, int uid, DateTime day, int txId) => ex.update(
        'inventory_items',
        {'receiptTxId': txId, 'last_changed': _now()},
        where: 'userid = ? AND fromShopping = 1 AND receiptTxId IS NULL AND substr(purchaseDate, 1, 10) = ?',
        whereArgs: [uid, _day(day)],
      );

  /// Einkaufstag ohne Kassenzettel abschließen (z. B. Wochenmarkt). Liefert den Zeitstempel fürs Rückgängig.
  Future<String> dismissTrip(int uid, DateTime day) async {
    final db = await _db.database;
    final at = _now();
    await db.update('inventory_items', {'receiptTxId': 0, 'last_changed': at},
        where: 'userid = ? AND fromShopping = 1 AND receiptTxId IS NULL AND substr(purchaseDate, 1, 10) = ?',
        whereArgs: [uid, _day(day)]);
    return at;
  }

  /// Macht [dismissTrip] rückgängig.
  Future<void> undoDismissTrip(int uid, String at) async {
    final db = await _db.database;
    await db.update('inventory_items', {'receiptTxId': null, 'last_changed': _now()},
        where: 'userid = ? AND receiptTxId = 0 AND last_changed = ?', whereArgs: [uid, at]);
  }

  Future<void> updateItem(InventoryItem item) async {
    final db = await _db.database;
    await db.update('inventory_items', {...item.toMap()..remove('id'), 'last_changed': _now()},
        where: 'id = ?', whereArgs: [item.id]);
    await scheduleExpiryReminder(item, item.id!);
  }

  Future<void> deleteItem(int id) async {
    final db = await _db.database;
    await db.update('inventory_items', {'is_deleted': 1, 'last_changed': _now()}, where: 'id = ?', whereArgs: [id]);
    await _notifications.cancelNotification(NotificationService.inventoryIdOffset + id);
  }

  /// Macht einen gelöschten Eintrag wieder sichtbar und plant die Ablauf-Erinnerung neu.
  Future<void> restoreItem(InventoryItem item) async {
    await _db.restoreRow('inventory_items', item.id!);
    await scheduleExpiryReminder(item, item.id!);
  }

  Future<InventoryItem?> getItem(int id) async {
    final db = await _db.database;
    final rows = await db.query('inventory_items', where: 'id = ? AND is_deleted = 0', whereArgs: [id]);
    return rows.isEmpty ? null : InventoryItem.fromMap(rows.first);
  }

  /// Alle Einträge eines Nutzers, optional nur bestimmte Arten.
  Future<List<InventoryItem>> getItems(int uid, {Set<InventoryKind>? kinds}) async {
    final db = await _db.database;
    var where = 'userid = ? AND is_deleted = 0';
    final args = <Object>[uid];
    if (kinds != null && kinds.isNotEmpty) {
      where += ' AND kind IN (${List.filled(kinds.length, '?').join(',')})';
      args.addAll(kinds.map((k) => k.dbValue));
    }
    final rows = await db.query('inventory_items', where: where, whereArgs: args, orderBy: 'name COLLATE NOCASE');
    return rows.map(InventoryItem.fromMap).toList();
  }

  /// Vorrat, der innerhalb von [days] Tagen abläuft oder schon abgelaufen ist – dringendstes zuerst.
  Future<List<InventoryItem>> getExpiring(int uid, {int days = 3, DateTime? now}) async {
    final n = now ?? DateTime.now();
    final limit = DateTime(n.year, n.month, n.day + days + 1);
    final db = await _db.database;
    final rows = await db.query('inventory_items',
        where: 'userid = ? AND is_deleted = 0 AND expiryDate IS NOT NULL AND expiryDate < ?',
        whereArgs: [uid, limit.toIso8601String()],
        orderBy: 'expiryDate');
    return rows.map(InventoryItem.fromMap).toList();
  }

  /// Verbraucht [amount] (Standard 1). Bei 0 gilt der Eintrag als aufgebraucht und
  /// verschwindet aus dem Vorrat. Gibt die Restmenge zurück.
  Future<double> consume(InventoryItem item, {double amount = 1}) async {
    final rest = item.quantity - amount;
    if (rest <= 0) {
      await deleteItem(item.id!);
      return 0;
    }
    final db = await _db.database;
    await db.update('inventory_items', {'quantity': rest, 'lastUsedAt': _now(), 'last_changed': _now()},
        where: 'id = ?', whereArgs: [item.id]);
    return rest;
  }

  /// Wie [consume], aber innerhalb einer laufenden SQL-Transaktion und mit dem aktuellen Bestand aus der DB.
  /// Liefert den Rest – `null`, wenn der Artikel inzwischen gelöscht ist. Bei 0 muss der Aufrufer danach
  /// [cancelExpiryReminder] aufrufen.
  Future<double?> consumeIn(DatabaseExecutor ex, int id, double amount) async {
    final rows = await ex.query('inventory_items', columns: ['quantity'], where: 'id = ? AND is_deleted = 0', whereArgs: [id]);
    if (rows.isEmpty) return null;
    final rest = ((rows.first['quantity'] as num?)?.toDouble() ?? 0) - amount;
    if (rest <= 0) {
      await ex.update('inventory_items', {'is_deleted': 1, 'last_changed': _now()}, where: 'id = ?', whereArgs: [id]);
      return 0;
    }
    await ex.update('inventory_items', {'quantity': rest, 'lastUsedAt': _now(), 'last_changed': _now()},
        where: 'id = ?', whereArgs: [id]);
    return rest;
  }

  Future<void> cancelExpiryReminder(int id) => _notifications.cancelNotification(NotificationService.inventoryIdOffset + id);

  /// Kleidung: heute getragen.
  Future<void> markWorn(int id, {DateTime? at}) async {
    final db = await _db.database;
    await db.rawUpdate(
      'UPDATE inventory_items SET lastUsedAt = ?, wearCount = COALESCE(wearCount, 0) + 1, last_changed = ? WHERE id = ?',
      [(at ?? DateTime.now()).toIso8601String(), _now(), id],
    );
  }

  /// Plant die Ablauf-Erinnerungen aller Vorratsartikel neu (beim Anmelden).
  Future<void> refreshReminders(int uid) async {
    for (final item in await getItems(uid)) {
      if (item.id != null && item.expiryDate != null && item.kind.isConsumable) await scheduleExpiryReminder(item, item.id!);
    }
  }

  /// Erinnerung um 9 Uhr am Vortag des Ablaufs (bzw. sofort am Morgen, falls das schon vorbei ist).
  Future<void> scheduleExpiryReminder(InventoryItem item, int id) async {
    final notificationId = NotificationService.inventoryIdOffset + id;
    await _notifications.cancelNotification(notificationId);
    final expiry = item.expiryDate;
    if (expiry == null || !item.kind.isConsumable) return;
    await _notifications.scheduleNotification(
      id: notificationId,
      title: '${item.name} läuft morgen ab',
      body: item.location == null ? 'Bald verbrauchen.' : 'Liegt im ${item.location}.',
      scheduledDate: DateTime(expiry.year, expiry.month, expiry.day - 1, 9),
    );
  }
}
