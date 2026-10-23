import 'package:frontend/core/models/dates.dart';

/// Was für ein Inventar-Eintrag es ist. [dbValue] wird gespeichert.
enum InventoryKind {
  food('food', 'Lebensmittel'),
  drink('drink', 'Getränk'),
  clothing('clothing', 'Kleidung'),
  accessory('accessory', 'Accessoire'),
  care('care', 'Pflege & Duft'),
  other('other', 'Sonstiges');

  const InventoryKind(this.dbValue, this.label);
  final String dbValue;
  final String label;

  /// Wird verbraucht (Menge, Ablaufdatum) statt getragen.
  bool get isConsumable => this == food || this == drink || this == care;

  /// Wird getragen (Tragezähler, „lange nicht getragen“).
  bool get isWearable => this == clothing || this == accessory;

  static InventoryKind fromDb(Object? v) => values.firstWhere((k) => k.dbValue == v, orElse: () => other);

  /// Vorschläge für Kategorien und Orte je Art.
  List<String> get suggestedCategories => switch (this) {
        food => const ['Obst & Gemüse', 'Milchprodukte', 'Fleisch & Fisch', 'Brot & Backwaren', 'Vorräte', 'Tiefkühl', 'Snacks', 'Sonstiges'],
        drink => const ['Wasser', 'Softdrinks', 'Säfte', 'Kaffee & Tee', 'Sport & Protein', 'Alkohol', 'Sonstiges'],
        clothing => const ['Oberteile', 'Hosen', 'Jacken', 'Schuhe', 'Sportkleidung', 'Unterwäsche', 'Sonstiges'],
        accessory => const ['Uhren', 'Schmuck', 'Taschen', 'Gürtel', 'Brillen', 'Mützen & Schals', 'Sonstiges'],
        care => const ['Parfüm', 'Deo', 'Hautpflege', 'Haarpflege', 'Rasur', 'Zahnpflege', 'Sonstiges'],
        other => const ['Haushalt', 'Sonstiges'],
      };

  List<String> get suggestedLocations => switch (this) {
        food || drink => const ['Kühlschrank', 'Gefrierschrank', 'Vorratsschrank', 'Keller'],
        clothing => const ['Kleiderschrank', 'Kommode', 'Schuhschrank', 'Keller'],
        accessory => const ['Kommode', 'Kleiderschrank', 'Schmuckkästchen'],
        care => const ['Bad', 'Kommode', 'Kulturbeutel'],
        other => const [],
      };
}

/// Zustand eines Gegenstands (vor allem Kleidung).
enum ItemCondition {
  newItem('neu', 'Neu'),
  good('gut', 'Gut'),
  used('gebraucht', 'Gebraucht'),
  worn('abgenutzt', 'Abgenutzt'),
  broken('defekt', 'Defekt');

  const ItemCondition(this.dbValue, this.label);
  final String dbValue;
  final String label;

  static ItemCondition? fromDb(Object? v) => v == null ? null : values.where((c) => c.dbValue == v).firstOrNull;
}

/// Eintrag im Vorrat oder Kleiderschrank.
class InventoryItem {
  final int? id;
  final int userid;
  final InventoryKind kind;
  final String name;
  final String? category;
  final String? location;
  final double quantity;
  final String? unit;
  final String? brand;
  final String? barcode;
  final DateTime? purchaseDate;
  final DateTime? expiryDate;
  final DateTime? openedDate;
  final ItemCondition? condition;
  final String? imagePath;
  final String? size;
  final String? color;
  final String? season;

  /// Zuletzt benutzt bzw. getragen.
  final DateTime? lastUsedAt;
  final int wearCount;
  final double? price;
  final String? notes;

  /// Verknüpftes Lebensmittel (Nährwerte) für die Ernährung.
  final int? foodId;

  /// Kam über die Einkaufsliste in den Vorrat (dann gehört ein Kassenzettel dazu).
  final bool fromShopping;

  /// Buchung des zugehörigen Kassenzettels; `0` = bewusst ohne Bon erledigt.
  final int? receiptTxId;

