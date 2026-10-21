import 'dart:convert';

import 'package:frontend/features/fitness/models/nutrition.dart';

/// Mahlzeiten, die im Essensplan vorkommen – in der Reihenfolge des Tages.
const plannedMeals = [Meal.breakfast, Meal.lunch, Meal.snack, Meal.dinner];

/// Übliche Uhrzeit einer Mahlzeit (Minuten seit Mitternacht), solange keine eigene gesetzt ist.
int defaultMealMinutes(Meal meal) => switch (meal) {
      Meal.breakfast => 7 * 60 + 30,
      Meal.lunch => 12 * 60 + 30,
      Meal.snack => 15 * 60 + 30,
      Meal.dinner => 18 * 60 + 30,
      Meal.drinks => 12 * 60,
    };

String formatMinutes(int minutes) =>
    '${(minutes ~/ 60).toString().padLeft(2, '0')}:${(minutes % 60).toString().padLeft(2, '0')}';

/// Zutat eines Rezepts; [amount] bezieht sich auf die Grundportionen des Rezepts.
class Ingredient {
  final String name;
  final double? amount;

  /// z. B. „g“, „ml“, „EL“, „TL“, „Dose“; `null` = Stück.
  final String? unit;
  const Ingredient(this.name, [this.amount, this.unit]);

  /// Menge für [factor]-fache Portionen, lesbar gerundet („150 g“, „1,5 Dosen“, „2“).
  String amountFor(double factor) {
    if (amount == null) return '';
    final value = amount! * factor;
    final rounded = switch (unit) {
      'g' || 'ml' when value >= 50 => (value / 5).round() * 5.0,
      _ => (value * 4).round() / 4, // Viertel bei EL, TL, Stück
    };
    final text = rounded == rounded.roundToDouble()
        ? rounded.toStringAsFixed(0)
        : rounded.toStringAsFixed(2).replaceAll(RegExp(r'0+$'), '').replaceAll('.', ',');
    if (unit == null) return text;
    return '$text ${rounded > 1 ? (_plural[unit] ?? unit) : unit}';
  }

  static const _plural = {'Dose': 'Dosen', 'Scheibe': 'Scheiben', 'Stange': 'Stangen', 'Prise': 'Prisen', 'Zehe': 'Zehen'};

  Map<String, dynamic> toJson() => {'name': name, 'amount': amount, 'unit': unit};

  factory Ingredient.fromJson(Map<String, dynamic> m) =>
      Ingredient(m['name'] ?? '', (m['amount'] as num?)?.toDouble(), m['unit']);

  /// Eine Zeile wie „200 g Haferflocken“, „2 EL Erdnussmus“ oder „Salz“.
  factory Ingredient.parse(String line) {
    final m = RegExp(r'^\s*(\d+(?:[.,]\d+)?)\s*(g|kg|ml|l|EL|TL|Dosen?|Bund|Prisen?|Pck\.?|Scheiben?|Stangen?|Blätter|Zehen?|Stück|Stk\.?)?\s+(.+)$',
            caseSensitive: false)
        .firstMatch(line);
    if (m == null) return Ingredient(line.trim());
    var unit = m.group(2);
    if (unit != null) {
      // Einheiten im Singular speichern, damit gleiche Zutaten zusammengefasst werden
      unit = _plural.entries.firstWhere((e) => e.value.toLowerCase() == unit!.toLowerCase(), orElse: () => MapEntry(unit!, unit)).key;
      if (unit.toLowerCase().startsWith('stk') || unit.toLowerCase() == 'stück') unit = null;
    }
    return Ingredient(m.group(3)!.trim(), double.parse(m.group(1)!.replaceAll(',', '.')), unit);
  }

  @override
  String toString() => amount == null ? name : '${amountFor(1)} $name';
}

/// Gericht mit Zutaten, Zubereitung und Nährwerten pro Portion. Entweder aus dem
/// mitgelieferten Katalog ([key]) oder selbst angelegt ([id]).
class Recipe {
  final int? id;
  final String? key;
  final int? userid;
  final String name;

  /// Kurzbeschreibung für Listen.
  final String summary;

  /// Mahlzeiten, zu denen das Gericht passt.
  final Set<Meal> meals;
  final int servings;
  final int minutes;
  final List<Ingredient> ingredients;
  final List<String> steps;
  final Macros perServing;

  /// Gewicht einer Portion in Gramm (für das Ernährungsprotokoll).
  final double gramsPerServing;
  final List<String> tags;

  const Recipe({
    this.id,
    this.key,
    this.userid,
    required this.name,
    this.summary = '',
    required this.meals,
    this.servings = 2,
    this.minutes = 20,
    this.ingredients = const [],
    this.steps = const [],
    this.perServing = Macros.zero,
    this.gramsPerServing = 350,
    this.tags = const [],
  });

