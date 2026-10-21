import 'package:flutter/material.dart';

import 'package:frontend/core/models/dates.dart';
import 'package:frontend/features/inventory/models/inventory_item.dart';

/// Abteilungen der Einkaufsliste – bestimmen auch, wohin ein gekaufter Artikel im Inventar wandert.
enum ShoppingCategory {
  food('food', 'Lebensmittel', Icons.local_grocery_store_rounded, InventoryKind.food),
  drinks('drinks', 'Getränke', Icons.local_drink_rounded, InventoryKind.drink),
  care('care', 'Drogerie & Pflege', Icons.spa_rounded, InventoryKind.care),
  clothing('clothing', 'Kleidung', Icons.checkroom_rounded, InventoryKind.clothing),
  household('household', 'Haushalt', Icons.cleaning_services_rounded, InventoryKind.other),
  other('other', 'Sonstiges', Icons.shopping_bag_rounded, InventoryKind.other);

  const ShoppingCategory(this.dbValue, this.label, this.icon, this.inventoryKind);
  final String dbValue;
  final String label;
  final IconData icon;
  final InventoryKind inventoryKind;

  /// Übernahme ins Inventar lohnt sich (Vorrat, Kleiderschrank, Pflege).
  bool get tracksInventory => this != household && this != other;

  String get inventoryTarget => switch (inventoryKind) {
        InventoryKind.clothing => 'Kleiderschrank',
        InventoryKind.care => 'Pflege & Duft',
        _ => 'Vorrat',
      };

  static ShoppingCategory fromDb(Object? v) => values.firstWhere((c) => c.dbValue == v, orElse: () => other);

  /// Ordnet einen Artikel anhand typischer Wörter einer Kategorie zu (für die Übernahme ins
  /// Inventar). Die Anzeige gruppiert feiner nach [ShoppingAisle].
  static ShoppingCategory guess(String name) {
    final n = name.toLowerCase();
    bool any(List<String> words) => words.any(n.contains);
    if (any(['deo', 'parfüm', 'parfum', 'shampoo', 'duschgel', 'zahnpasta', 'zahnbürste', 'creme', 'rasier', 'seife', 'lotion'])) {
      return care;
    }
    if (any(['shirt', 'hose', 'jeans', 'socken', 'pullover', 'jacke', 'schuh', 'hemd', 'unterhose', 'kleid', 'mütze'])) {
      return clothing;
    }
    if (any(['spülmittel', 'waschmittel', 'klopapier', 'toilettenpapier', 'müllbeutel', 'schwamm', 'reiniger', 'küchenrolle'])) {
      return household;
    }
    if (any(['wasser', 'saft', 'drink', 'milch', 'kaffee', 'tee', 'limo', 'bier', 'wein'])) return drinks;
    return food;
  }
}

/// Menge und Name aus einer Eingabe lösen: „600g Magerquark“, „Magerquark 600 g“, „4x Deo“, „Deo 4x“.
/// Liefert (Name, normalisierte Menge oder `null`).
(String, String?) parseShoppingInput(String input) {
  const unit = r'(?:x|×|stk\.?|stück|g|gr|kg|ml|l|pck\.?|packungen?|pakete?|dosen?|flaschen?|becher|gläser|glas|bund|netze?|beutel)';
  final text = input.trim().replaceAll(RegExp(r'\s+'), ' ');
  final prefix = RegExp('^(\\d+(?:[.,]\\d+)?)\\s*($unit)?\\s+(.+)\$', caseSensitive: false).firstMatch(text);
  if (prefix != null) return (prefix.group(3)!, normalizeQuantity(prefix.group(1)!, prefix.group(2)));
  final suffix = RegExp('^(.+?)\\s+(\\d+(?:[.,]\\d+)?)\\s*($unit)?\$', caseSensitive: false).firstMatch(text);
  if (suffix != null) return (suffix.group(1)!, normalizeQuantity(suffix.group(2)!, suffix.group(3)));
  return (text, null);
}

