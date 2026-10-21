import 'package:sqflite/sqflite.dart';
import 'package:frontend/core/models/app_exceptions.dart';
import 'package:frontend/core/database/database.dart';
import 'package:frontend/features/finance/models/transaction.dart' as tr;
import 'package:frontend/features/finance/models/transaction_type.dart';
import 'package:frontend/features/finance/repositories/transaction_repository.dart';
import 'package:frontend/features/inventory/models/inventory_item.dart';
import 'package:frontend/features/inventory/repositories/inventory_repository.dart';
import 'package:frontend/features/style/models/style.dart';

/// Outfits und Wunschliste. Kleidungsstücke selbst liegen im [InventoryRepository].
class StyleRepository {
  StyleRepository({DatabaseService? db, required InventoryRepository inventory, required TransactionRepository transactions})
      : _db = db ?? DatabaseService.instance,
        _inventory = inventory,
        _transactions = transactions;

  final DatabaseService _db;
  final InventoryRepository _inventory;
  final TransactionRepository _transactions;

  /// Standard-Kategorie für Kleidungskäufe (siehe Standarddaten neuer Nutzer).
  static const clothingCategory = 'Kleidung';

  static String _now() => syncStamp();

  // ─── Outfits ──────────────────────────────────────────────────────────

  Future<int> saveOutfit(Outfit outfit) async {
    final db = await _db.database;
    return db.transaction((txn) async {
      final data = outfit.toMap()..remove('id');
      final int id;
      if (outfit.id == null) {
        id = await txn.insert('outfits', data);
      } else {
        id = outfit.id!;
        await txn.update('outfits', {...data, 'last_changed': _now()}, where: 'id = ?', whereArgs: [id]);
        await txn.delete('outfit_items', where: 'outfitId = ?', whereArgs: [id]);
      }
      for (final item in outfit.items) {
        await txn.insert('outfit_items', {'outfitId': id, 'itemId': item.id, 'userid': outfit.userid});
      }
      return id;
    });
  }

  Future<void> deleteOutfit(int id) async {
    final db = await _db.database;
    await db.update('outfits', {'is_deleted': 1, 'last_changed': _now()}, where: 'id = ?', whereArgs: [id]);
  }

  /// Outfits mit ihren (nicht gelöschten) Teilen, zuletzt getragene zuerst.
  Future<void> restoreOutfit(int id) => _db.restoreRow('outfits', id);

  Future<void> restoreWish(int id) => _db.restoreRow('wishlist_items', id);

  Future<List<Outfit>> getOutfits(int uid) async {
    final db = await _db.database;
    final rows = await db.query('outfits',
        where: 'userid = ? AND is_deleted = 0', whereArgs: [uid], orderBy: 'lastWornAt IS NULL, lastWornAt DESC, name COLLATE NOCASE');
    final links = await db.rawQuery('''
      SELECT oi.outfitId, i.* FROM outfit_items oi JOIN inventory_items i ON i.id = oi.itemId
      WHERE oi.userid = ? AND oi.is_deleted = 0 AND i.is_deleted = 0 ORDER BY oi.id
    ''', [uid]);
    final byOutfit = <int, List<InventoryItem>>{};
    for (final l in links) {
      byOutfit.putIfAbsent(l['outfitId'] as int, () => []).add(InventoryItem.fromMap(l));
    }
    return [for (final r in rows) Outfit.fromMap(r, items: byOutfit[r['id']] ?? const [])];
  }

  /// Outfit heute getragen: zählt beim Outfit und bei jedem Teil mit.
  Future<void> wearOutfit(Outfit outfit, {DateTime? at}) async {
    final when = at ?? DateTime.now();
    final db = await _db.database;
    await db.rawUpdate(
      'UPDATE outfits SET lastWornAt = ?, wearCount = COALESCE(wearCount, 0) + 1, last_changed = ? WHERE id = ?',
      [when.toIso8601String(), _now(), outfit.id],
    );
    for (final item in outfit.items) {
      await _inventory.markWorn(item.id!, at: when);
    }
  }

  // ─── Wunschliste ──────────────────────────────────────────────────────

  Future<int> saveWish(WishlistItem wish) async {
    final db = await _db.database;
    if (wish.id == null) return db.insert('wishlist_items', wish.toMap()..remove('id'));
    await db.update('wishlist_items', {...wish.toMap()..remove('id'), 'last_changed': _now()}, where: 'id = ?', whereArgs: [wish.id]);
    return wish.id!;
  }