  bool get isOwn => id != null;

  Map<String, dynamic> toMap() => {
        'id': id,
        'userid': userid,
        'name': name,
        'summary': summary,
        'meals': meals.map((m) => m.dbValue).join(','),
        'servings': servings,
        'minutes': minutes,
        'ingredients': jsonEncode([for (final i in ingredients) i.toJson()]),
        'steps': jsonEncode(steps),
        'kcal': perServing.kcal,
        'protein': perServing.protein,
        'carbs': perServing.carbs,
        'fat': perServing.fat,
        'gramsPerServing': gramsPerServing,
      };

  factory Recipe.fromMap(Map<String, dynamic> m) => Recipe(
        id: m['id'],
        userid: m['userid'],
        name: m['name'] ?? '',
        summary: m['summary'] ?? '',
        meals: {
          for (final v in (m['meals'] as String? ?? '').split(',').where((v) => v.isNotEmpty)) Meal.fromDb(v),
        },
        servings: m['servings'] ?? 1,
        minutes: m['minutes'] ?? 0,
        ingredients: [
          for (final i in jsonDecode(m['ingredients'] ?? '[]') as List) Ingredient.fromJson(Map<String, dynamic>.from(i)),
        ],
        steps: [for (final s in jsonDecode(m['steps'] ?? '[]') as List) s.toString()],
        perServing: Macros(
          kcal: (m['kcal'] as num?)?.toDouble() ?? 0,
          protein: (m['protein'] as num?)?.toDouble() ?? 0,
          carbs: (m['carbs'] as num?)?.toDouble() ?? 0,
          fat: (m['fat'] as num?)?.toDouble() ?? 0,
        ),
        gramsPerServing: (m['gramsPerServing'] as num?)?.toDouble() ?? 350,
      );
}

/// Ein Gericht im Essensplan: an einem Tag zu einer Mahlzeit (und Uhrzeit).
class PlannedMeal {
  final int? id;
  final int userid;
  final DateTime date;
  final Meal meal;

  /// Eigene Uhrzeit in Minuten seit Mitternacht; sonst die übliche der Mahlzeit.
  final int? time;
  final String? recipeKey;
  final int? recipeId;

  /// Name zum Zeitpunkt des Einplanens (bleibt lesbar, falls das Rezept gelöscht wird).
  final String name;
  final double servings;
  final String? note;

  /// Eintrag im Ernährungsprotokoll, sobald das Gericht als gegessen markiert ist.
  final int? mealEntryId;

  /// Koch-Block, zu dem diese Portion gehört (ein Rezept, einmal gekocht, auf Tage verteilt).
  final int? batchId;

  /// Statt eines Rezepts ein einzelnes Lebensmittel (z. B. „Haferflocken, 60 g“).
  final int? foodId;
  final double? grams;

  /// Vorratsartikel, aus dem das Lebensmittel genommen wird (beim „Gegessen“ abgebucht).
  final int? itemId;

  const PlannedMeal({
    this.id,
    required this.userid,
    required this.date,
    required this.meal,
    this.time,
    this.recipeKey,
    this.recipeId,
    required this.name,
    this.servings = 1,
    this.note,
    this.mealEntryId,
    this.batchId,
    this.foodId,
    this.grams,
    this.itemId,
  });

  bool get eaten => mealEntryId != null;

  /// Einzelnes Lebensmittel statt Rezept.
  bool get isFood => foodId != null;

  int get minutes => time ?? defaultMealMinutes(meal);

  DateTime get at => DateTime(date.year, date.month, date.day).add(Duration(minutes: minutes));

  PlannedMeal copyWith({
    DateTime? date,
    Meal? meal,
    int? time,
    bool clearTime = false,
    double? servings,
    String? note,
    int? mealEntryId,
    bool clearMealEntry = false,
    double? grams,
  }) =>
      PlannedMeal(
        id: id,
        userid: userid,
        date: date ?? this.date,
        meal: meal ?? this.meal,
        time: clearTime ? null : (time ?? this.time),
        recipeKey: recipeKey,
        recipeId: recipeId,
        name: name,
        servings: servings ?? this.servings,
        note: note ?? this.note,
        mealEntryId: clearMealEntry ? null : (mealEntryId ?? this.mealEntryId),
        batchId: batchId,
        foodId: foodId,
        grams: grams ?? this.grams,
        itemId: itemId,
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'userid': userid,
        'date': MealEntry.dayKey(date),
        'meal': meal.dbValue,
        'time': time,
        'recipeKey': recipeKey,
        'recipeId': recipeId,
        'name': name,
        'servings': servings,
        'note': note,
        'mealEntryId': mealEntryId,
        'batchId': batchId,
        'foodId': foodId,
        'grams': grams,
        'itemId': itemId,
      };

