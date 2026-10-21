import 'package:frontend/core/database/database.dart';
import 'package:frontend/features/fitness/catalog/standard_foods.dart';
import 'package:frontend/features/fitness/models/nutrition.dart';
import 'package:frontend/features/inventory/models/inventory_item.dart';
import 'package:frontend/features/inventory/repositories/inventory_repository.dart';

/// Lebensmittel, Ernährungsprotokoll und Tagesziele.
class NutritionRepository {
  NutritionRepository({DatabaseService? db, InventoryRepository? inventory})
      : _db = db ?? DatabaseService.instance,
        _inventory = inventory ?? InventoryRepository(db: db);

  final DatabaseService _db;
  final InventoryRepository _inventory;

  static String _now() => syncStamp();

  // ─── Lebensmittel ─────────────────────────────────────────────────────

  Future<Food> saveFood(Food food) async {
    final db = await _db.database;
    if (food.id == null) {
      final id = await db.insert('foods', food.toMap()..remove('id'));
      return food.copyWith(id: id);
    }
    await db.update('foods', {...food.toMap()..remove('id'), 'last_changed': _now()}, where: 'id = ?', whereArgs: [food.id]);
    return food;
  }

  Future<void> deleteFood(int id) async {
    final db = await _db.database;
    await db.update('foods', {'is_deleted': 1, 'last_changed': _now()}, where: 'id = ?', whereArgs: [id]);
  }

  Future<Food?> getFood(int id) async {
    final db = await _db.database;
    final rows = await db.query('foods', where: 'id = ? AND is_deleted = 0', whereArgs: [id]);
    return rows.isEmpty ? null : Food.fromMap(rows.first);
  }

  Future<Food?> findByBarcode(int uid, String barcode) async {
    final db = await _db.database;
    final rows = await db.query('foods',
        where: 'userid = ? AND barcode = ? AND is_deleted = 0', whereArgs: [uid, barcode], limit: 1);
    return rows.isEmpty ? null : Food.fromMap(rows.first);
  }

  /// Eigene Lebensmittel, zuletzt genutzte zuerst; mit [search] nach Name/Marke gefiltert.
  /// Legt mitgelieferte Standardprodukte an, die es beim Nutzer noch nie gab. Gelöschte bleiben
  /// gelöscht; neu hinzugekommene Standardprodukte (z. B. Getränke) werden nachgetragen.
  Future<void> ensureStandardFoods(int uid) => _seeding[uid] ??= _seedStandardFoods(uid).catchError((Object e) {
        _seeding.remove(uid); // nach einem Fehler beim nächsten Aufruf erneut versuchen
        throw e;
      });

  /// Laufende bzw. erledigte Anlage pro Nutzer – verhindert doppelte Einträge bei parallelen Aufrufen.
  final Map<int, Future<void>> _seeding = {};

  Future<void> _seedStandardFoods(int uid) async {
    final db = await _db.database;
    await db.transaction((txn) async {
      final existing = (await txn.query('foods', columns: ['name'], where: 'userid = ? AND brand = ?', whereArgs: [uid, standardFoodBrand]))
          .map((r) => r['name'] as String)
          .toSet();
      for (final f in standardFoods.where((f) => !existing.contains(f.name))) {
        await txn.insert('foods', f.toFood(uid).toMap()..remove('id'));
      }
      // Packungsgrößen bei bereits angelegten Standardprodukten nachtragen (ab Schema 24)
      for (final f in standardFoods.where((f) => existing.contains(f.name) && standardPackSizes.containsKey(f.name))) {
        await txn.update('foods', {'packSizes': f.toFood(uid).toMap()['packSizes']},
            where: 'userid = ? AND brand = ? AND name = ? AND packSizes IS NULL',
            whereArgs: [uid, standardFoodBrand, f.name]);
      }
    });
  }

  /// Verknüpft einen (offline oder bei Open Food Facts unbekannten) Barcode mit einem vorhandenen
  /// Lebensmittel: Es entsteht ein eigenes Lebensmittel mit denselben Nährwerten und dem Barcode,
  /// damit der nächste Scan sofort – auch ohne Internet – klappt.
  Future<Food> linkBarcode(int uid, String barcode, Food source) => saveFood(Food(
        userid: uid,
        name: source.name,
        brand: source.brand == standardFoodBrand ? null : source.brand,
        barcode: barcode,
        per100: source.per100,
        servingGrams: source.servingGrams,
      ));

  Future<List<Food>> searchFoods(int uid, {String search = ''}) async {
    final db = await _db.database;
    final pattern = '%${search.trim().toLowerCase()}%';
    final rows = await db.rawQuery('''
      SELECT f.*, MAX(e.id) AS lastUse FROM foods f
      LEFT JOIN meal_entries e ON e.foodId = f.id AND e.is_deleted = 0
      WHERE f.userid = ? AND f.is_deleted = 0 AND (LOWER(f.name) LIKE ? OR LOWER(COALESCE(f.brand, '')) LIKE ?)
      GROUP BY f.id
      ORDER BY lastUse IS NULL, lastUse DESC, f.name COLLATE NOCASE
    ''', [uid, pattern, pattern]);
    return rows.map(Food.fromMap).toList();
  }

  // ─── Protokoll ────────────────────────────────────────────────────────

  Future<MealEntry> addEntry({
    required int uid,
    required Food food,
    required double grams,
    required Meal meal,
    required DateTime date,
    double? portions,
  }) async {
    final entry = MealEntry(
      userid: uid,
      date: date,
      meal: meal,
      foodId: food.id,
      name: food.name,
      grams: grams,
      macros: food.forGrams(grams),
      portions: portions,
    );
    final db = await _db.database;
    final id = await db.insert('meal_entries', entry.toMap()..remove('id'));
    return MealEntry.fromMap({...entry.toMap(), 'id': id});
  }