  const InventoryItem({
    this.id,
    required this.userid,
    required this.kind,
    required this.name,
    this.category,
    this.location,
    this.quantity = 1,
    this.unit,
    this.brand,
    this.barcode,
    this.purchaseDate,
    this.expiryDate,
    this.openedDate,
    this.condition,
    this.imagePath,
    this.size,
    this.color,
    this.season,
    this.lastUsedAt,
    this.wearCount = 0,
    this.price,
    this.notes,
    this.foodId,
    this.fromShopping = false,
    this.receiptTxId,
  });

  InventoryItem copyWith({
    double? quantity,
    DateTime? lastUsedAt,
    int? wearCount,
    String? imagePath,
    bool clearImage = false,
    int? foodId,
  }) {
    return InventoryItem(
      id: id,
      userid: userid,
      kind: kind,
      name: name,
      category: category,
      location: location,
      quantity: quantity ?? this.quantity,
      unit: unit,
      brand: brand,
      barcode: barcode,
      purchaseDate: purchaseDate,
      expiryDate: expiryDate,
      openedDate: openedDate,
      condition: condition,
      imagePath: clearImage ? null : (imagePath ?? this.imagePath),
      size: size,
      color: color,
      season: season,
      lastUsedAt: lastUsedAt ?? this.lastUsedAt,
      wearCount: wearCount ?? this.wearCount,
      price: price,
      notes: notes,
      foodId: foodId ?? this.foodId,
      fromShopping: fromShopping,
      receiptTxId: receiptTxId,
    );
  }

  /// Tage bis zum Ablauf (0 = heute, negativ = abgelaufen), `null` ohne Ablaufdatum.
  int? daysUntilExpiry([DateTime? now]) {
    if (expiryDate == null) return null;
    return daysBetween(now ?? DateTime.now(), expiryDate!);
  }

  bool isExpired([DateTime? now]) => (daysUntilExpiry(now) ?? 1) < 0;

  /// Läuft innerhalb von [days] Tagen ab (heute eingeschlossen), ist aber noch nicht abgelaufen.
  bool expiresSoon({int days = 3, DateTime? now}) {
    final d = daysUntilExpiry(now);
    return d != null && d >= 0 && d <= days;
  }

  /// Alter seit dem Kauf in Tagen, `null` ohne Kaufdatum.
  int? ageInDays([DateTime? now]) => purchaseDate == null ? null : daysBetween(purchaseDate!, now ?? DateTime.now());

  static String? _d(DateTime? d) => d?.toIso8601String();
  static DateTime? _p(Object? v) => v == null ? null : DateTime.tryParse(v as String);

  Map<String, dynamic> toMap() => {
        'id': id,
        'userid': userid,
        'kind': kind.dbValue,
        'name': name,
        'category': category,
        'location': location,
        'quantity': quantity,
        'unit': unit,
        'brand': brand,
        'barcode': barcode,
        'purchaseDate': _d(purchaseDate),
        'expiryDate': _d(expiryDate),
        'openedDate': _d(openedDate),
        'condition': condition?.dbValue,
        'imagePath': imagePath,
        'size': size,
        'color': color,
        'season': season,
        'lastUsedAt': _d(lastUsedAt),
        'wearCount': wearCount,
        'price': price,
        'notes': notes,
        'foodId': foodId,
        // Nur setzen, nie überschreiben: Editoren kennen die Bon-Verknüpfung nicht
        if (fromShopping) 'fromShopping': 1,
        if (receiptTxId != null) 'receiptTxId': receiptTxId,
      };

