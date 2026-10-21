import 'package:frontend/features/inventory/models/inventory_item.dart';

/// Outfit aus Kleidungsstücken des Kleiderschranks.
class Outfit {
  final int? id;
  final int userid;
  final String name;
  final String? imagePath;
  final DateTime? lastWornAt;
  final int wearCount;
  final List<InventoryItem> items;

  const Outfit({
    this.id,
    required this.userid,
    required this.name,
    this.imagePath,
    this.lastWornAt,
    this.wearCount = 0,
    this.items = const [],
  });

  bool get neverWorn => wearCount == 0;

  Map<String, dynamic> toMap() => {
        'id': id,
        'userid': userid,
        'name': name,
        'imagePath': imagePath,
        'lastWornAt': lastWornAt?.toIso8601String(),
        'wearCount': wearCount,
      };

  factory Outfit.fromMap(Map<String, dynamic> m, {List<InventoryItem> items = const []}) => Outfit(
        id: m['id'],
        userid: m['userid'],
        name: m['name'] ?? '',
        imagePath: m['imagePath'],
        lastWornAt: m['lastWornAt'] == null ? null : DateTime.parse(m['lastWornAt']),
        wearCount: m['wearCount'] ?? 0,
        items: items,
      );
}

enum WishPriority {
  low(1, 'Irgendwann'),
  medium(2, 'Bald'),
  high(3, 'Dringend');

  const WishPriority(this.dbValue, this.label);
  final int dbValue;
  final String label;

  static WishPriority fromDb(Object? v) => values.firstWhere((p) => p.dbValue == v, orElse: () => medium);
}

enum WishStatus {
  open('open'),
  bought('bought');

  const WishStatus(this.dbValue);
  final String dbValue;

  static WishStatus fromDb(Object? v) => values.firstWhere((s) => s.dbValue == v, orElse: () => open);
}

/// Eintrag auf der Wunschliste.
class WishlistItem {
  final int? id;
  final int userid;
  final String name;
  final double? price;
  final String? url;
  final String? imagePath;
  final WishPriority priority;
  final WishStatus status;
  final int? boughtItemId;

  const WishlistItem({
    this.id,
    required this.userid,
    required this.name,
    this.price,
    this.url,
    this.imagePath,
    this.priority = WishPriority.medium,
    this.status = WishStatus.open,
    this.boughtItemId,
  });

  bool get isOpen => status == WishStatus.open;

  Map<String, dynamic> toMap() => {
        'id': id,
        'userid': userid,
        'name': name,
        'price': price,
        'url': url,
        'imagePath': imagePath,
        'priority': priority.dbValue,
        'status': status.dbValue,
        'boughtItemId': boughtItemId,
      };

  factory WishlistItem.fromMap(Map<String, dynamic> m) => WishlistItem(
        id: m['id'],
        userid: m['userid'],
        name: m['name'] ?? '',
        price: (m['price'] as num?)?.toDouble(),
        url: m['url'],
        imagePath: m['imagePath'],
        priority: WishPriority.fromDb(m['priority']),
        status: WishStatus.fromDb(m['status']),
        boughtItemId: m['boughtItemId'],
      );
}

/// Offene Wünsche im Verhältnis zum Monatsbudget der Kleidungs-Kategorie.
class WishlistBudget {
  final String category;
  final double openSum;

  /// 0 = kein Budget hinterlegt.
  final double monthlyBudget;
  final double spentThisMonth;

  const WishlistBudget({required this.category, required this.openSum, this.monthlyBudget = 0, this.spentThisMonth = 0});

  bool get hasBudget => monthlyBudget > 0;
  double get remaining => monthlyBudget - spentThisMonth;
}
