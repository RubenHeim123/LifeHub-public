import 'package:frontend/features/inventory/models/inventory_item.dart';
import 'package:frontend/features/lists/models/lists.dart';
import 'package:frontend/features/meals/models/meal_plan.dart';

/// Wie gut der Vorrat eine Zutat abdeckt.
enum PantryStatus { missing, partial, enough }

/// Ergebnis der Vorratsprüfung für eine Zutat eines Koch-Blocks.
class PantryCheck {
  final Ingredient ingredient;

  /// Bedarf (Rezeptmenge × Faktor) in vereinheitlichter Einheit (kg → g, l → ml); `null` ohne Mengenangabe.
  final double? need;
  final String? needUnit;

  /// Passender Vorratsartikel (auch wenn er gerade ganz reserviert ist).
  final InventoryItem? item;
  final PantryStatus status;

  /// Mengen lassen sich vergleichen (gleiche Einheit bzw. beides Stück).
  final bool comparable;

  /// Noch frei im Vorrat, in der Einheit des Artikels (nach Abzug anderer Reservierungen).
  final double? available;

  /// So viel würde reserviert (Einheit des Artikels); `null` = Menge nicht vergleichbar.
  final double? reserve;

  /// Fehlende Menge in [needUnit], wenn aus dem Vorrat genommen wird (Teilmenge).
  final double? shortfall;

  const PantryCheck({
    required this.ingredient,
    this.need,
    this.needUnit,
    this.item,
    required this.status,
    this.comparable = false,
    this.available,
    this.reserve,
    this.shortfall,
  });

  /// Kann aus dem Vorrat genommen werden.
  bool get inPantry => item != null && status != PantryStatus.missing;
}

String _norm(String s) => s.toLowerCase().replaceAll(RegExp(r'\(.*?\)'), '').replaceAll(RegExp(r'[^a-zäöüß ]'), ' ').trim();

/// Passt der Name des Vorratsartikels zur Zutat („Paprika“ ↔ „Paprika rot“)?
bool matchesIngredient(String ingredient, String itemName) {
  final wanted = _norm(ingredient);
  final firstWord = wanted.split(' ').first;
  if (firstWord.length < 3) return false;
  final have = _norm(itemName);
  if (have == wanted) return true;
  // Kurze Wörter („Ei“, „Öl“, leerer Name) passen sonst zu allem, was so anfängt
  final haveFirst = have.split(' ').first;
  if (haveFirst.length < 3) return false;
  return have.startsWith(firstWord) || wanted.startsWith(haveFirst);
}

/// Erster Vorratsartikel, der zur Zutat passt.
InventoryItem? matchPantryItem(Ingredient ingredient, List<InventoryItem> pantry) =>
    pantry.where((i) => matchesIngredient(ingredient.name, i.name)).firstOrNull;

// Einheiten, die man als Stück zählt (1 Dose ↔ 1 Stück im Vorrat)
const _countUnits = {null, 'Dose', 'Pck.', 'Glas', 'Becher', 'Flasche', 'Bund', 'Netz', 'Beutel', 'Stange'};

/// Prüft alle Zutaten von [recipe] × [factor] gegen den Vorrat. [reserved] sind die Reservierungen
/// **anderer** Koch-Blöcke – was dort zurückgelegt ist, steht hier nicht mehr zur Verfügung.
List<PantryCheck> checkPantryItems({
  required Recipe recipe,
  required double factor,
  required List<InventoryItem> pantry,
  List<PantryReservation> reserved = const [],
}) {
  double reservedOf(int itemId) => reserved.where((r) => r.itemId == itemId).fold(0.0, (s, r) => s + (r.amount ?? 0));

  return [
    for (final ingredient in recipe.ingredients)
      () {
        final (need, needUnit) = ingredient.amount == null ? (null, normalizeAmount(1, ingredient.unit).$2) : normalizeAmount(ingredient.amount! * factor, ingredient.unit);
        final candidates = pantry.where((i) => matchesIngredient(ingredient.name, i.name)).toList();
        if (candidates.isEmpty) {
          return PantryCheck(ingredient: ingredient, need: need, needUnit: needUnit, status: PantryStatus.missing, shortfall: need);
        }

        PantryCheck checkItem(InventoryItem item) {
          final free = (item.quantity - reservedOf(item.id!)).clamp(0, double.infinity).toDouble();
          final (perItem, itemUnit) = normalizeAmount(1, item.unit); // 1 kg → 1000 g
          final comparable = need != null && (itemUnit == needUnit || (_countUnits.contains(itemUnit) && _countUnits.contains(needUnit)));
          if (!comparable) {
            // Mengen nicht vergleichbar (z. B. 1 TL Salz aus einer Packung): vorhanden, solange etwas da ist
            return PantryCheck(
              ingredient: ingredient,
              need: need,
              needUnit: needUnit,
              item: item,
              status: free > 0 ? PantryStatus.enough : PantryStatus.missing,
              available: free,
              shortfall: free > 0 ? null : need,
            );
          }
          final freeNorm = free * perItem;
          if (freeNorm <= 0) {
            return PantryCheck(ingredient: ingredient, need: need, needUnit: needUnit, item: item, status: PantryStatus.missing, comparable: true, available: 0, shortfall: need);
          }
          if (freeNorm >= need - 1e-9) {
            return PantryCheck(ingredient: ingredient, need: need, needUnit: needUnit, item: item, status: PantryStatus.enough, comparable: true, available: free, reserve: need / perItem);
          }
          return PantryCheck(
            ingredient: ingredient,
            need: need,
            needUnit: needUnit,
            item: item,
            status: PantryStatus.partial,
            comparable: true,
            available: free,
            reserve: free,
            shortfall: need - freeNorm,
          );
        }

        // Den ersten Artikel nehmen, der noch etwas frei hat (zwei Packungen Linsen …)
        final checks = candidates.map(checkItem).toList();
        return checks.firstWhere((c) => c.status != PantryStatus.missing, orElse: () => checks.first);
      }(),
  ];
}
