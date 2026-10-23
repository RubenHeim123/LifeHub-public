import 'package:sqflite/sqflite.dart';

import 'package:frontend/core/database/database.dart';
import 'package:frontend/features/fitness/models/nutrition.dart';
import 'package:frontend/features/inventory/models/inventory_item.dart';
import 'package:frontend/features/inventory/repositories/inventory_repository.dart';
import 'package:frontend/features/lists/models/lists.dart';

/// Einkaufsliste und Geschenke-Wunschlisten für andere Personen.
class ListsRepository {
  ListsRepository({DatabaseService? db, required InventoryRepository inventory})
      : _db = db ?? DatabaseService.instance,
        _inventory = inventory;

  final DatabaseService _db;
  final InventoryRepository _inventory;

  static String _now() => syncStamp();

  // ─── Einkaufsliste ────────────────────────────────────────────────────

  /// Menge auf die Liste setzen. Steht dasselbe Lebensmittel ([shoppingKey]: auch „Zwiebel“ zu
  /// „Zwiebeln“) mit derselben Einheit schon offen auf der Liste, wird die Menge aufaddiert; woher sie
  /// stammt (Rezept, selbst eingetragen), wird gemerkt.
  /// Liefert die ID des Artikels.
  Future<int> addToList(
    int uid, {
    required String name,
    double? amount,
    String? unit,
    String? note,
    ShoppingCategory? category,
    int? foodId,
    String label = ShoppingSource.manualLabel,
    String? recipeKey,
    int? recipeId,
    int? batchId,
  }) async {
    final db = await _db.database;
    final (value, u) = amount == null ? (null, unit) : normalizeAmount(amount, unit);
    final clean = name.trim();
    return db.transaction((txn) async {
      final key = shoppingKey(clean);
      final open = (await txn.query('shopping_items',
              // Gleiche Einheit – oder beide ohne Menge. (sqflite erlaubt kein null als Argument.)
              where: 'userid = ? AND is_deleted = 0 AND done = 0 AND '
                  '(${u == null ? 'unit IS NULL' : 'unit = ?'}${value == null ? ' OR amount IS NULL' : ''})',
              whereArgs: [uid, if (u != null) u],
              orderBy: 'id'))
          .where((r) => shoppingKey(r['name'] as String? ?? '') == key)
          .toList();
      final int itemId;
      if (open.isNotEmpty) {
        itemId = open.first['id'] as int;
        if (note != null && open.first['quantity'] == null) {
          await txn.update('shopping_items', {'quantity': note}, where: 'id = ?', whereArgs: [itemId]);
        }
      } else {
        itemId = await txn.insert('shopping_items', ShoppingItem(
          userid: uid,
          name: clean,
          category: category ?? ShoppingCategory.guess(clean),
          quantity: note,
          unit: u,
          foodId: foodId ?? await _matchFood(txn, uid, clean),
        ).toMap()..remove('id'));
      }
      await txn.insert('shopping_sources', ShoppingSource(
        itemId: itemId,
        userid: uid,
        amount: value,
        unit: u,
        label: label,
        recipeKey: recipeKey,
        recipeId: recipeId,
        batchId: batchId,
      ).toMap()..remove('id'));
      await _recalc(txn, itemId);
      return itemId;
    });
  }

