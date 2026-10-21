import 'package:sqflite/sqflite.dart';

import 'package:frontend/core/database/database.dart';
import 'package:frontend/features/calendar/models/appointment.dart';
import 'package:frontend/features/calendar/repositories/appointment_repository.dart';
import 'package:frontend/features/inventory/models/inventory_item.dart';
import 'package:frontend/features/fitness/models/nutrition.dart';
import 'package:frontend/features/inventory/repositories/inventory_repository.dart';
import 'package:frontend/features/lists/models/lists.dart';
import 'package:frontend/features/lists/repositories/lists_repository.dart';
import 'package:frontend/features/meals/catalog/recipe_catalog.dart';
import 'package:frontend/features/meals/models/meal_plan.dart';
import 'package:frontend/features/meals/services/pantry_check.dart';

/// Essensplan: Gerichte für Tage und Mahlzeiten einplanen, eigene Rezepte, Übernahme ins
/// Ernährungsprotokoll und Zutaten auf die Einkaufsliste.
class MealPlanRepository {
  MealPlanRepository({
    DatabaseService? db,
    required ListsRepository lists,
    required InventoryRepository inventory,
    AppointmentRepository? appointments,
  })  : _db = db ?? DatabaseService.instance,
        _lists = lists,
        _inventory = inventory,
        _appointments = appointments ?? AppointmentRepository(db: db);

  final DatabaseService _db;
  final ListsRepository _lists;
  final InventoryRepository _inventory;
  final AppointmentRepository _appointments;

  static String _now() => syncStamp();

  // ─── Rezepte ──────────────────────────────────────────────────────────

  /// Eigene Rezepte zuerst, dann der mitgelieferte Katalog.
  Future<List<Recipe>> getRecipes(int uid) async {
    final db = await _db.database;
    final rows = await db.query('recipes',
        where: 'userid = ? AND is_deleted = 0', whereArgs: [uid], orderBy: 'name COLLATE NOCASE');
    return [...rows.map(Recipe.fromMap), ...recipeCatalog];
  }

  Future<Recipe?> getRecipe(int id) async {
    final db = await _db.database;
    final rows = await db.query('recipes', where: 'id = ? AND is_deleted = 0', whereArgs: [id]);
    return rows.isEmpty ? null : Recipe.fromMap(rows.first);
  }

  Future<int> saveRecipe(Recipe recipe) async {
    final db = await _db.database;
    if (recipe.id == null) return db.insert('recipes', recipe.toMap()..remove('id'));
    await db.update('recipes', {...recipe.toMap()..remove('id'), 'last_changed': _now()},
        where: 'id = ?', whereArgs: [recipe.id]);
    return recipe.id!;
  }

  /// Löscht ein eigenes Rezept. Bereits geplante Mahlzeiten behalten ihren Namen.
  Future<void> deleteRecipe(int id) async {
    final db = await _db.database;
    await db.update('recipes', {'is_deleted': 1, 'last_changed': _now()}, where: 'id = ?', whereArgs: [id]);
  }

  /// Rezept einer geplanten Mahlzeit (Katalog oder eigenes), `null` wenn es nicht mehr existiert.
  Future<Recipe?> recipeFor(PlannedMeal planned) async =>
      catalogRecipe(planned.recipeKey) ?? (planned.recipeId == null ? null : await getRecipe(planned.recipeId!));

  // ─── Plan ─────────────────────────────────────────────────────────────

  /// Plant [recipe] für [date] und [meal] ein.
  Future<PlannedMeal> plan({
    required int uid,
    required Recipe recipe,
    required DateTime date,
    required Meal meal,
    double servings = 1,
    int? time,
  }) async {
    final planned = PlannedMeal(
      userid: uid,
      date: DateTime(date.year, date.month, date.day),
      meal: meal,
      time: time,
      recipeKey: recipe.key,
      recipeId: recipe.id,
      name: recipe.name,
      servings: servings,
    );
    final db = await _db.database;
    final id = await db.insert('meal_plan', planned.toMap()..remove('id'));
    return PlannedMeal.fromMap({...planned.toMap(), 'id': id});
  }

