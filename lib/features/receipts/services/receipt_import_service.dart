import 'package:sqflite/sqflite.dart' show DatabaseExecutor;

import 'package:frontend/core/database/database.dart';
import 'package:frontend/core/models/app_exceptions.dart';
import 'package:frontend/features/finance/models/transaction.dart';
import 'package:frontend/features/finance/models/transaction_type.dart';
import 'package:frontend/features/finance/repositories/transaction_repository.dart';
import 'package:frontend/features/inventory/models/inventory_item.dart';
import 'package:frontend/features/inventory/repositories/inventory_repository.dart';

/// Eine Position, die nach dem Prüfen in den Vorrat kommt.
class PantryLine {
  final String name;
  final double quantity;

  /// g, ml oder `null` = Stück.
  final String? unit;
  final int? foodId;
  final double? price;
  final InventoryKind kind;
  const PantryLine({
    required this.name,
    required this.quantity,
    this.unit,
    this.foodId,
    this.price,
    this.kind = InventoryKind.food,
  });
}

/// Bon-Position, die schon über die Einkaufsliste im Vorrat liegt: wird verknüpft statt doppelt angelegt.
class ReceiptLink {
  final int inventoryId;
  final double? price;

  /// Menge vom Bon übernehmen (sonst bleibt die beim Abhaken eingetragene).
  final double? quantity;
  final String? unit;
  const ReceiptLink({required this.inventoryId, this.price, this.quantity, this.unit});
}

/// Was nach dem Prüfen gespeichert wird: eine Ausgabe mit Bon-Foto und die Vorratsartikel.
class ReceiptDraft {
  final int userid;
  final String description;
  final double amount;
  final DateTime date;
  final String category;
  final String account;
  final String? imagePath;
  final List<PantryLine> pantry;

  /// Positionen, die zum Einkauf vom selben Tag gehören.
  final List<ReceiptLink> links;

  /// Der Bon gehört zum Einkauf von [date]: alles, was an dem Tag von der Liste in den Vorrat kam,
  /// gilt danach als belegt (auch Artikel, die nicht auf dem Bon stehen).
  final bool closesTrip;

  /// Bon zu einer schon vorhandenen Buchung: diese wird aktualisiert statt eine neue angelegt.
  final int? transactionId;
  const ReceiptDraft({
    required this.userid,
    required this.description,
    required this.amount,
    required this.date,
    required this.category,
    required this.account,
    this.imagePath,
    this.pantry = const [],
    this.links = const [],
    this.closesTrip = false,
    this.transactionId,
  });
}

/// Speichert einen geprüften Kassenzettel: Buchung in den Finanzen, Lebensmittel in den Vorrat.
class ReceiptImportService {
  ReceiptImportService({required TransactionRepository transactions, required InventoryRepository inventory})
      : _transactions = transactions,
        _inventory = inventory;

  final TransactionRepository _transactions;
  final InventoryRepository _inventory;

  /// Speichert alles in einer SQL-Transaktion. Liefert die ID der Buchung.
  Future<int> save(ReceiptDraft draft) async {
    if (draft.amount <= 0) throw const UserFacingException('Bitte einen Betrag größer als 0 eintragen.');
    InventoryItem itemFor(PantryLine line, int txId) => InventoryItem(
          userid: draft.userid,
          kind: line.kind,
          name: line.name,
          quantity: line.quantity,
          unit: line.unit,
          foodId: line.foodId,
          price: line.price,
          purchaseDate: draft.date,
          notes: 'Vom Kassenzettel: ${draft.description}',
          receiptTxId: txId,
        );
    final saved = <(InventoryItem, int)>[];
    // Buchung, Vorrat und Abgleich ganz oder gar nicht – sonst stünde nach einem Fehler eine halbe Bon-Buchung da
    Future<void> together(DatabaseExecutor txn, int txId) async {
      for (final line in draft.pantry) {
        final item = itemFor(line, txId);
        saved.add((item, await _inventory.insertItem(txn, item)));
      }
      for (final link in draft.links) {
        await txn.update(
            'inventory_items',
            {
              'receiptTxId': txId,
              if (link.price != null) 'price': link.price,
              if (link.quantity != null) ...{'quantity': link.quantity, 'unit': link.unit},
              'last_changed': syncStamp(),
            },
            where: 'id = ?',
            whereArgs: [link.inventoryId]);
      }
      if (draft.closesTrip) await _inventory.assignTrip(txn, draft.userid, draft.date, txId);
    }

    final transaction = Transaction(
      id: draft.transactionId,
      date: draft.date,
      amount: double.parse(draft.amount.toStringAsFixed(2)),
      category: draft.category,
      description: draft.description,
      account: draft.account,
      transactionType: TransactionType.expense,
      userid: draft.userid,
      imagePath: draft.imagePath,
    );
    final int txId;
    if (draft.transactionId != null) {
      txId = draft.transactionId!;
      await _transactions.updateTransaction(transaction, together: (txn) => together(txn, txId));
    } else {
      txId = await _transactions.createTransaction(transaction, together: together);
    }
    for (final (item, id) in saved) {
      await _inventory.scheduleExpiryReminder(item, id);
    }
    return txId;
  }
}