/// „600“, „g“ → „600 g“; „4“, „x“ → „4×“; „2“, null → „2×“.
String normalizeQuantity(String amount, String? unit) {
  final u = (unit ?? '').toLowerCase();
  if (u.isEmpty || u == 'x' || u == '×' || u.startsWith('stk') || u == 'stück') return '$amount×';
  final short = switch (u) {
    'gr' => 'g',
    _ => u,
  };
  return '$amount $short';
}

/// Zahl und Einheit einer Mengenangabe, z. B. „600 g“ → (600, "g"), „4×“ → (4, null).
(double?, String?) splitQuantity(String? quantity) {
  final m = RegExp(r'^\s*(\d+(?:[.,]\d+)?)\s*(×|x)?\s*([a-zA-ZäöüÄÖÜ.]+)?').firstMatch(quantity ?? '');
  if (m == null) return (null, null);
  final amount = double.tryParse(m.group(1)!.replaceAll(',', '.'));
  final u = m.group(3)?.toLowerCase();
  return (amount, const {'g', 'kg', 'ml', 'l'}.contains(u) ? u : null);
}

// ─── Mengen ─────────────────────────────────────────────────────────────

const _unitAliases = {
  'kg': 'kg', 'g': 'g', 'gr': 'g', 'l': 'l', 'ml': 'ml',
  'el': 'EL', 'tl': 'TL', 'prise': 'Prise', 'prisen': 'Prise',
  'dose': 'Dose', 'dosen': 'Dose', 'pck': 'Pck.', 'pck.': 'Pck.', 'packung': 'Pck.', 'packungen': 'Pck.',
  'paket': 'Pck.', 'pakete': 'Pck.', 'flasche': 'Flasche', 'flaschen': 'Flasche', 'becher': 'Becher',
  'glas': 'Glas', 'gläser': 'Glas', 'bund': 'Bund', 'netz': 'Netz', 'netze': 'Netz', 'beutel': 'Beutel',
  'scheibe': 'Scheibe', 'scheiben': 'Scheibe', 'stange': 'Stange', 'stangen': 'Stange',
  'blätter': 'Blatt', 'blatt': 'Blatt', 'zehe': 'Zehe', 'zehen': 'Zehe',
};

const _plurals = {'Dose': 'Dosen', 'Flasche': 'Flaschen', 'Scheibe': 'Scheiben', 'Stange': 'Stangen', 'Zehe': 'Zehen', 'Prise': 'Prisen'};

/// Einheit vereinheitlichen und kg/l in g/ml umrechnen; Stück (×) ist `null`.
(double, String?) normalizeAmount(double amount, String? unit) {
  final u = unit?.trim().toLowerCase();
  if (u == null || u.isEmpty || u == 'x' || u == '×' || u.startsWith('stk') || u == 'stück') return (amount, null);
  final canonical = _unitAliases[u] ?? unit!.trim();
  return switch (canonical) {
    'kg' => (amount * 1000, 'g'),
    'l' => (amount * 1000, 'ml'),
    _ => (amount, canonical),
  };
}

/// Menge aus Text: „600 g“ → (600, "g"), „1,5 kg“ → (1500, "g"), „4x“ → (4, null), „2 Dosen“ → (2, "Dose").
/// Ohne Zahl `null` (dann bleibt der Text als Notiz stehen, z. B. „für Schwester“).
(double, String?)? parseAmount(String? text) {
  final m = RegExp(r'^\s*(\d+(?:[.,]\d+)?)\s*(×|x)?\s*([a-zA-ZäöüÄÖÜß.]+)?\s*$').firstMatch(text ?? '');
  if (m == null) return null;
  final value = double.tryParse(m.group(1)!.replaceAll(',', '.'));
  if (value == null) return null;
  return normalizeAmount(value, m.group(2) != null ? '×' : m.group(3));
}

String _number(double v) {
  final rounded = (v * 100).round() / 100;
  return rounded == rounded.roundToDouble()
      ? rounded.toStringAsFixed(0)
      : rounded.toString().replaceAll(RegExp(r'0+$'), '').replaceAll('.', ',');
}