  /// Neuer Artikel aus dem Formular bzw. Änderungen an einem bestehenden. Eine geänderte Menge wird
  /// als „selbst eingetragen“ verrechnet, damit die Aufteilung nach Rezepten erhalten bleibt.
  Future<int> saveShopping(ShoppingItem item) async {
    if (item.id == null) {
      return addToList(item.userid,
          name: item.name, amount: item.amount, unit: item.unit, note: item.quantity, category: item.category, foodId: item.foodId);
    }
    final db = await _db.database;
    await db.transaction((txn) async {
      final old = ShoppingItem.fromMap((await txn.query('shopping_items', where: 'id = ?', whereArgs: [item.id])).single);
      await txn.update('shopping_items', {
        'name': item.name,
        'category': item.category.dbValue,
        'quantity': item.quantity,
        'foodId': item.foodId,
        'done': item.done ? 1 : 0,
        'doneAt': item.doneAt?.toIso8601String(),
        'boughtAmount': item.boughtAmount,
        'last_changed': _now(),
      }, where: 'id = ?', whereArgs: [item.id]);
      final newAmount = item.amount;
      if (newAmount != null && (newAmount != (old.amount ?? 0) || item.unit != old.unit)) {
        if (item.unit != old.unit) {
          // Neue Einheit: bisherige Aufteilung passt nicht mehr – alles als selbst eingetragen
          await txn.update('shopping_sources', {'is_deleted': 1, 'last_changed': _now()}, where: 'itemId = ?', whereArgs: [item.id]);
          await txn.update('shopping_items', {'unit': item.unit}, where: 'id = ?', whereArgs: [item.id]);
          await txn.insert('shopping_sources', ShoppingSource(
            itemId: item.id!, userid: item.userid, amount: newAmount, unit: item.unit, label: ShoppingSource.manualLabel,
          ).toMap()..remove('id'));
        } else {
          final delta = newAmount - (old.amount ?? 0);
          final manual = await txn.query('shopping_sources',
              where: 'itemId = ? AND is_deleted = 0 AND label = ? AND recipeKey IS NULL AND recipeId IS NULL',
              whereArgs: [item.id, ShoppingSource.manualLabel], limit: 1);
          if (manual.isNotEmpty) {
            final current = (manual.first['amount'] as num?)?.toDouble() ?? 0;
            await txn.update('shopping_sources', {'amount': current + delta, 'last_changed': _now()},
                where: 'id = ?', whereArgs: [manual.first['id']]);
          } else {
            await txn.insert('shopping_sources', ShoppingSource(
              itemId: item.id!, userid: item.userid, amount: delta, unit: item.unit, label: ShoppingSource.manualLabel,
            ).toMap()..remove('id'));
          }
        }
        await _recalc(txn, item.id!);
      }
    });
    return item.id!;
  }

  /// Offene Artikel desselben Lebensmittels mit gleicher Einheit zu einem zusammenführen (Liste aus
  /// älteren Versionen oder vom Abgleich). Herkünfte wandern mit, die Menge wird neu summiert.
  Future<void> _mergeDuplicates(Database db, int uid) async {
    final rows = await db.query('shopping_items',
        columns: ['id', 'name', 'unit'], where: 'userid = ? AND is_deleted = 0 AND done = 0', whereArgs: [uid], orderBy: 'id');
    final groups = <(String, String?), List<int>>{};
    for (final r in rows) {
      groups.putIfAbsent((shoppingKey(r['name'] as String? ?? ''), r['unit'] as String?), () => []).add(r['id'] as int);
    }
    final dupes = groups.values.where((ids) => ids.length > 1).toList();
    if (dupes.isEmpty) return;
    await db.transaction((txn) async {
      for (final ids in dupes) {
        final keep = ids.first;
        for (final other in ids.skip(1)) {
          await txn.update('shopping_sources', {'itemId': keep, 'last_changed': _now()}, where: 'itemId = ?', whereArgs: [other]);
          await txn.update('shopping_items', {'is_deleted': 1, 'last_changed': _now()}, where: 'id = ?', whereArgs: [other]);
        }
        await _recalc(txn, keep);
      }
    });
  }

  /// Summe der Herkünfte neu berechnen.
  Future<void> _recalc(DatabaseExecutor txn, int itemId) async {
    final rows = await txn.rawQuery(
        'SELECT SUM(amount) AS total, COUNT(amount) AS n FROM shopping_sources WHERE itemId = ? AND is_deleted = 0', [itemId]);
    final n = rows.first['n'] as int? ?? 0;
    final total = (rows.first['total'] as num?)?.toDouble();
    await txn.update('shopping_items', {'amount': n == 0 ? null : total, 'last_changed': _now()},
        where: 'id = ?', whereArgs: [itemId]);
  }