  factory PlannedMeal.fromMap(Map<String, dynamic> m) => PlannedMeal(
        id: m['id'],
        userid: m['userid'],
        date: DateTime.parse(m['date']),
        meal: Meal.fromDb(m['meal']),
        time: m['time'] as int?,
        recipeKey: m['recipeKey'],
        recipeId: m['recipeId'] as int?,
        name: m['name'] ?? '',
        servings: (m['servings'] as num?)?.toDouble() ?? 1,
        note: m['note'],
        mealEntryId: m['mealEntryId'] as int?,
        batchId: m['batchId'] as int?,
        foodId: m['foodId'] as int?,
        grams: (m['grams'] as num?)?.toDouble(),
        itemId: m['itemId'] as int?,
      );
}

/// „1 Portion“, „2 Portionen“, „1,5 Portionen“.
String portionsLabel(double servings) {
  final n = servings == servings.roundToDouble() ? servings.toStringAsFixed(0) : servings.toString().replaceAll('.', ',');
  return servings == 1 ? '1 Portion' : '$n Portionen';
}

/// Ein Rezept, einmal gekocht und auf Mahlzeiten verteilt (z. B. 9 Portionen Dal auf Montag bis
/// Mittwoch). [factor] skaliert das Rezept (×1 = wie im Rezept, ×3 = dreifache Menge). Nicht alle
/// Portionen müssen verteilt sein – der Essensplan weist auf die übrigen hin.
class MealBatch {
  final int? id;
  final int userid;
  final String? recipeKey;
  final int? recipeId;
  final String name;
  final double factor;

  /// An diesem Tag wird gekocht.
  final DateTime cookDate;

  /// Gesetzt, sobald „Gekocht“ eingetragen wurde.
  final DateTime? cookedAt;

  /// Uhrzeit und Dauer des Koch-Termins im Kalender (z. B. 17:00, 60 Minuten).
  final int? cookHour;
  final int? cookMinute;
  final int durationMin;

  /// Termin „Kochen: …“ im Kalender.
  final int? appointmentId;

  /// Zutaten wurden beim Planen geprüft (Vorrat reserviert, Rest auf der Einkaufsliste). Beim
  /// Ändern des Blocks bleibt dann die bisherige Vorrats-Auswahl vorbelegt.
  final bool ingredientsPlanned;

  /// Zutaten-Schritt: Vorrat reservieren bzw. Fehlendes auf die Einkaufsliste setzen (beides abschaltbar).
  final bool usePantry;
  final bool shop;

  const MealBatch({
    this.id,
    required this.userid,
    this.recipeKey,
    this.recipeId,
    required this.name,
    this.factor = 1,
    required this.cookDate,
    this.cookedAt,
    this.cookHour,
    this.cookMinute,
    this.durationMin = 60,
    this.appointmentId,
    this.ingredientsPlanned = false,
    this.usePantry = true,
    this.shop = true,
  });

  bool get cooked => cookedAt != null;

  /// Beginn des Kochens (Kochtag + Uhrzeit), `null` ohne Uhrzeit.
  DateTime? get cookStart => cookHour == null ? null : DateTime(cookDate.year, cookDate.month, cookDate.day, cookHour!, cookMinute ?? 0);

  String? get cookTimeLabel => cookHour == null ? null : '${cookHour.toString().padLeft(2, '0')}:${(cookMinute ?? 0).toString().padLeft(2, '0')}';

  /// Portionen insgesamt (Rezeptportionen × Faktor).
  double servingsOf(Recipe recipe) => recipe.servings * factor;

  Map<String, dynamic> toMap() => {
        'id': id,
        'userid': userid,
        'recipeKey': recipeKey,
        'recipeId': recipeId,
        'name': name,
        'factor': factor,
        'cookDate': MealEntry.dayKey(cookDate),
        'cookedAt': cookedAt == null ? null : MealEntry.dayKey(cookedAt!),
        'cookTime': cookTimeLabel,
        'durationMin': durationMin,
        'appointmentId': appointmentId,
        'ingredientsPlanned': ingredientsPlanned ? 1 : 0,
        'usePantry': usePantry ? 1 : 0,
        'shop': shop ? 1 : 0,
      };

  factory MealBatch.fromMap(Map<String, dynamic> m) => MealBatch(
        id: m['id'],
        userid: m['userid'],
        recipeKey: m['recipeKey'],
        recipeId: m['recipeId'] as int?,
        name: m['name'] ?? '',
        factor: (m['factor'] as num?)?.toDouble() ?? 1,
        cookDate: DateTime.parse(m['cookDate']),
        cookedAt: m['cookedAt'] == null ? null : DateTime.parse(m['cookedAt']),
        cookHour: _timePart(m['cookTime'], 0),
        cookMinute: _timePart(m['cookTime'], 1),
        durationMin: (m['durationMin'] as int?) ?? 60,
        appointmentId: m['appointmentId'] as int?,
        ingredientsPlanned: (m['ingredientsPlanned'] as int? ?? 0) == 1,
        usePantry: (m['usePantry'] as int? ?? 1) == 1,
        shop: (m['shop'] as int? ?? 1) == 1,
      );