  /// Ein einzelnes Lebensmittel einplanen (z. B. 60 g Haferflocken zum Frühstück), optional aus
  /// einem Vorratsartikel [itemId], der beim „Gegessen“ abgebucht wird.
  Future<PlannedMeal> planFood({
    required int uid,
    required Food food,
    required double grams,
    required DateTime date,
    required Meal meal,
    int? itemId,
  }) async {
    final planned = PlannedMeal(
      userid: uid,
      date: DateTime(date.year, date.month, date.day),
      meal: meal,
      name: food.name,
      servings: 1,
      foodId: food.id,
      grams: grams,
      itemId: itemId,
    );
    final db = await _db.database;
    final id = await db.insert('meal_plan', planned.toMap()..remove('id'));
    return PlannedMeal.fromMap({...planned.toMap(), 'id': id});
  }

  /// Eingeplantes Lebensmittel als gegessen eintragen: Eintrag im Ernährungsprotokoll mit den
  /// Nährwerten von [food], Vorratsartikel (falls gewählt) wird abgebucht.
  Future<PlannedMeal> markFoodEaten(PlannedMeal planned, Food food) async {
    if (planned.eaten) return planned;
    final grams = planned.grams ?? food.servingGrams ?? 100;
    final entry = MealEntry(
      userid: planned.userid,
      date: planned.date,
      meal: planned.meal,
      foodId: food.id,
      name: food.name,
      grams: grams,
      macros: food.per100.scaled(grams / 100),
    );
    final db = await _db.database;
    final usedUp = <int>[];
    final updated = await db.transaction((txn) async {
      final entryId = await txn.insert('meal_entries', entry.toMap()..remove('id'));
      if (planned.itemId != null) {
        final rows = await txn.query('inventory_items', columns: ['unit'], where: 'id = ? AND is_deleted = 0', whereArgs: [planned.itemId]);
        if (rows.isNotEmpty) {
          final unit = (rows.first['unit'] as String?)?.toLowerCase().trim();
          final rest = await _inventory.consumeIn(txn, planned.itemId!, unit == 'g' || unit == 'ml' ? grams : 1);
          if (rest == 0) usedUp.add(planned.itemId!);
        }
      }
      final updated = planned.copyWith(mealEntryId: entryId);
      await txn.update('meal_plan', {...updated.toMap()..remove('id'), 'last_changed': _now()},
          where: 'id = ?', whereArgs: [planned.id]);
      return updated;
    });
    for (final id in usedUp) {
      await _inventory.cancelExpiryReminder(id);
    }
    return updated;
  }

  Future<void> update(PlannedMeal planned) async {
    final db = await _db.database;
    await db.update('meal_plan', {...planned.toMap()..remove('id'), 'last_changed': _now()},
        where: 'id = ?', whereArgs: [planned.id]);
  }

  Future<void> restore(int id) => _db.restoreRow('meal_plan', id);

  Future<void> restoreRecipe(int id) => _db.restoreRow('recipes', id);

  Future<void> remove(int id) async {
    final db = await _db.database;
    await db.update('meal_plan', {'is_deleted': 1, 'last_changed': _now()}, where: 'id = ?', whereArgs: [id]);
  }

  /// Geplante Mahlzeiten von [from] bis einschließlich [to], nach Tag und Uhrzeit sortiert.
  /// Wurde der Protokolleintrag inzwischen gelöscht, gilt das Gericht wieder als offen.
  Future<List<PlannedMeal>> getRange(int uid, DateTime from, DateTime to) async {
    final db = await _db.database;
    final rows = await db.rawQuery('''
        SELECT p.*, CASE WHEN e.is_deleted = 0 THEN p.mealEntryId END AS mealEntryId
        FROM meal_plan p LEFT JOIN meal_entries e ON e.id = p.mealEntryId
        WHERE p.userid = ? AND p.is_deleted = 0 AND p.date >= ? AND p.date <= ?
        ORDER BY p.date, p.id''', [uid, MealEntry.dayKey(from), MealEntry.dayKey(to)]);
    return rows.map(PlannedMeal.fromMap).toList()..sort((a, b) => a.at.compareTo(b.at));
  }

  Future<List<PlannedMeal>> getDay(int uid, DateTime day) => getRange(uid, day, day);