  /// Lebensmittel mit passendem Namen (für Packungsgrößen): „Rote Linsen“ ↔ „Rote Linsen (trocken)“.
  Future<int?> _matchFood(DatabaseExecutor txn, int uid, String name) async {
    String norm(String s) => s.toLowerCase().replaceAll(RegExp(r'\(.*?\)'), '').replaceAll(RegExp(r'\s+'), ' ').trim();
    final wanted = norm(name);
    if (wanted.length < 3) return null;
    final rows = await txn.query('foods', columns: ['id', 'name'], where: 'userid = ? AND is_deleted = 0', whereArgs: [uid]);
    int? best;
    var bestScore = 0;
    for (final r in rows) {
      final candidate = norm(r['name'] as String);
      final score = candidate == wanted
          ? 3
          : (candidate.startsWith(wanted) || wanted.startsWith(candidate)) && candidate.length >= 4
              ? 2
              : 0;
      if (score > bestScore) {
        best = r['id'] as int;
        bestScore = score;
      }
    }
    return best;
  }

  /// Eine Liste: offene Artikel in der Reihenfolge des Eintragens, erledigte zuletzt (neueste zuerst).
  Future<List<ShoppingItem>> getShopping(int uid) async {
    final db = await _db.database;
    await _mergeDuplicates(db, uid);
    final rows = await db.query('shopping_items',
        where: 'userid = ? AND is_deleted = 0', whereArgs: [uid], orderBy: 'done, doneAt DESC, id');
    return rows.map(ShoppingItem.fromMap).toList();
  }

  /// Woher die Menge eines Artikels stammt (z. B. „400 g – Ofenkartoffeln“).
  Future<List<ShoppingSource>> getSources(int itemId) async {
    final db = await _db.database;
    final rows = await db.query('shopping_sources', where: 'itemId = ? AND is_deleted = 0', whereArgs: [itemId], orderBy: 'id');
    return rows.map(ShoppingSource.fromMap).toList();
  }

  /// Packungsgrößen der zugeordneten Lebensmittel (foodId → Größen in g/ml).
  Future<Map<int, List<double>>> packSizes(int uid) async {
    final db = await _db.database;
    final rows = await db.query('foods',
        columns: ['id', 'packSizes'], where: 'userid = ? AND is_deleted = 0 AND packSizes IS NOT NULL', whereArgs: [uid]);
    return {for (final r in rows) r['id'] as int: Food.parsePackSizes(r['packSizes'])};
  }

  /// Einen Teil der Menge entfernen. Bleibt nichts übrig, verschwindet der Artikel.
  Future<void> removeSource(ShoppingSource source) async {
    final db = await _db.database;
    await db.transaction((txn) async {
      await txn.update('shopping_sources', {'is_deleted': 1, 'last_changed': _now()}, where: 'id = ?', whereArgs: [source.id]);
      await _recalcOrDelete(txn, source.itemId);
    });
  }

  Future<void> restoreSource(ShoppingSource source) async {
    final db = await _db.database;
    await db.transaction((txn) async {
      await txn.update('shopping_sources', {'is_deleted': 0, 'last_changed': _now()}, where: 'id = ?', whereArgs: [source.id]);
      await txn.update('shopping_items', {'is_deleted': 0, 'last_changed': _now()}, where: 'id = ?', whereArgs: [source.itemId]);
      await _recalc(txn, source.itemId);
    });
  }

  Future<void> _recalcOrDelete(DatabaseExecutor txn, int itemId) async {
    final left = await txn.query('shopping_sources', where: 'itemId = ? AND is_deleted = 0', whereArgs: [itemId]);
    if (left.isEmpty) {
      await txn.update('shopping_items', {'is_deleted': 1, 'last_changed': _now()}, where: 'id = ?', whereArgs: [itemId]);
    } else {
      await _recalc(txn, itemId);
    }
  }