  static int? _timePart(Object? time, int i) {
    final parts = (time as String?)?.split(':');
    return parts == null || parts.length != 2 ? null : int.tryParse(parts[i]);
  }
}

/// Für einen Koch-Block aus dem Vorrat zurückgelegte Menge einer Zutat. [amount] in der Einheit
/// des Vorratsartikels; `null`, wenn sich die Mengen nicht vergleichen lassen (1 TL aus einer Packung).
class PantryReservation {
  final int? id;
  final int userid;
  final int batchId;
  final int itemId;
  final String ingredient;
  final double? amount;
  final String? unit;

  const PantryReservation({
    this.id,
    required this.userid,
    required this.batchId,
    required this.itemId,
    required this.ingredient,
    this.amount,
    this.unit,
  });

  Map<String, dynamic> toMap() => {
        if (id != null) 'id': id,
        'userid': userid,
        'batchId': batchId,
        'itemId': itemId,
        'ingredient': ingredient,
        'amount': amount,
        'unit': unit,
      };

  factory PantryReservation.fromMap(Map<String, dynamic> m) => PantryReservation(
        id: m['id'] as int?,
        userid: m['userid'] as int,
        batchId: m['batchId'] as int,
        itemId: m['itemId'] as int,
        ingredient: m['ingredient'] as String? ?? '',
        amount: (m['amount'] as num?)?.toDouble(),
        unit: m['unit'] as String?,
      );
}

/// Eine Portion in der Verteilung eines Koch-Blocks: Tag, Mahlzeit, Anzahl.
class PortionSlot {
  final DateTime date;
  final Meal meal;
  final double servings;
  const PortionSlot(this.date, this.meal, this.servings);

  @override
  bool operator ==(Object other) => other is PortionSlot && other.date == date && other.meal == meal && other.servings == servings;

  @override
  int get hashCode => Object.hash(date, meal, servings);

  @override
  String toString() => '${MealEntry.dayKey(date)} ${meal.dbValue} ×$servings';
}

/// Was beim Kochen tatsächlich verwendet wurde: Soll laut Rezept vs. genommen aus dem Vorrat
/// (z. B. „200 g Paprika“ → 2 Stück Paprika).
class CookUsage {
  final String ingredient;

  /// Menge laut Rezept, z. B. „200 g“.
  final String? planned;
  final int? itemId;
  final String? itemName;
  final double? amount;
  final String? unit;

  const CookUsage({required this.ingredient, this.planned, this.itemId, this.itemName, this.amount, this.unit});

  bool get fromPantry => itemId != null && (amount ?? 0) > 0;

  Map<String, dynamic> toJson() => {
        'ingredient': ingredient,
        'planned': planned,
        'itemId': itemId,
        'itemName': itemName,
        'amount': amount,
        'unit': unit,
      };

  factory CookUsage.fromJson(Map<String, dynamic> m) => CookUsage(
        ingredient: m['ingredient'] ?? '',
        planned: m['planned'],
        itemId: m['itemId'] as int?,
        itemName: m['itemName'],
        amount: (m['amount'] as num?)?.toDouble(),
        unit: m['unit'],
      );
}

/// Protokoll „an diesem Tag gekocht“: Rezept und was aus dem Vorrat genommen wurde.
class CookLog {
  final int? id;
  final int userid;
  final int? batchId;
  final String? recipeKey;
  final int? recipeId;
  final String name;
  final DateTime date;
  final List<CookUsage> usages;

  const CookLog({
    this.id,
    required this.userid,
    this.batchId,
    this.recipeKey,
    this.recipeId,
    required this.name,
    required this.date,
    this.usages = const [],
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'userid': userid,
        'batchId': batchId,
        'recipeKey': recipeKey,
        'recipeId': recipeId,
        'name': name,
        'date': MealEntry.dayKey(date),
        'usages': jsonEncode([for (final u in usages) u.toJson()]),
      };

  factory CookLog.fromMap(Map<String, dynamic> m) => CookLog(
        id: m['id'],
        userid: m['userid'],
        batchId: m['batchId'] as int?,
        recipeKey: m['recipeKey'],
        recipeId: m['recipeId'] as int?,
        name: m['name'] ?? '',
        date: DateTime.parse(m['date']),
        usages: [for (final u in jsonDecode(m['usages'] ?? '[]') as List) CookUsage.fromJson(Map<String, dynamic>.from(u))],
      );
}