  /// Was als Nächstes ansteht: heute ab [now] (noch nicht gegessen), sonst `null`.
  Future<List<PlannedMeal>> upcomingToday(int uid, DateTime now) async {
    final today = await getDay(uid, now);
    final open = today.where((p) => !p.eaten).toList();
    // Eine Mahlzeit gilt bis eine Stunde nach ihrer Uhrzeit als „jetzt“.
    return open.where((p) => p.at.add(const Duration(hours: 1)).isAfter(now)).toList();
  }

  // ─── Gegessen ─────────────────────────────────────────────────────────

  /// Trägt das Gericht mit seinen Nährwerten ins Ernährungsprotokoll ein und merkt sich den Eintrag.
  Future<PlannedMeal> markEaten(PlannedMeal planned, Recipe recipe) async {
    if (planned.eaten) return planned;
    final entry = MealEntry(
      userid: planned.userid,
      date: planned.date,
      meal: planned.meal,
      name: planned.servings == 1 ? recipe.name : '${recipe.name} (${portionsLabel(planned.servings)})',
      grams: recipe.gramsPerServing * planned.servings,
      macros: recipe.perServing.scaled(planned.servings),
    );
    final db = await _db.database;
    return db.transaction((txn) async {
      final entryId = await txn.insert('meal_entries', entry.toMap()..remove('id'));
      final updated = planned.copyWith(mealEntryId: entryId);
      await txn.update('meal_plan', {...updated.toMap()..remove('id'), 'last_changed': _now()},
          where: 'id = ?', whereArgs: [planned.id]);
      return updated;
    });
  }

  /// Nimmt „gegessen“ zurück und löscht den Eintrag im Protokoll.
  Future<PlannedMeal> unmarkEaten(PlannedMeal planned) async {
    if (!planned.eaten) return planned;
    final db = await _db.database;
    return db.transaction((txn) async {
      await txn.update('meal_entries', {'is_deleted': 1, 'last_changed': _now()},
          where: 'id = ?', whereArgs: [planned.mealEntryId]);
      final updated = planned.copyWith(clearMealEntry: true);
      await txn.update('meal_plan', {...updated.toMap()..remove('id'), 'last_changed': _now()},
          where: 'id = ?', whereArgs: [planned.id]);
      return updated;
    });
  }

  // ─── Einkaufsliste ────────────────────────────────────────────────────

  /// Setzt die Zutaten der Gerichte (je mit Portionenzahl) auf die Einkaufsliste. Mengen werden zu
  /// gleichen Zutaten anderer Herkunft aufaddiert; jedes Rezept bleibt als Herkunft sichtbar. Ohne
  /// [batchId] ersetzt ein erneutes Setzen desselben Rezepts dessen noch offene Mengen (kein Doppeltes
  /// bei zweimaligem Tippen). Liefert die Anzahl der Zutaten.
  Future<int> addToShopping(int uid, List<(Recipe, double)> dishes, {int? batchId}) async {
    var added = 0;
    for (final (recipe, servings) in dishes) {
      if (batchId == null) {
        await _lists.removeFromList(uid,
            recipeKey: recipe.key, recipeId: recipe.key == null ? recipe.id : null, onlyWithoutBatch: true, onlyOpen: true);
      }
      final factor = servings / recipe.servings;
      for (final ingredient in recipe.ingredients) {
        final amount = ingredient.amount == null ? null : ingredient.amount! * factor;
        await _lists.addToList(
          uid,
          name: ingredient.name,
          // Stück aufrunden: 1,5 Zwiebeln kauft man als 2
          amount: amount == null ? null : (ingredient.unit == null ? amount.ceilToDouble() : amount),
          unit: ingredient.unit,
          label: recipe.name,
          recipeKey: recipe.key,
          recipeId: recipe.id,
          batchId: batchId,
        );
        added++;
      }
    }
    return added;
  }

  // ─── Koch-Blöcke ──────────────────────────────────────────────────────