/// „900 g“, „1,5 kg“, „3×“, „2 Dosen“.
String formatAmount(double amount, String? unit) {
  if (unit == null) return '${_number(amount)}×';
  if (unit == 'g' && amount >= 1000) return '${_number(amount / 1000)} kg';
  if (unit == 'ml' && amount >= 1000) return '${_number(amount / 1000)} l';
  return '${_number(amount)} ${amount > 1 ? (_plurals[unit] ?? unit) : unit}';
}

/// Günstigste Packungskombination für [need] (g/ml) aus höchstens zwei Größen: möglichst wenig
/// übrig, bei Gleichstand möglichst wenige Packungen. Liefert z. B. [(400, 1), (600, 1)].
List<(double, int)> packPlan(double need, List<double> sizes) {
  if (need <= 0 || sizes.isEmpty) return const [];
  List<(double, int)>? best;
  double bestWaste = double.infinity;
  int bestCount = 1 << 30;
  void consider(List<(double, int)> plan) {
    final total = plan.fold(0.0, (s, p) => s + p.$1 * p.$2);
    if (total < need) return;
    final count = plan.fold(0, (s, p) => s + p.$2);
    final waste = total - need;
    if (waste < bestWaste - 1e-9 || (waste - bestWaste).abs() < 1e-9 && count < bestCount) {
      best = plan;
      bestWaste = waste;
      bestCount = count;
    }
  }

  for (final a in sizes) {
    final maxA = (need / a).ceil();
    consider([(a, maxA)]);
    for (final b in sizes) {
      if (b <= a) continue;
      for (var na = 1; na <= maxA; na++) {
        final rest = need - na * a;
        final nb = rest <= 0 ? 0 : (rest / b).ceil();
        if (nb > 0) consider([(a, na), (b, nb)]);
      }
    }
  }
  return best ?? const [];
}

String packPlanLabel(List<(double, int)> plan, String unit) =>
    plan.map((p) => '${p.$2}× ${formatAmount(p.$1, unit)}').join(' + ');

/// Woher ein Teil der Menge eines Einkaufsartikels stammt: ein Rezept (Koch-Block) oder selbst eingetragen.
class ShoppingSource {
  final int? id;
  final int itemId;
  final int userid;
  final double? amount;
  final String? unit;
  final String label;
  final String? recipeKey;
  final int? recipeId;
  final int? batchId;

  const ShoppingSource({
    this.id,
    required this.itemId,
    required this.userid,
    this.amount,
    this.unit,
    required this.label,
    this.recipeKey,
    this.recipeId,
    this.batchId,
  });

  static const manualLabel = 'Selbst eingetragen';

  String? get amountLabel => amount == null ? null : formatAmount(amount!, unit);

  Map<String, dynamic> toMap() => {
        'id': id,
        'itemId': itemId,
        'userid': userid,
        'amount': amount,
        'unit': unit,
        'label': label,
        'recipeKey': recipeKey,
        'recipeId': recipeId,
        'batchId': batchId,
      };

  factory ShoppingSource.fromMap(Map<String, dynamic> m) => ShoppingSource(
        id: m['id'],
        itemId: m['itemId'],
        userid: m['userid'],
        amount: (m['amount'] as num?)?.toDouble(),
        unit: m['unit'],
        label: m['label'] ?? '',
        recipeKey: m['recipeKey'],
        recipeId: m['recipeId'] as int?,
        batchId: m['batchId'] as int?,
      );
}

class ShoppingItem {
  final int? id;
  final int userid;
  final String name;
  final ShoppingCategory category;

  /// Freitext ohne Zahl, z. B. „für Schwester“ (Mengen stehen in [amount]/[unit]).
  final String? quantity;
  final bool done;
  final DateTime? doneAt;

  /// Benötigte Menge (Summe aller Herkünfte); Einheit g/ml/EL/Dose … oder `null` = Stück.
  final double? amount;
  final String? unit;

  /// Zugeordnetes Lebensmittel (für Packungsgrößen und den Vorrat).
  final int? foodId;

  /// Tatsächlich gekaufte Menge (z. B. 600 g statt benötigter 500 g) – landet so im Vorrat.
  final double? boughtAmount;

