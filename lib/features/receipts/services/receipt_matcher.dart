import 'package:frontend/features/fitness/models/nutrition.dart';
import 'package:frontend/features/inventory/models/inventory_item.dart';
import 'package:frontend/features/lists/models/lists.dart';
import 'package:frontend/features/receipts/models/receipt.dart';
import 'package:frontend/features/receipts/services/receipt_analyzer.dart';

/// Wie eine Bon-Position zum Einkauf desselben Tages passt.
enum ReceiptMatchStatus {
  /// Abgehakt und auf dem Bon, Menge gleich (oder nicht vergleichbar, z. B. Stück ↔ g).
  matched,

  /// Abgehakt und auf dem Bon, aber mit anderer Menge.
  amountDiffers,

  /// Nur auf dem Bon – nicht über die Einkaufsliste in den Vorrat gekommen.
  onlyOnReceipt,
}

/// Abgleich eines Kassenzettels mit dem Einkauf vom selben Tag.
class ShoppingComparison {
  /// Alles, was an dem Tag von der Einkaufsliste in den Vorrat kam (und noch keinen Bon hat).
  final List<InventoryItem> trip;

  /// Bon-Position (Index) → zugehöriger Vorratsartikel aus dem Einkauf.
  final Map<int, InventoryItem> pairs;

  /// Je Bon-Position der Status.
  final List<ReceiptMatchStatus> status;

  const ShoppingComparison({required this.trip, required this.pairs, required this.status});

  static const empty = ShoppingComparison(trip: [], pairs: {}, status: []);

  bool get hasTrip => trip.isNotEmpty;

  /// Abgehakt, aber nicht auf dem Bon.
  List<InventoryItem> get onlyInPantry {
    final paired = pairs.values.map((i) => i.id).toSet();
    return trip.where((i) => !paired.contains(i.id)).toList();
  }

  int get matchedCount => status.where((s) => s != ReceiptMatchStatus.onlyOnReceipt).length;
}

/// Vergleicht Bon-Positionen mit dem Einkauf (nur der übergebene Tag – der Aufrufer lädt ihn).
class ReceiptMatcher {
  const ReceiptMatcher();

  /// Ab diesem Wert gilt ein Paar als dasselbe Produkt.
  static const _threshold = 1.5;

  /// [foods] je Position das von der Prüfansicht zugeordnete Lebensmittel (oder `null`).
  ShoppingComparison compare(List<ReceiptItem> items, List<Food?> foods, List<InventoryItem> trip) {
    if (trip.isEmpty) return ShoppingComparison(trip: trip, pairs: const {}, status: [for (final _ in items) ReceiptMatchStatus.onlyOnReceipt]);
    // Alle Kandidaten bewerten, dann gierig die besten Paare vergeben (jedes nur einmal)
    final candidates = <(double, int, int)>[];
    for (final (i, item) in items.indexed) {
      if (item.isNonGoods) continue;
      final food = i < foods.length ? foods[i] : null;
      for (final (j, p) in trip.indexed) {
        final score = _score(item, food, p);
        if (score >= _threshold) candidates.add((score, i, j));
      }
    }
    candidates.sort((a, b) => b.$1.compareTo(a.$1));
    final pairs = <int, InventoryItem>{};
    final usedTrip = <int>{};
    for (final (_, i, j) in candidates) {
      if (pairs.containsKey(i) || usedTrip.contains(j)) continue;
      pairs[i] = trip[j];
      usedTrip.add(j);
    }
    return ShoppingComparison(
      trip: trip,
      pairs: pairs,
      status: [
        for (final (i, item) in items.indexed)
          pairs[i] == null
              ? ReceiptMatchStatus.onlyOnReceipt
              : amountsDiffer(item, pairs[i]!)
                  ? ReceiptMatchStatus.amountDiffers
                  : ReceiptMatchStatus.matched,
      ],
    );
  }

  static double _score(ReceiptItem item, Food? food, InventoryItem p) {
    if (food?.id != null && food!.id == p.foodId) return 10;
    if (shoppingKey(item.displayName) == shoppingKey(p.name)) return 5;
    return ReceiptAnalyzer.nameScore(item.name, p.name);
  }

  /// Weicht die Bon-Menge von der eingetragenen ab? Nur bei gleicher Einheit (g/ml/Stück) vergleichbar.
  static bool amountsDiffer(ReceiptItem item, InventoryItem p) {
    final (bonAmount, bonUnit) = item.pantryAmount;
    final (amount, unit) = normalizeAmount(p.quantity, p.unit);
    if (bonUnit != unit) return false;
    return (bonAmount - amount).abs() > 0.01 * (amount.abs() < 1 ? 1 : amount.abs());
  }
}