  /// Plant ein Rezept (× [factor]) ein: gekocht wird am [cookDate] (mit [cookHour]:[cookMinute] als
  /// Termin „Kochen: …“ im Kalender), die Portionen gehen auf [slots]. Nicht alle Portionen müssen
  /// verteilt sein; mehr als gekocht wird ist nicht erlaubt.
  Future<int> planBatch({
    required int uid,
    required Recipe recipe,
    required DateTime cookDate,
    required List<PortionSlot> slots,
    double factor = 1,
    int? cookHour,
    int cookMinute = 0,
    int durationMin = 60,
  }) async {
    _checkDistribution(recipe, factor, slots);
    final db = await _db.database;
    final batch = MealBatch(
      userid: uid,
      recipeKey: recipe.key,
      recipeId: recipe.id,
      name: recipe.name,
      factor: factor,
      cookDate: DateTime(cookDate.year, cookDate.month, cookDate.day),
      cookHour: cookHour,
      cookMinute: cookHour == null ? null : cookMinute,
      durationMin: durationMin,
    );
    final batchId = await db.transaction((txn) async {
      final batchId = await txn.insert('meal_batches', batch.toMap()..remove('id'));
      await _insertSlots(txn, uid, recipe, batchId, slots);
      return batchId;
    });
    await _syncAppointment(batchId);
    return batchId;
  }

  /// Hält den Koch-Termin im Kalender passend zum Block (anlegen, verschieben, entfernen).
  Future<void> _syncAppointment(int batchId) async {
    final batch = await getBatch(batchId);
    if (batch == null) return;
    final start = batch.cookStart;
    final existing = batch.appointmentId == null ? null : await _activeAppointment(batch.appointmentId!);
    if (start == null) {
      if (existing != null) await _appointments.deleteAppointment(existing.id!);
      return;
    }
    final appointment = Appointment(
      id: existing?.id,
      title: 'Kochen: ${batch.name}',
      description: 'Koch-Block aus dem Essensplan',
      date: start,
      durationMinutes: batch.durationMin,
      userid: batch.userid,
      reminderMinutes: existing?.reminderMinutes ?? Appointment.defaultReminderMinutes,
    );
    if (existing != null) {
      await _appointments.updateAppointment(appointment);
    } else {
      final id = await _appointments.createAppointment(appointment);
      final db = await _db.database;
      await db.update('meal_batches', {'appointmentId': id, 'last_changed': _now()}, where: 'id = ?', whereArgs: [batchId]);
    }
  }

  Future<Appointment?> _activeAppointment(int id) async {
    final db = await _db.database;
    final rows = await db.query('appointments', where: 'id = ? AND is_deleted = 0', whereArgs: [id]);
    return rows.isEmpty ? null : Appointment.fromMap(rows.first);
  }

  /// Verteilung bzw. Menge eines Koch-Blocks ändern. Bereits gegessene Portionen bleiben stehen.
  Future<void> replanBatch(
    MealBatch batch,
    Recipe recipe, {
    required DateTime cookDate,
    required List<PortionSlot> slots,
    double? factor,
    int? cookHour,
    int cookMinute = 0,
    int? durationMin,
  }) async {
    final f = factor ?? batch.factor;
    final db = await _db.database;
    await db.transaction((txn) async {
      final eaten = await txn.query('meal_plan',
          where: 'batchId = ? AND is_deleted = 0 AND mealEntryId IS NOT NULL', whereArgs: [batch.id]);
      final eatenServings = eaten.fold<double>(0, (s, r) => s + ((r['servings'] as num?)?.toDouble() ?? 0));
      _checkDistribution(recipe, f, slots, alreadyEaten: eatenServings);
      await txn.update('meal_plan', {'is_deleted': 1, 'last_changed': _now()},
          where: 'batchId = ? AND is_deleted = 0 AND mealEntryId IS NULL', whereArgs: [batch.id]);
      await txn.update(
          'meal_batches',
          {
            'factor': f,
            'cookDate': MealEntry.dayKey(cookDate),
            'cookTime': cookHour == null ? null : '${cookHour.toString().padLeft(2, '0')}:${cookMinute.toString().padLeft(2, '0')}',
            'durationMin': durationMin ?? batch.durationMin,
            'last_changed': _now(),
          },
          where: 'id = ?',
          whereArgs: [batch.id]);
      await _insertSlots(txn, batch.userid, recipe, batch.id!, slots);
    });
    await _syncAppointment(batch.id!);
  }