  /// Alle Mengen eines Koch-Blocks (oder Rezepts) wieder von der Liste nehmen – z. B. nach einem
  /// Vertipper. Artikel ohne verbleibende Herkunft verschwinden. Liefert den Zeitstempel fürs Rückgängig.
  /// Mit [onlyOpen] bleiben die Herkünfte schon gekaufter Artikel stehen – so weiß ein erneutes
  /// Planen, was schon gekauft ist ([boughtFor]).
  Future<String> removeFromList(int uid,
      {int? batchId, String? recipeKey, int? recipeId, bool onlyWithoutBatch = false, bool onlyOpen = false}) async {
    final db = await _db.database;
    final at = _now();
    await db.transaction((txn) async {
      final where = (batchId != null
              ? 'batchId = ?'
              : recipeKey != null
                  ? 'recipeKey = ?'
                  : 'recipeId = ?') +
          (onlyWithoutBatch ? ' AND batchId IS NULL' : '') +
          (onlyOpen ? ' AND itemId IN (SELECT id FROM shopping_items WHERE done = 0)' : '');
      final arg = batchId ?? recipeKey ?? recipeId;
      final rows = await txn.query('shopping_sources',
          columns: ['itemId'], where: 'userid = ? AND is_deleted = 0 AND $where', whereArgs: [uid, arg]);
      await txn.update('shopping_sources', {'is_deleted': 1, 'last_changed': at},
          where: 'userid = ? AND is_deleted = 0 AND $where', whereArgs: [uid, arg]);
      for (final itemId in {for (final r in rows) r['itemId'] as int}) {
        final left = await txn.query('shopping_sources', where: 'itemId = ? AND is_deleted = 0', whereArgs: [itemId]);
        if (left.isEmpty) {
          await txn.update('shopping_items', {'is_deleted': 1, 'last_changed': at}, where: 'id = ? AND done = 0', whereArgs: [itemId]);
        } else {
          await _recalc(txn, itemId);
        }
      }
    });
    return at;
  }

  /// Für einen Koch-Block schon gekaufte (abgehakte) Mengen je Zutat und Einheit, Name klein
  /// geschrieben. Zählt auch Gekauftes, das schon in den Vorrat gewandert oder von der Liste geräumt ist. `null` als Menge: gekauft, aber ohne Mengenangabe (gilt als erledigt).
  Future<Map<(String, String?), double?>> boughtFor(int uid, int batchId) async {
    final db = await _db.database;
    final rows = await db.rawQuery('''
        SELECT LOWER(i.name) AS name, s.unit AS unit, s.amount AS amount FROM shopping_sources s
        JOIN shopping_items i ON i.id = s.itemId AND i.done = 1
        WHERE s.userid = ? AND s.is_deleted = 0 AND s.batchId = ?''', [uid, batchId]);
    final out = <(String, String?), double?>{};
    for (final r in rows) {
      final key = (r['name'] as String, r['unit'] as String?);
      final amount = (r['amount'] as num?)?.toDouble();
      out[key] = out.containsKey(key) && (out[key] == null || amount == null) ? null : (out[key] ?? 0) + (amount ?? 0);
      if (amount == null) out[key] = null;
    }
    return out;
  }

  /// Macht [removeFromList] rückgängig.
  Future<void> restoreRemoved(int uid, String at) async {
    final db = await _db.database;
    await db.transaction((txn) async {
      final rows = await txn.query('shopping_sources',
          columns: ['itemId'], where: 'userid = ? AND is_deleted = 1 AND last_changed = ?', whereArgs: [uid, at]);
      await txn.update('shopping_sources', {'is_deleted': 0}, where: 'userid = ? AND is_deleted = 1 AND last_changed = ?', whereArgs: [uid, at]);
      await txn.update('shopping_items', {'is_deleted': 0}, where: 'userid = ? AND is_deleted = 1 AND last_changed = ?', whereArgs: [uid, at]);
      for (final itemId in {for (final r in rows) r['itemId'] as int}) {
        await _recalc(txn, itemId);
      }
    });
  }

  /// Abhaken bzw. wieder öffnen. [bought] ist die tatsächlich gekaufte Menge (z. B. Packungsgröße), in
  /// der Einheit des Artikels oder – falls angegeben – in [boughtUnit] (`(null,)` = Stück).
  /// [barcode]/[foodId] kommen z. B. vom Scan beim Abhaken.
  Future<ShoppingItem> toggleShopping(ShoppingItem item,
      {DateTime? at, double? bought, (String?,)? boughtUnit, String? barcode, int? foodId}) async {
    var updated = item.done
        ? item.copyWith(done: false, clearDoneAt: true, clearBought: true)
        : item.copyWith(done: true, doneAt: at ?? DateTime.now(), boughtAmount: bought, barcode: barcode, foodId: foodId);
    final unitChanged = !item.done && bought != null && boughtUnit != null && boughtUnit.$1 != item.unit;
    if (unitChanged) {
      updated = ShoppingItem.fromMap({...updated.toMap(), 'unit': boughtUnit.$1});
    }
    final db = await _db.database;
    await db.update('shopping_items', {
      'done': updated.done ? 1 : 0,
      'doneAt': updated.doneAt?.toIso8601String(),
      'boughtAmount': updated.boughtAmount,
      'barcode': updated.barcode,
      'foodId': updated.foodId,
      if (unitChanged) 'unit': boughtUnit.$1,
      'last_changed': _now(),
    }, where: 'id = ?', whereArgs: [item.id]);
    return updated;
  }