  /// Aus dem Vorrat essen: trägt ins Protokoll ein und bucht im Vorrat ab
  /// (bei Einheit g/ml die Grammzahl, sonst ein Stück).
  Future<MealEntry> eatFromPantry({
    required int uid,
    required InventoryItem item,
    required Food food,
    required double grams,
    required Meal meal,
    required DateTime date,
  }) async {
    final entry = await addEntry(uid: uid, food: food, grams: grams, meal: meal, date: date);
    final unit = item.unit?.toLowerCase().trim();
    await _inventory.consume(item, amount: unit == 'g' || unit == 'ml' ? grams : 1);
    return entry;
  }

  /// Eigenes Gericht merken: Nährwerte je Portion, optional mit Gramm je Portion (sonst nominell 100 g).
  Future<Food> saveDish({required int uid, required String name, required Macros perPortion, double? gramsPerPortion}) {
    final grams = (gramsPerPortion ?? 0) > 0 ? gramsPerPortion! : 100.0;
    return saveFood(Food(userid: uid, name: name.trim(), per100: perPortion.scaled(100 / grams), servingGrams: grams, isDish: true));
  }

  /// Portionen eines Rezepts (oder eines anderen Gerichts ohne gespeichertes Lebensmittel) eintragen.
  Future<MealEntry> addDishEntry({
    required int uid,
    required String name,
    required Macros perPortion,
    required double gramsPerPortion,
    required double portions,
    required Meal meal,
    required DateTime date,
  }) async {
    final entry = MealEntry(
      userid: uid,
      date: date,
      meal: meal,
      name: name,
      grams: gramsPerPortion * portions,
      macros: perPortion.scaled(portions),
      portions: portions,
    );
    final db = await _db.database;
    final id = await db.insert('meal_entries', entry.toMap()..remove('id'));
    return MealEntry.fromMap({...entry.toMap(), 'id': id});
  }

  /// Wasser (oder ein anderes Getränk ohne Nährwerte) trinken: Eintrag unter „Getränke“.
  Future<MealEntry> addWater({required int uid, required double ml, required DateTime date, String name = 'Wasser'}) async {
    final entry = MealEntry(userid: uid, date: date, meal: Meal.drinks, name: name, grams: ml, macros: Macros.zero);
    final db = await _db.database;
    final id = await db.insert('meal_entries', entry.toMap()..remove('id'));
    return MealEntry.fromMap({...entry.toMap(), 'id': id});
  }

  /// Menge oder Mahlzeit eines Eintrags ändern; Nährwerte werden anteilig umgerechnet.
  /// Bei Gerichten zählen die [portions] (die Gramm werden mitgeführt).
  Future<MealEntry> updateEntry(MealEntry entry, {required double grams, required Meal meal, double? portions}) async {
    final old = entry.portions;
    final factor = portions != null && old != null && old > 0
        ? portions / old
        : entry.grams <= 0
            ? 1.0
            : grams / entry.grams;
    final updated = MealEntry(
      id: entry.id,
      userid: entry.userid,
      date: entry.date,
      meal: meal,
      foodId: entry.foodId,
      name: entry.name,
      grams: grams,
      macros: entry.macros.scaled(factor),
      portions: portions ?? entry.portions,
    );
    final db = await _db.database;
    await db.update('meal_entries', {...updated.toMap()..remove('id'), 'last_changed': _now()},
        where: 'id = ?', whereArgs: [entry.id]);
    return updated;
  }

  Future<void> restoreEntry(int id) => _db.restoreRow('meal_entries', id);

  Future<void> deleteEntry(int id) async {
    final db = await _db.database;
    await db.update('meal_entries', {'is_deleted': 1, 'last_changed': _now()}, where: 'id = ?', whereArgs: [id]);
  }

  Future<NutritionDay> getDay(int uid, DateTime date) async {
    final db = await _db.database;
    final rows = await db.query('meal_entries',
        where: 'userid = ? AND date = ? AND is_deleted = 0', whereArgs: [uid, MealEntry.dayKey(date)], orderBy: 'id');
    return NutritionDay(DateTime(date.year, date.month, date.day), rows.map(MealEntry.fromMap).toList(), await getGoals(uid));
  }

  // ─── Ziele ────────────────────────────────────────────────────────────

  Future<NutritionGoals> getGoals(int uid) async {
    final db = await _db.database;
    final rows = await db.query('nutrition_goals', where: 'userid = ? AND is_deleted = 0', whereArgs: [uid], limit: 1);
    if (rows.isEmpty) return NutritionGoals.defaults;
    final r = rows.first;
    return NutritionGoals(
      Macros(
        kcal: (r['kcal'] as num).toDouble(),
        protein: (r['protein'] as num).toDouble(),
        carbs: (r['carbs'] as num).toDouble(),
        fat: (r['fat'] as num).toDouble(),
      ),
      waterMl: (r['waterMl'] as num?)?.toDouble() ?? NutritionGoals.defaultWaterMl,
    );
  }

  Future<void> setGoals(int uid, Macros target, {double? waterMl}) async {
    final db = await _db.database;
    final values = {
      'kcal': target.kcal,
      'protein': target.protein,
      'carbs': target.carbs,
      'fat': target.fat,
      if (waterMl != null) 'waterMl': waterMl,
      'last_changed': _now(),
    };
    final updated = await db.update('nutrition_goals', values, where: 'userid = ?', whereArgs: [uid]);
    if (updated == 0) await db.insert('nutrition_goals', {...values, 'userid': uid});
  }
}