  /// Portionen eines Blocks, die noch keiner Mahlzeit zugeordnet sind.
  Future<double> unplannedServings(MealBatch batch, Recipe recipe) async {
    final meals = await getBatchMeals(batch.id!);
    final planned = meals.fold<double>(0, (s, m) => s + m.servings);
    final left = batch.servingsOf(recipe) - planned;
    return left > 0.01 ? left : 0;
  }

  static void _checkDistribution(Recipe recipe, double factor, List<PortionSlot> slots, {double alreadyEaten = 0}) {
    final total = recipe.servings * factor;
    final planned = slots.fold<double>(alreadyEaten, (s, p) => s + p.servings);
    if (planned - total > 0.01) {
      throw StateError('Es sind ${_fmt(planned)} Portionen verteilt, gekocht werden aber nur ${_fmt(total)}.');
    }
  }

  static String _fmt(double v) => v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toString().replaceAll('.', ',');

  Future<void> _insertSlots(DatabaseExecutor txn, int uid, Recipe recipe, int batchId, List<PortionSlot> slots) async {
    for (final slot in slots.where((s) => s.servings > 0)) {
      await txn.insert('meal_plan', PlannedMeal(
        userid: uid,
        date: DateTime(slot.date.year, slot.date.month, slot.date.day),
        meal: slot.meal,
        recipeKey: recipe.key,
        recipeId: recipe.id,
        name: recipe.name,
        servings: slot.servings,
        batchId: batchId,
      ).toMap()..remove('id'));
    }
  }

  Future<MealBatch?> getBatch(int id) async {
    final db = await _db.database;
    final rows = await db.query('meal_batches', where: 'id = ? AND is_deleted = 0', whereArgs: [id]);
    return rows.isEmpty ? null : MealBatch.fromMap(rows.first);
  }

  /// Koch-Blöcke, die zwischen [from] und [to] gekocht werden oder dort Portionen haben.
  Future<List<MealBatch>> getBatches(int uid, DateTime from, DateTime to) async {
    final db = await _db.database;
    final f = MealEntry.dayKey(from), t = MealEntry.dayKey(to);
    final rows = await db.rawQuery('''
        SELECT * FROM meal_batches b WHERE b.userid = ? AND b.is_deleted = 0 AND (
          (b.cookDate >= ? AND b.cookDate <= ?) OR EXISTS (
            SELECT 1 FROM meal_plan p WHERE p.batchId = b.id AND p.is_deleted = 0 AND p.date >= ? AND p.date <= ?))
        ORDER BY b.cookDate, b.id''', [uid, f, t, f, t]);
    return rows.map(MealBatch.fromMap).toList();
  }

  /// Portionen eines Koch-Blocks.
  Future<List<PlannedMeal>> getBatchMeals(int batchId) async {
    final db = await _db.database;
    final rows = await db.query('meal_plan', where: 'batchId = ? AND is_deleted = 0', whereArgs: [batchId], orderBy: 'date, id');
    return rows.map(PlannedMeal.fromMap).toList();
  }

  /// Löscht einen Koch-Block mit seinen Portionen. Liefert den Zeitstempel für „Rückgängig“.
  Future<String> deleteBatch(int batchId) async {
    final db = await _db.database;
    final at = _now();
    final batch = await getBatch(batchId);
    await db.transaction((txn) async {
      await txn.update('meal_batches', {'is_deleted': 1, 'last_changed': at}, where: 'id = ?', whereArgs: [batchId]);
      await txn.update('meal_plan', {'is_deleted': 1, 'last_changed': at},
          where: 'batchId = ? AND is_deleted = 0', whereArgs: [batchId]);
      // Reservierte Vorratsmengen werden wieder frei
      await txn.update('pantry_reservations', {'is_deleted': 1, 'last_changed': at},
          where: 'batchId = ? AND is_deleted = 0', whereArgs: [batchId]);
    });
    if (batch?.appointmentId != null) await _appointments.deleteAppointment(batch!.appointmentId!);
    return at;
  }