  factory InventoryItem.fromMap(Map<String, dynamic> m) => InventoryItem(
        id: m['id'],
        userid: m['userid'],
        kind: InventoryKind.fromDb(m['kind']),
        name: m['name'] ?? '',
        category: m['category'],
        location: m['location'],
        quantity: (m['quantity'] as num?)?.toDouble() ?? 1,
        unit: m['unit'],
        brand: m['brand'],
        barcode: m['barcode'],
        purchaseDate: _p(m['purchaseDate']),
        expiryDate: _p(m['expiryDate']),
        openedDate: _p(m['openedDate']),
        condition: ItemCondition.fromDb(m['condition']),
        imagePath: m['imagePath'],
        size: m['size'],
        color: m['color'],
        season: m['season'],
        lastUsedAt: _p(m['lastUsedAt']),
        wearCount: (m['wearCount'] as int?) ?? 0,
        price: (m['price'] as num?)?.toDouble(),
        notes: m['notes'],
        foodId: m['foodId'] as int?,
        fromShopping: m['fromShopping'] == 1,
        receiptTxId: m['receiptTxId'] as int?,
      );
}

/// Schnellfilter für den Inventar-Screen.
enum InventoryStatus {
  all('Alle'),
  expiringSoon('Läuft bald ab'),
  expired('Abgelaufen'),
  notWornLately('Lange nicht getragen');

  const InventoryStatus(this.label);
  final String label;
}

enum InventorySort {
  expiry('Ablaufdatum'),
  age('Alter'),
  lastUsed('Zuletzt benutzt'),
  name('Name');

  const InventorySort(this.label);
  final String label;
}

/// Suche, Filter und Sortierung – reine Funktion, damit sie ohne UI testbar ist.
class InventoryQuery {
  final String search;

  /// Nur eine Art (z. B. Drogerie im Vorrat); `null` = alle.
  final InventoryKind? kind;
  final String? category;
  final String? location;
  final ItemCondition? condition;
  final InventoryStatus status;
  final InventorySort sort;

  /// Ab so vielen Tagen ohne Tragen gilt Kleidung als „lange nicht getragen“.
  static const notWornDays = 90;

  const InventoryQuery({
    this.search = '',
    this.kind,
    this.category,
    this.location,
    this.condition,
    this.status = InventoryStatus.all,
    this.sort = InventorySort.expiry,
  });

  bool matches(InventoryItem i, DateTime now) {
    final q = search.trim().toLowerCase();
    if (q.isNotEmpty) {
      final haystack = [i.name, i.brand, i.location, i.color, i.category, i.notes, i.size]
          .whereType<String>()
          .join(' ')
          .toLowerCase();
      if (!haystack.contains(q)) return false;
    }
    if (kind != null && i.kind != kind) return false;
    if (category != null && i.category != category) return false;
    if (location != null && i.location != location) return false;
    if (condition != null && i.condition != condition) return false;
    return switch (status) {
      InventoryStatus.all => true,
      InventoryStatus.expiringSoon => i.expiresSoon(now: now),
      InventoryStatus.expired => i.isExpired(now),
      InventoryStatus.notWornLately =>
        i.kind.isWearable && (i.lastUsedAt == null || daysBetween(i.lastUsedAt!, now) >= notWornDays),
    };
  }

  List<InventoryItem> apply(List<InventoryItem> items, {DateTime? now}) {
    final n = now ?? DateTime.now();
    final far = DateTime(9999);
    final result = items.where((i) => matches(i, n)).toList();
    int byName(InventoryItem a, InventoryItem b) => a.name.toLowerCase().compareTo(b.name.toLowerCase());
    result.sort(switch (sort) {
      InventorySort.expiry => (a, b) {
          final c = (a.expiryDate ?? far).compareTo(b.expiryDate ?? far);
          return c != 0 ? c : byName(a, b);
        },
      // Älteste zuerst; ohne Kaufdatum ans Ende
      InventorySort.age => (a, b) {
          final c = (a.purchaseDate ?? far).compareTo(b.purchaseDate ?? far);
          return c != 0 ? c : byName(a, b);
        },
      // Am längsten nicht benutzt zuerst; nie benutzt ganz vorne
      InventorySort.lastUsed => (a, b) {
          final c = (a.lastUsedAt ?? DateTime(0)).compareTo(b.lastUsedAt ?? DateTime(0));
          return c != 0 ? c : byName(a, b);
        },
      InventorySort.name => byName,
    });
    return result;
  }
}
