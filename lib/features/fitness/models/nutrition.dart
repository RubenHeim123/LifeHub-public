/// Mahlzeiten eines Tages.
enum Meal {
  breakfast('breakfast', 'Frühstück'),
  lunch('lunch', 'Mittagessen'),
  dinner('dinner', 'Abendessen'),
  snack('snack', 'Snacks'),
  drinks('drinks', 'Getränke');

  /// Mengen werden bei Getränken in ml angegeben.
  String get unit => this == drinks ? 'ml' : 'g';

  const Meal(this.dbValue, this.label);
  final String dbValue;
  final String label;

  static Meal fromDb(Object? v) => values.firstWhere((m) => m.dbValue == v, orElse: () => snack);
}

/// Nährwerte (kcal in kcal, Rest in Gramm).
class Macros {
  final double kcal, protein, carbs, fat;
  const Macros({this.kcal = 0, this.protein = 0, this.carbs = 0, this.fat = 0});

  static const zero = Macros();

  Macros operator +(Macros o) =>
      Macros(kcal: kcal + o.kcal, protein: protein + o.protein, carbs: carbs + o.carbs, fat: fat + o.fat);

  Macros scaled(double factor) =>
      Macros(kcal: kcal * factor, protein: protein * factor, carbs: carbs * factor, fat: fat * factor);
}

/// Lebensmittel mit Nährwerten pro 100 g (bzw. 100 ml).
class Food {
  final int? id;
  final int userid;
  final String name;
  final String? brand;
  final String? barcode;
  final Macros per100;

  /// Typische Portion in Gramm (Vorschlag beim Eintragen).
  final double? servingGrams;

  /// Packungsgrößen, in denen es das Produkt zu kaufen gibt (in g bzw. ml), z. B. [400, 600].
  final List<double> packSizes;

  /// Ein ganzes Gericht („Pizza vom Italiener“): wird in Portionen zu je [servingGrams] eingetragen.
  final bool isDish;

  const Food({
    this.id,
    required this.userid,
    required this.name,
    this.brand,
    this.barcode,
    this.per100 = Macros.zero,
    this.servingGrams,
    this.packSizes = const [],
    this.isDish = false,
  });

  Macros forGrams(double grams) => per100.scaled(grams / 100);

  /// Gramm einer Portion (bei Gerichten ohne Angabe nominell 100).
  double get portionGrams => servingGrams ?? 100;

  /// Nährwerte einer Portion.
  Macros get portionMacros => forGrams(portionGrams);

  Food copyWith({int? id, int? userid, List<double>? packSizes}) => Food(
        id: id ?? this.id,
        userid: userid ?? this.userid,
        name: name,
        brand: brand,
        barcode: barcode,
        per100: per100,
        servingGrams: servingGrams,
        packSizes: packSizes ?? this.packSizes,
        isDish: isDish,
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'userid': userid,
        'name': name,
        'brand': brand,
        'barcode': barcode,
        'kcal': per100.kcal,
        'protein': per100.protein,
        'carbs': per100.carbs,
        'fat': per100.fat,
        'servingGrams': servingGrams,
        'packSizes': packSizes.isEmpty ? null : packSizes.map(_num).join(';'),
        'isDish': isDish ? 1 : 0,
      };

  static String _num(double v) => v == v.roundToDouble() ? v.toInt().toString() : v.toString();

  /// „400, 600“ → [400, 600]
  /// Ein Komma direkt zwischen Ziffern mit 1–2 Nachkommastellen ist ein Dezimalkomma („1,5, 500“ → [1.5, 500]),
  /// sonst trennt es wie `;`, `/` und Leerzeichen („400,600“ → [400, 600]).
  static List<double> parsePackSizes(Object? v) {
    final text = '${v ?? ''}'.replaceAllMapped(RegExp(r'(\d),(\d{1,2})(?!\d)'), (m) => '${m[1]}.${m[2]}');
    return [
      for (final part in text.split(RegExp(r'[,;/\s]+')))
        if (double.tryParse(part) case final d? when d > 0) d,
    ]..sort();
  }