  Future<void> restoreBatch(int batchId, String at) async {
    final db = await _db.database;
    await db.transaction((txn) async {
      await txn.update('meal_batches', {'is_deleted': 0}, where: 'id = ?', whereArgs: [batchId]);
      await txn.update('meal_plan', {'is_deleted': 0},
          where: 'batchId = ? AND is_deleted = 1 AND last_changed = ?', whereArgs: [batchId, at]);
      await txn.update('pantry_reservations', {'is_deleted': 0},
          where: 'batchId = ? AND is_deleted = 1 AND last_changed = ?', whereArgs: [batchId, at]);
    });
    final batch = await getBatch(batchId);
    if (batch?.appointmentId != null) {
      final rows = await db.query('appointments', where: 'id = ?', whereArgs: [batch!.appointmentId]);
      if (rows.isNotEmpty) await _appointments.restoreAppointment(Appointment.fromMap(rows.first));
    }
  }

  /// Alle Zutaten eines Koch-Blocks wieder von der Einkaufsliste nehmen (z. B. nach einem Vertipper).
  Future<String> removeBatchFromShopping(int uid, int batchId) => _lists.removeFromList(uid, batchId: batchId);

  Future<void> restoreShopping(int uid, String at) => _lists.restoreRemoved(uid, at);

  Future<Recipe?> _recipeOf(String? key, int? id) async => catalogRecipe(key) ?? (id == null ? null : await getRecipe(id));

  Future<Recipe?> recipeOfBatch(MealBatch batch) => _recipeOf(batch.recipeKey, batch.recipeId);

  // ─── Gekocht ──────────────────────────────────────────────────────────

  /// „Heute gekocht“: bucht die tatsächlich genommenen Mengen im Vorrat ab und schreibt das
  /// Protokoll; ein eingeplanter Koch-Block gilt danach als gekocht.
  Future<CookLog> markCooked({
    required int uid,
    required Recipe recipe,
    required DateTime date,
    required List<CookUsage> usages,
    MealBatch? batch,
  }) async {
    final log = CookLog(
      userid: uid,
      batchId: batch?.id,
      recipeKey: recipe.key,
      recipeId: recipe.id,
      name: recipe.name,
      date: date,
      usages: usages,
    );
    final db = await _db.database;
    final usedUp = <int>[];
    final id = await db.transaction((txn) async {
      for (final u in usages.where((u) => u.fromPantry)) {
        final rest = await _inventory.consumeIn(txn, u.itemId!, u.amount!);
        if (rest == 0) usedUp.add(u.itemId!);
      }
      final id = await txn.insert('cook_logs', log.toMap()..remove('id'));
      if (batch != null) {
        await txn.update('meal_batches', {'cookedAt': MealEntry.dayKey(date), 'last_changed': _now()},
            where: 'id = ?', whereArgs: [batch.id]);
        // Gekocht: die Reservierungen sind verbraucht (abgebucht wird über [usages])
        await txn.update('pantry_reservations', {'is_deleted': 1, 'last_changed': _now()},
            where: 'batchId = ? AND is_deleted = 0', whereArgs: [batch.id]);
      }
      return id;
    });
    for (final itemId in usedUp) {
      await _inventory.cancelExpiryReminder(itemId);
    }
    return CookLog.fromMap({...log.toMap(), 'id': id});
  }

  Future<List<CookLog>> getCookLogs(int uid, DateTime from, DateTime to) async {
    final db = await _db.database;
    final rows = await db.query('cook_logs',
        where: 'userid = ? AND is_deleted = 0 AND date >= ? AND date <= ?',
        whereArgs: [uid, MealEntry.dayKey(from), MealEntry.dayKey(to)],
        orderBy: 'date, id');
    return rows.map(CookLog.fromMap).toList();
  }

  // ─── Vorrat reservieren ───────────────────────────────────────────────

  Future<List<PantryReservation>> _activeReservations(int uid) async {
    final db = await _db.database;
    final rows = await db.query('pantry_reservations', where: 'userid = ? AND is_deleted = 0', whereArgs: [uid]);
    return rows.map(PantryReservation.fromMap).toList();
  }

  /// Reservierungen eines Koch-Blocks.
  Future<List<PantryReservation>> reservationsOf(int batchId) async {
    final db = await _db.database;
    final rows = await db.query('pantry_reservations', where: 'batchId = ? AND is_deleted = 0', whereArgs: [batchId]);
    return rows.map(PantryReservation.fromMap).toList();
  }