  Future<void> deleteShopping(int id) async {
    final db = await _db.database;
    await db.update('shopping_items', {'is_deleted': 1, 'last_changed': _now()}, where: 'id = ?', whereArgs: [id]);
  }

  Future<void> restoreShopping(int id) => _db.restoreRow('shopping_items', id);

  /// Entfernt alle abgehakten Artikel. Liefert die Anzahl.
  Future<int> clearDone(int uid) async {
    final db = await _db.database;
    return db.update('shopping_items', {'is_deleted': 1, 'last_changed': _now()},
        where: 'userid = ? AND done = 1 AND is_deleted = 0', whereArgs: [uid]);
  }

  /// Gekauften Artikel in den Vorrat (Kleidung: Kleiderschrank) übernehmen und von der Liste nehmen –
  /// mit der tatsächlich gekauften Menge (z. B. 600 g statt 500 g).
  /// Verschiebt einen (gekauften) Artikel ins Inventar. Liefert die neue Inventar-ID – oder `null`, wenn
  /// der Artikel schon verschoben oder gelöscht wurde (doppeltes Antippen bucht nichts doppelt).
  Future<int?> moveToInventory(ShoppingItem item) async {
    final kind = item.category.inventoryKind;
    final (legacyAmount, legacyUnit) = splitQuantity(item.quantity);
    final amount = item.boughtAmount ?? item.amount ?? legacyAmount;
    final unit = item.amount != null || item.boughtAmount != null ? item.unit : legacyUnit;
    final entry = InventoryItem(
      userid: item.userid,
      kind: kind,
      name: item.name,
      category: item.category.inventoryCategory,
      quantity: amount ?? 1,
      unit: unit,
      foodId: item.foodId,
      barcode: item.barcode,
      purchaseDate: item.doneAt ?? DateTime.now(),
      condition: kind.isWearable ? ItemCondition.newItem : null,
      fromShopping: true,
    );
    final db = await _db.database;
    final id = await db.transaction<int?>((txn) async {
      final removed = await txn.update('shopping_items', {'is_deleted': 1, 'last_changed': _now()},
          where: 'id = ? AND is_deleted = 0', whereArgs: [item.id]);
      if (removed == 0) return null;
      return txn.insert('inventory_items', entry.toMap()..remove('id'));
    });
    if (id != null) await _inventory.scheduleExpiryReminder(entry, id);
    return id;
  }

  /// Macht Abhaken + [moveToInventory] rückgängig: Vorratseintrag weg, Artikel wieder offen auf der Liste
  /// – so, wie [original] vor dem Abhaken war.
  Future<void> undoMoveToInventory(ShoppingItem original, int inventoryId) async {
    final db = await _db.database;
    await db.transaction((txn) async {
      // fromShopping = 0: zählt nicht mehr als Einkauf, der einen Kassenzettel braucht
      await txn.update('inventory_items', {'is_deleted': 1, 'fromShopping': 0, 'last_changed': _now()},
          where: 'id = ?', whereArgs: [inventoryId]);
      await txn.update('shopping_items', {
        'is_deleted': 0,
        'done': 0,
        'doneAt': null,
        'boughtAmount': null,
        'barcode': original.barcode,
        'unit': original.unit,
        'foodId': original.foodId,
        'last_changed': _now(),
      }, where: 'id = ?', whereArgs: [original.id]);
    });
  }

  // ─── Geschenke ────────────────────────────────────────────────────────

  Future<int> saveGiftList(GiftList list) async {
    final db = await _db.database;
    if (list.id == null) return db.insert('gift_lists', list.toMap()..remove('id'));
    await db.update('gift_lists', {...list.toMap()..remove('id'), 'last_changed': _now()},
        where: 'id = ?', whereArgs: [list.id]);
    return list.id!;
  }