  factory Food.fromMap(Map<String, dynamic> m) => Food(
        id: m['id'],
        userid: m['userid'],
        name: m['name'] ?? '',
        brand: m['brand'],
        barcode: m['barcode'],
        per100: Macros(
          kcal: (m['kcal'] as num?)?.toDouble() ?? 0,
          protein: (m['protein'] as num?)?.toDouble() ?? 0,
          carbs: (m['carbs'] as num?)?.toDouble() ?? 0,
          fat: (m['fat'] as num?)?.toDouble() ?? 0,
        ),
        servingGrams: (m['servingGrams'] as num?)?.toDouble(),
        packSizes: parsePackSizes(m['packSizes']),
        isDish: m['isDish'] == 1,
      );
}

/// Eingetragene Portion. Name und Nährwerte werden beim Eintragen festgeschrieben,
/// damit spätere Änderungen am Lebensmittel das Protokoll nicht verfälschen.
class MealEntry {
  final int? id;
  final int userid;
  final DateTime date;
  final Meal meal;
  final int? foodId;
  final String name;
  final double grams;
  final Macros macros;

  /// Bei Gerichten und Rezepten: Anzahl Portionen (sonst `null`, dann zählen die Gramm).
  final double? portions;

  const MealEntry({
    this.id,
    required this.userid,
    required this.date,
    required this.meal,
    this.foodId,
    required this.name,
    required this.grams,
    required this.macros,
    this.portions,
  });

  static String dayKey(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Map<String, dynamic> toMap() => {
        'id': id,
        'userid': userid,
        'date': dayKey(date),
        'meal': meal.dbValue,
        'foodId': foodId,
        'name': name,
        'grams': grams,
        'kcal': macros.kcal,
        'protein': macros.protein,
        'carbs': macros.carbs,
        'fat': macros.fat,
        'portions': portions,
      };

  factory MealEntry.fromMap(Map<String, dynamic> m) => MealEntry(
        id: m['id'],
        userid: m['userid'],
        date: DateTime.parse(m['date']),
        meal: Meal.fromDb(m['meal']),
        foodId: m['foodId'] as int?,
        name: m['name'] ?? '',
        grams: (m['grams'] as num?)?.toDouble() ?? 0,
        macros: Macros(
          kcal: (m['kcal'] as num?)?.toDouble() ?? 0,
          protein: (m['protein'] as num?)?.toDouble() ?? 0,
          carbs: (m['carbs'] as num?)?.toDouble() ?? 0,
          fat: (m['fat'] as num?)?.toDouble() ?? 0,
        ),
        portions: (m['portions'] as num?)?.toDouble(),
      );
}

/// Tagesziele. Standardwerte, bis der Nutzer eigene setzt.
class NutritionGoals {
  final Macros target;

  /// Trinkziel pro Tag in ml.
  final double waterMl;
  const NutritionGoals(this.target, {this.waterMl = defaultWaterMl});

  static const defaultWaterMl = 2500.0;
  static const defaults = NutritionGoals(Macros(kcal: 2400, protein: 150, carbs: 280, fat: 75));
}

/// Ein Tag im Ernährungsprotokoll.
class NutritionDay {
  final DateTime date;
  final List<MealEntry> entries;
  final NutritionGoals goals;
  const NutritionDay(this.date, this.entries, this.goals);

  Macros get total => entries.fold(Macros.zero, (sum, e) => sum + e.macros);
  Macros totalFor(Meal meal) => entries.where((e) => e.meal == meal).fold(Macros.zero, (s, e) => s + e.macros);
  List<MealEntry> entriesFor(Meal meal) => entries.where((e) => e.meal == meal).toList();

  /// Getrunkene Menge in ml (alle Einträge unter „Getränke“, inkl. Wasser).
  double get drankMl => entriesFor(Meal.drinks).fold(0.0, (s, e) => s + e.grams);
}