  /// Welche Zutaten von [recipe] × [factor] im Vorrat sind – ohne das, was **andere** Koch-Blöcke
  /// schon reserviert haben ([batchId] = der Block, der gerade geplant wird).
  Future<List<PantryCheck>> checkPantry(int uid, Recipe recipe, double factor, {int? batchId}) async {
    final pantry = await _inventory.getItems(uid, kinds: {InventoryKind.food, InventoryKind.drink, InventoryKind.other});
    final reserved = (await _activeReservations(uid)).where((r) => r.batchId != batchId).toList();
    return checkPantryItems(recipe: recipe, factor: factor, pantry: pantry, reserved: reserved);
  }

  /// Speichert die Zutaten-Entscheidung eines Koch-Blocks: [usePantry] je Zutat (gleiche Reihenfolge
  /// wie [checks]). Ja → Vorrat reservieren (Teil-Rest auf die Einkaufsliste), Nein oder nicht im
  /// Vorrat → Einkaufsliste. Mit [pantry] = false wird nichts reserviert, mit [shop] = false nichts
  /// eingekauft (beides wird am Block gemerkt).
  ///
  /// Erneutes Speichern ersetzt Reservierungen und den offenen Einkauf dieses Blocks. Schon Gekauftes
  /// (abgehakt) wird abgezogen – es kommt nicht noch einmal auf die Liste, nur was darüber hinaus fehlt.
  /// Liefert (reserviert, auf der Einkaufsliste).
  Future<(int, int)> saveIngredientPlan(int uid, int batchId, List<PantryCheck> checks, List<bool> usePantry,
      {bool pantry = true, bool shop = true}) async {
    final db = await _db.database;
    var reserved = 0;
    final toBuy = <(PantryCheck, double?)>[];
    await db.transaction((txn) async {
      await txn.update('pantry_reservations', {'is_deleted': 1, 'last_changed': _now()},
          where: 'batchId = ? AND is_deleted = 0', whereArgs: [batchId]);
      for (var i = 0; i < checks.length; i++) {
        final c = checks[i];
        if (pantry && usePantry[i] && c.inPantry) {
          await txn.insert('pantry_reservations', PantryReservation(
            userid: uid,
            batchId: batchId,
            itemId: c.item!.id!,
            ingredient: c.ingredient.name,
            amount: c.reserve,
            unit: c.item!.unit,
          ).toMap());
          reserved++;
          if (c.status == PantryStatus.partial) toBuy.add((c, c.shortfall));
        } else {
          toBuy.add((c, c.need));
        }
      }
      await txn.update(
          'meal_batches',
          {'ingredientsPlanned': 1, 'usePantry': pantry ? 1 : 0, 'shop': shop ? 1 : 0, 'last_changed': _now()},
          where: 'id = ?',
          whereArgs: [batchId]);
    });
    // Offenen Einkauf dieses Blocks neu aufbauen; Gekauftes bleibt stehen und wird abgezogen
    await _lists.removeFromList(uid, batchId: batchId, onlyOpen: true);
    if (!shop) return (reserved, 0);
    final bought = await _lists.boughtFor(uid, batchId);
    final batch = await getBatch(batchId);
    var added = 0;
    for (final (c, need) in toBuy) {
      // Stück aufrunden: 1,5 Zwiebeln kauft man als 2
      var amount = need == null ? null : (c.needUnit == null ? need.ceilToDouble() : need);
      final key = (c.ingredient.name.trim().toLowerCase(), amount == null ? c.needUnit : normalizeAmount(amount, c.needUnit).$2);
      if (bought.containsKey(key)) {
        final done = bought[key];
        if (done == null || amount == null) continue; // schon gekauft (ohne vergleichbare Menge)
        amount = normalizeAmount(amount, c.needUnit).$1 - done;
        if (amount <= 0.0001) continue;
        await _lists.addToList(uid, name: c.ingredient.name, amount: amount, unit: key.$2, label: batch?.name ?? '',
            recipeKey: batch?.recipeKey, recipeId: batch?.recipeId, batchId: batchId);
      } else {
        await _lists.addToList(uid, name: c.ingredient.name, amount: amount, unit: c.needUnit, label: batch?.name ?? '',
            recipeKey: batch?.recipeKey, recipeId: batch?.recipeId, batchId: batchId);
      }
      added++;
    }
    return (reserved, added);
  }
}