  /// Beim Abhaken gescannter Barcode – wandert mit in den Vorrat.
  final String? barcode;

  const ShoppingItem({
    this.id,
    required this.userid,
    required this.name,
    this.category = ShoppingCategory.food,
    this.quantity,
    this.done = false,
    this.doneAt,
    this.amount,
    this.unit,
    this.foodId,
    this.boughtAmount,
    this.barcode,
  });

  /// Anzeige der Menge: „900 g“, „3×“ oder der Freitext.
  String? get quantityLabel => amount != null && amount! > 0 ? formatAmount(amount!, unit) : quantity;

  ShoppingItem copyWith({
    String? name,
    ShoppingCategory? category,
    String? quantity,
    bool? done,
    DateTime? doneAt,
    bool clearDoneAt = false,
    double? amount,
    String? unit,
    int? foodId,
    bool clearFood = false,
    double? boughtAmount,
    bool clearBought = false,
    String? barcode,
    bool clearBarcode = false,
  }) =>
      ShoppingItem(
        id: id,
        userid: userid,
        name: name ?? this.name,
        category: category ?? this.category,
        quantity: quantity ?? this.quantity,
        done: done ?? this.done,
        doneAt: clearDoneAt ? null : (doneAt ?? this.doneAt),
        amount: amount ?? this.amount,
        unit: unit ?? this.unit,
        foodId: clearFood ? null : (foodId ?? this.foodId),
        boughtAmount: clearBought ? null : (boughtAmount ?? this.boughtAmount),
        barcode: clearBarcode ? null : (barcode ?? this.barcode),
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'userid': userid,
        'name': name,
        'category': category.dbValue,
        'quantity': quantity,
        'done': done ? 1 : 0,
        'doneAt': doneAt?.toIso8601String(),
        'amount': amount,
        'unit': unit,
        'foodId': foodId,
        'boughtAmount': boughtAmount,
        'barcode': barcode,
      };

  factory ShoppingItem.fromMap(Map<String, dynamic> m) => ShoppingItem(
        id: m['id'],
        userid: m['userid'],
        name: m['name'] ?? '',
        category: ShoppingCategory.fromDb(m['category']),
        quantity: m['quantity'],
        done: m['done'] == 1,
        doneAt: m['doneAt'] == null ? null : DateTime.parse(m['doneAt']),
        amount: (m['amount'] as num?)?.toDouble(),
        unit: m['unit'],
        foodId: m['foodId'] as int?,
        boughtAmount: (m['boughtAmount'] as num?)?.toDouble(),
        barcode: m['barcode'] as String?,
      );
}

/// Anlässe als Vorschläge; frei eingebbar.
const giftOccasions = ['Geburtstag', 'Weihnachten', 'Hochzeit', 'Jahrestag', 'Muttertag', 'Vatertag', 'Einfach so'];

/// Wunsch-/Geschenkeliste für eine Person und einen Anlass, z. B. „Schwester · Geburtstag“.
class GiftList {
  final int? id;
  final int userid;
  final String person;
  final String occasion;
  final DateTime? date;
  final String? notes;
  final List<GiftItem> items;

  const GiftList({
    this.id,
    required this.userid,
    required this.person,
    required this.occasion,
    this.date,
    this.notes,
    this.items = const [],
  });

  String get title => '$person · $occasion';

  int get openCount => items.where((i) => i.status == GiftStatus.idea).length;

  double get plannedSum => items.where((i) => i.status != GiftStatus.idea).fold(0.0, (s, i) => s + (i.price ?? 0));

  /// Tage bis zum Anlass (negativ = vorbei), `null` ohne Datum.
  int? daysUntil(DateTime now) {
    final d = date;
    if (d == null) return null;
    return daysBetween(now, d);
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'userid': userid,
        'person': person,
        'occasion': occasion,
        'date': date?.toIso8601String(),
        'notes': notes,
      };

  factory GiftList.fromMap(Map<String, dynamic> m, {List<GiftItem> items = const []}) => GiftList(
        id: m['id'],
        userid: m['userid'],
        person: m['person'] ?? '',
        occasion: m['occasion'] ?? '',
        date: m['date'] == null ? null : DateTime.parse(m['date']),
        notes: m['notes'],
        items: items,
      );
}