  Future<void> deleteWish(int id) async {
    final db = await _db.database;
    await db.update('wishlist_items', {'is_deleted': 1, 'last_changed': _now()}, where: 'id = ?', whereArgs: [id]);
  }

  /// Offene Wünsche nach Priorität, danach die gekauften.
  Future<List<WishlistItem>> getWishlist(int uid) async {
    final db = await _db.database;
    final rows = await db.query('wishlist_items',
        where: 'userid = ? AND is_deleted = 0', whereArgs: [uid], orderBy: "status = 'bought', priority DESC, name COLLATE NOCASE");
    return rows.map(WishlistItem.fromMap).toList();
  }

  /// Wunsch gekauft: bucht die Ausgabe in den Finanzen und legt das Teil im Kleiderschrank an.
  /// Liefert die ID des neuen Kleidungsstücks.
  Future<int> buy(WishlistItem wish, {required String account, String category = clothingCategory, double? price, DateTime? date}) async {
    final when = date ?? DateTime.now();
    final amount = price ?? wish.price ?? 0;
    late int itemId;
    // Buchung, Kleiderschrank und Wunsch-Status ganz oder gar nicht; ein zweites Antippen bucht nichts doppelt
    Future<void> rest(DatabaseExecutor txn) async {
      final open = await txn.query('wishlist_items',
          columns: ['id'], where: 'id = ? AND is_deleted = 0 AND status = ?', whereArgs: [wish.id, WishStatus.open.dbValue]);
      if (open.isEmpty) throw UserFacingException('„${wish.name}“ ist schon gekauft.');
      itemId = await _inventory.insertItem(
        txn,
        InventoryItem(
          userid: wish.userid,
          kind: InventoryKind.clothing,
          name: wish.name,
          condition: ItemCondition.newItem,
          purchaseDate: when,
          price: amount > 0 ? amount : null,
          imagePath: wish.imagePath,
        ),
      );
      await txn.update(
        'wishlist_items',
        {'status': WishStatus.bought.dbValue, 'boughtItemId': itemId, 'price': amount > 0 ? amount : wish.price, 'last_changed': _now()},
        where: 'id = ?',
        whereArgs: [wish.id],
      );
    }

    if (amount > 0) {
      await _transactions.createTransaction(
        tr.Transaction(
          date: when,
          amount: amount,
          category: category,
          description: wish.name,
          account: account,
          transactionType: TransactionType.expense,
          userid: wish.userid,
        ),
        together: (txn, _) => rest(txn),
      );
    } else {
      final db = await _db.database;
      await db.transaction(rest);
    }
    return itemId;
  }

  /// Summe offener Wünsche gegen Budget und Ausgaben der Kategorie im laufenden Monat.
  Future<WishlistBudget> getBudget(int uid, {String category = clothingCategory, DateTime? now}) async {
    final db = await _db.database;
    final today = now ?? DateTime.now();
    final open = await db.rawQuery(
      "SELECT COALESCE(SUM(price), 0) AS total FROM wishlist_items WHERE userid = ? AND is_deleted = 0 AND status = 'open'",
      [uid],
    );
    final cat = await db.query('categories',
        columns: ['monthlyBudget'],
        where: 'categoryUserid = ? AND categoryName = ? AND transactionType = ? AND is_deleted = 0',
        whereArgs: [uid, category, TransactionType.expense.dbValue]);
    final spent = await db.rawQuery(
      'SELECT COALESCE(SUM(amount), 0) AS total FROM transactions '
      'WHERE userid = ? AND category = ? AND transactionType = ? AND is_deleted = 0 AND date >= ? AND date < ?',
      [
        uid,
        category,
        TransactionType.expense.dbValue,
        DateTime(today.year, today.month, 1).toIso8601String(),
        DateTime(today.year, today.month + 1, 1).toIso8601String(),
      ],
    );
    return WishlistBudget(
      category: category,
      openSum: (open.first['total'] as num).toDouble(),
      monthlyBudget: cat.isEmpty ? 0 : ((cat.first['monthlyBudget'] as num?)?.toDouble() ?? 0),
      spentThisMonth: (spent.first['total'] as num).toDouble(),
    );
  }
}
