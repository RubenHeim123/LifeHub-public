/// Eine Position auf dem Kassenzettel, z. B. „HAFERFLOCKEN 500G  0,59 A“.
class ReceiptItem {
  /// Text, wie er auf dem Bon steht (bereinigt um Steuerkennzeichen).
  final String name;

  /// Gesamtpreis der Position (bei Rabatten negativ).
  final double price;

  /// Stückzahl („2 x 0,89“), mindestens 1.
  final int count;

  /// Abgewogene Ware („1,230 kg x 1,45 EUR/kg“) in kg.
  final double? weightKg;

  const ReceiptItem({required this.name, required this.price, this.count = 1, this.weightKg});

  ReceiptItem copyWith({int? count, double? weightKg, double? price}) =>
      ReceiptItem(name: name, price: price ?? this.price, count: count ?? this.count, weightKg: weightKg ?? this.weightKg);

  /// Pfand, Leergut, Rabatte und Tüten sind keine Ware für den Vorrat.
  bool get isNonGoods {
    final n = name.toLowerCase();
    return price < 0 ||
        const ['pfand', 'leergut', 'rabatt', 'coupon', 'gutschein', 'tragetasche', 'tüte', 'tuete', 'tasche']
            .any(n.contains);
  }

  /// Packungsgröße aus dem Namen („QUARK 500G“, „MILCH 1,5L“) – als (Menge, Einheit g/ml).
  (double, String)? get packSize {
    final m = RegExp(r'(\d+(?:[.,]\d+)?)\s*(kg|g|ml|l)\b', caseSensitive: false).firstMatch(name);
    if (m == null) return null;
    final v = double.tryParse(m.group(1)!.replaceAll(',', '.'));
    if (v == null || v <= 0) return null;
    return switch (m.group(2)!.toLowerCase()) {
      'kg' => (v * 1000, 'g'),
      'l' => (v * 1000, 'ml'),
      'ml' => (v, 'ml'),
      _ => (v, 'g'),
    };
  }

  /// Menge für den Vorrat: Gewicht in g, sonst Packungsgröße × Stück, sonst Stückzahl.
  (double, String?) get pantryAmount {
    if (weightKg != null) return ((weightKg! * 1000).roundToDouble(), 'g');
    final size = packSize;
    if (size != null) return (size.$1 * count, size.$2);
    return (count.toDouble(), null);
  }

  /// Lesbarer Name: „HAFERFLOCKEN 500G“ → „Haferflocken“.
  String get displayName {
    final cleaned = name
        .replaceAll(RegExp(r'(\d+(?:[.,]\d+)?)\s*(kg|g|ml|l)\b', caseSensitive: false), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (cleaned.isEmpty) return name;
    final upper = cleaned == cleaned.toUpperCase();
    if (!upper) return cleaned;
    return cleaned
        .toLowerCase()
        .split(' ')
        .map((w) => w.isEmpty ? w : w[0].toUpperCase() + w.substring(1))
        .join(' ');
  }
}

enum ReceiptPayment { card, cash, unknown }

/// Was auf dem Kassenzettel erkannt wurde.
class ParsedReceipt {
  final String? store;
  final DateTime? date;
  final double? total;
  final ReceiptPayment payment;
  final List<ReceiptItem> items;

  /// Die erkannten Textzeilen (zum Nachsehen in der Prüfansicht).
  final List<String> lines;

  const ParsedReceipt({
    this.store,
    this.date,
    this.total,
    this.payment = ReceiptPayment.unknown,
    this.items = const [],
    this.lines = const [],
  });

  double get itemsSum => items.fold(0, (s, i) => s + i.price);

  /// Betrag der Buchung: die Summe vom Bon, sonst die Summe der Positionen.
  double? get amount => total ?? (items.isEmpty ? null : double.parse(itemsSum.toStringAsFixed(2)));

  /// Passen Summe und Positionen zusammen? (Hinweis in der Prüfansicht)
  bool get sumMatches => total == null || items.isEmpty || (total! - itemsSum).abs() < 0.015;
}