enum GiftStatus {
  idea('idea', 'Idee'),
  bought('bought', 'Gekauft'),
  given('given', 'Verschenkt');

  const GiftStatus(this.dbValue, this.label);
  final String dbValue;
  final String label;

  GiftStatus get next => values[(index + 1) % values.length];

  static GiftStatus fromDb(Object? v) => values.firstWhere((s) => s.dbValue == v, orElse: () => idea);
}

class GiftItem {
  final int? id;
  final int listId;
  final int userid;
  final String name;
  final double? price;
  final String? url;
  final String? notes;
  final GiftStatus status;

  const GiftItem({
    this.id,
    required this.listId,
    required this.userid,
    required this.name,
    this.price,
    this.url,
    this.notes,
    this.status = GiftStatus.idea,
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'listId': listId,
        'userid': userid,
        'name': name,
        'price': price,
        'url': url,
        'notes': notes,
        'status': status.dbValue,
      };

  factory GiftItem.fromMap(Map<String, dynamic> m) => GiftItem(
        id: m['id'],
        listId: m['listId'],
        userid: m['userid'],
        name: m['name'] ?? '',
        price: (m['price'] as num?)?.toDouble(),
        url: m['url'],
        notes: m['notes'],
        status: GiftStatus.fromDb(m['status']),
      );
}

// ─── Gleiche Lebensmittel zusammenfassen, nach Abteilung gruppieren ─────

/// Schlüssel für „dasselbe Lebensmittel“: klein geschrieben, ohne Klammerzusatz („(Dose, abgetropft)“),
/// einfache deutsche Mehrzahl auf die Einzahl gebracht („Zwiebeln“ → „zwiebel“, „Eier“ → „ei“).
String shoppingKey(String name) {
  final words = name
      .toLowerCase()
      .replaceAll(RegExp(r'\([^)]*\)'), ' ')
      .replaceAll(RegExp(r'[^\p{L}\p{N}]+', unicode: true), ' ')
      .trim()
      .split(' ')
      .where((w) => w.isNotEmpty);
  return words.map(_singular).join(' ');
}

String _singular(String w) {
  const irregular = {'eier': 'ei'};
  if (irregular.containsKey(w)) return irregular[w]!;
  // Tomaten → tomate, Zwiebeln → zwiebel, Möhren → möhre, Kartoffeln → kartoffel
  if (w.length > 4 && (w.endsWith('en') || w.endsWith('ln') || w.endsWith('rn'))) return w.substring(0, w.length - 1);
  // Avocados → avocado, Kiwis → kiwi
  if (w.length > 3 && w.endsWith('s') && 'aeiou'.contains(w[w.length - 2])) return w.substring(0, w.length - 1);
  return w;
}

/// Abteilungen im Laden – nur für die Anzeige der Einkaufsliste, in Laufreihenfolge.
enum ShoppingAisle {
  produce('Obst & Gemüse', Icons.eco_rounded),
  bakery('Brot & Backwaren', Icons.bakery_dining_rounded),
  chilled('Kühlregal', Icons.egg_alt_outlined),
  frozen('Tiefkühl', Icons.ac_unit_rounded),
  pantry('Vorrat & Trockenware', Icons.kitchen_rounded),
  drinks('Getränke', Icons.local_drink_rounded),
  care('Drogerie & Pflege', Icons.spa_rounded),
  household('Haushalt', Icons.cleaning_services_rounded),
  clothing('Kleidung', Icons.checkroom_rounded),
  other('Sonstiges', Icons.shopping_bag_rounded);

  const ShoppingAisle(this.label, this.icon);
  final String label;
  final IconData icon;