  Future<void> deleteGiftList(int id) async {
    final db = await _db.database;
    final now = _now();
    await db.transaction((txn) async {
      await txn.update('gift_lists', {'is_deleted': 1, 'last_changed': now}, where: 'id = ?', whereArgs: [id]);
      await txn.update('gift_items', {'is_deleted': 1, 'last_changed': now},
          where: 'listId = ? AND is_deleted = 0', whereArgs: [id]);
    });
  }

  /// Stellt eine gelöschte Liste mit den zusammen mit ihr gelöschten Ideen wieder her.
  Future<void> restoreGiftList(int id) async {
    final db = await _db.database;
    final rows = await db.query('gift_lists', columns: ['last_changed'], where: 'id = ?', whereArgs: [id]);
    if (rows.isEmpty) return;
    final deletedAt = rows.first['last_changed'];
    final now = _now();
    await db.transaction((txn) async {
      await txn.update('gift_lists', {'is_deleted': 0, 'last_changed': now}, where: 'id = ?', whereArgs: [id]);
      await txn.update('gift_items', {'is_deleted': 0, 'last_changed': now},
          where: 'listId = ? AND is_deleted = 1 AND last_changed = ?', whereArgs: [id, deletedAt]);
    });
  }

  Future<void> restoreGift(int id) => _db.restoreRow('gift_items', id);

  /// Listen mit ihren Geschenken; anstehende Anlässe zuerst, ohne Datum danach, vergangene zuletzt.
  Future<List<GiftList>> getGiftLists(int uid, {DateTime? now}) async {
    final db = await _db.database;
    final rows = await db.query('gift_lists', where: 'userid = ? AND is_deleted = 0', whereArgs: [uid]);
    final items = await db.query('gift_items', where: 'userid = ? AND is_deleted = 0', whereArgs: [uid], orderBy: 'id');
    final byList = <int, List<GiftItem>>{};
    for (final i in items) {
      byList.putIfAbsent(i['listId'] as int, () => []).add(GiftItem.fromMap(i));
    }
    final today = now ?? DateTime.now();
    int rank(GiftList l) {
      final d = l.daysUntil(today);
      return d == null ? 1 : (d < 0 ? 2 : 0);
    }

    final lists = [for (final r in rows) GiftList.fromMap(r, items: byList[r['id']] ?? const [])];
    lists.sort((a, b) {
      final r = rank(a).compareTo(rank(b));
      if (r != 0) return r;
      final da = a.daysUntil(today), dbb = b.daysUntil(today);
      if (da != null && dbb != null) return da.abs().compareTo(dbb.abs());
      return a.person.toLowerCase().compareTo(b.person.toLowerCase());
    });
    return lists;
  }

  Future<GiftList?> getGiftList(int id) async {
    final db = await _db.database;
    final rows = await db.query('gift_lists', where: 'id = ? AND is_deleted = 0', whereArgs: [id]);
    if (rows.isEmpty) return null;
    final items = await db.query('gift_items', where: 'listId = ? AND is_deleted = 0', whereArgs: [id], orderBy: 'id');
    return GiftList.fromMap(rows.first, items: items.map(GiftItem.fromMap).toList());
  }

  Future<int> saveGift(GiftItem gift) async {
    final db = await _db.database;
    if (gift.id == null) return db.insert('gift_items', gift.toMap()..remove('id'));
    await db.update('gift_items', {...gift.toMap()..remove('id'), 'last_changed': _now()},
        where: 'id = ?', whereArgs: [gift.id]);
    return gift.id!;
  }

  Future<void> setGiftStatus(GiftItem gift, GiftStatus status) async {
    final db = await _db.database;
    await db.update('gift_items', {'status': status.dbValue, 'last_changed': _now()}, where: 'id = ?', whereArgs: [gift.id]);
  }

  Future<void> deleteGift(int id) async {
    final db = await _db.database;
    await db.update('gift_items', {'is_deleted': 1, 'last_changed': _now()}, where: 'id = ?', whereArgs: [id]);
  }

  /// Geschenkidee auf die Einkaufsliste setzen (Abteilung „Sonstiges“, Notiz mit Person).
  Future<int> giftToShopping(GiftItem gift, GiftList list) => addToList(
        gift.userid,
        name: gift.name,
        category: ShoppingCategory.other,
        note: 'für ${list.person}',
        label: 'Geschenk für ${list.person}',
      );
}