  static const _produce = [
    'zwiebel', 'knoblauch', 'tomate', 'gurke', 'paprika', 'salat', 'spinat', 'kartoffel', 'möhre', 'karotte', 'apfel',
    'äpfel', 'banane', 'beere', 'zitrone', 'limette', 'avocado', 'brokkoli', 'zucchini', 'aubergine', 'pilz', 'champignon',
    'lauch', 'sellerie', 'ingwer', 'petersilie', 'koriander', 'basilikum', 'kräuter', 'obst', 'gemüse', 'kohl', 'kürbis',
    'birne', 'orange', 'traube', 'kiwi', 'mango', 'rucola', 'radieschen', 'rote bete', 'fenchel', 'süßkartoffel',
  ];
  static const _chilled = [
    'joghurt', 'quark', 'käse', 'butter', 'sahne', 'tofu', 'ei', 'schinken', 'wurst', 'hähnchen', 'fleisch', 'fisch',
    'lachs', 'hack', 'skyr', 'feta', 'mozzarella', 'tempeh', 'frischkäse', 'hummus', 'margarine',
  ];
  static const _bakery = ['brot', 'brötchen', 'toast', 'baguette', 'wrap', 'tortilla', 'croissant', 'semmel'];
  static const _frozen = ['tiefkühl', 'tk', 'eis', 'gefroren', 'pommes'];

  /// Haltbares geht vor, auch wenn ein Gemüse im Namen steckt („Gehackte Tomaten“, „Gemüsebrühe“).
  static const _shelfStable = [
    'gehackt', 'passiert', 'brühe', 'fond', 'mark', 'pulver', 'getrocknet', 'konserve', 'dose', 'glas', 'pesto', 'sauce', 'soße',
  ];

  /// Abteilung eines Artikels: aus seiner Kategorie, bei Lebensmitteln aus typischen Wörtern.
  static ShoppingAisle of(ShoppingItem item) {
    switch (item.category) {
      case ShoppingCategory.drinks:
        return drinks;
      case ShoppingCategory.care:
        return care;
      case ShoppingCategory.household:
        return household;
      case ShoppingCategory.clothing:
        return clothing;
      case ShoppingCategory.other:
        return other;
      case ShoppingCategory.food:
        break;
    }
    final key = shoppingKey(item.name);
    final words = key.split(' ');
    // Kurze Wörter („ei“, „tk“) nur als ganzes Wort, längere auch als Wortanfang („Hähnchenbrust“)
    bool any(List<String> list) => list.any((t) => t.contains(' ')
        ? key.contains(t)
        : words.any((w) => t.length < 4 ? w == t : w.startsWith(t) || w.endsWith(t)));
    if (any(_frozen)) return frozen;
    // Klammerzusatz zählt hier mit („Kidneybohnen (Dose, abgetropft)“)
    final raw = item.name.toLowerCase();
    if (_shelfStable.any(raw.contains)) return pantry;
    if (any(_produce)) return produce;
    if (any(_bakery)) return bakery;
    if (any(_chilled)) return chilled;
    return pantry;
  }
}

/// Ein Lebensmittel auf der Liste – auch über mehrere Einheiten („2× + 200 g Zwiebeln“).
class ShoppingGroup {
  final String key;
  final ShoppingAisle aisle;
  final List<ShoppingItem> items;
  const ShoppingGroup(this.key, this.aisle, this.items);

  String get name => items.first.name;
  bool get done => items.every((i) => i.done);

  String? get quantityLabel {
    final parts = [for (final i in items) if (i.quantityLabel != null) i.quantityLabel!];
    return parts.isEmpty ? null : parts.join(' + ');
  }
}

/// Fasst gleiche Lebensmittel zu Gruppen zusammen und ordnet sie nach Abteilung (innerhalb einer
/// Abteilung in Eingabereihenfolge).
List<ShoppingGroup> groupShopping(List<ShoppingItem> items) {
  final byKey = <String, List<ShoppingItem>>{};
  for (final i in items) {
    byKey.putIfAbsent(shoppingKey(i.name), () => []).add(i);
  }
  final groups = [for (final e in byKey.entries) ShoppingGroup(e.key, ShoppingAisle.of(e.value.first), e.value)];
  final order = {for (final (n, g) in groups.indexed) g.key: n};
  return groups..sort((a, b) => a.aisle.index != b.aisle.index ? a.aisle.index.compareTo(b.aisle.index) : order[a.key]!.compareTo(order[b.key]!));
}
