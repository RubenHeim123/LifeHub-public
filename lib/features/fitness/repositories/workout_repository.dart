import 'package:sqflite/sqflite.dart';

import 'package:frontend/core/database/database.dart';
import 'package:frontend/features/fitness/catalog/exercise_catalog.dart';
import 'package:frontend/features/fitness/catalog/sample_plans.dart';
import 'package:frontend/features/fitness/models/method_timer.dart';
import 'package:frontend/features/fitness/models/workout.dart';

/// Übungsbibliothek, Workouts, Trainingsplan, Protokoll und Fortschritt.
class WorkoutRepository {
  WorkoutRepository({DatabaseService? db}) : _db = db ?? DatabaseService.instance;

  final DatabaseService _db;

  static String _now() => syncStamp();
  static String _day(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  static DateTime _dayOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  // ─── Übungen ──────────────────────────────────────────────────────────

  Future<int> saveExercise(Exercise e) async {
    final db = await _db.database;
    if (e.id == null) return db.insert('exercises', e.toMap()..remove('id'));
    await db.update('exercises', {...e.toMap()..remove('id'), 'last_changed': _now()}, where: 'id = ?', whereArgs: [e.id]);
    return e.id!;
  }

  Future<void> restoreExercise(int id) => _db.restoreRow('exercises', id);

  Future<void> deleteExercise(int id) async {
    final db = await _db.database;
    await db.update('exercises', {'is_deleted': 1, 'last_changed': _now()}, where: 'id = ?', whereArgs: [id]);
  }

  Future<List<Exercise>> getExercises(int uid) async {
    final db = await _db.database;
    final rows = await db.query('exercises', where: 'userid = ? AND is_deleted = 0', whereArgs: [uid], orderBy: 'name COLLATE NOCASE');
    return rows.map(Exercise.fromMap).toList();
  }

  /// Startübungen passend zu Kraft mit Körpergewicht, Laufen und Calisthenics-Skills.
  Future<void> createStarterExercises(int uid) async {
    const starters = [
      ('Liegestütze', ExerciseType.strength, ExerciseMetric.reps),
      ('Klimmzüge', ExerciseType.strength, ExerciseMetric.reps),
      ('Dips', ExerciseType.strength, ExerciseMetric.reps),
      ('Kniebeugen', ExerciseType.strength, ExerciseMetric.reps),
      ('Plank', ExerciseType.strength, ExerciseMetric.time),
      ('Handstand halten', ExerciseType.skill, ExerciseMetric.time),
      ('Handstand-Liegestütze', ExerciseType.skill, ExerciseMetric.reps),
      ('Human-Flag-Progression', ExerciseType.skill, ExerciseMetric.time),
      ('Front-Lever-Progression', ExerciseType.skill, ExerciseMetric.time),
      ('Lauf', ExerciseType.run, ExerciseMetric.distance),
    ];
    final existing = (await getExercises(uid)).map((e) => e.name).toSet();
    final db = await _db.database;
    final batch = db.batch();
    for (final (name, type, metric) in starters) {
      if (existing.contains(name)) continue;
      batch.insert('exercises', Exercise(userid: uid, name: name, type: type, metric: metric).toMap()..remove('id'));
    }
    await batch.commit(noResult: true);
  }

  // ─── Workouts ─────────────────────────────────────────────────────────

  /// Speichert Workout samt Übungen (die Übungsliste wird komplett ersetzt).
  Future<int> saveWorkout(Workout w) async {
    final db = await _db.database;
    return db.transaction((txn) async {
      int id;
      if (w.id == null) {
        id = await txn.insert('workouts', w.toMap()..remove('id'));
      } else {
        id = w.id!;
        await txn.update('workouts', {...w.toMap()..remove('id'), 'last_changed': _now()}, where: 'id = ?', whereArgs: [id]);
        await txn.update('workout_exercises', {'is_deleted': 1, 'last_changed': _now()}, where: 'workoutId = ?', whereArgs: [id]);
      }
      for (var i = 0; i < w.exercises.length; i++) {
        await txn.insert('workout_exercises', w.exercises[i].toMap(id, w.userid, i));
      }
      return id;
    });
  }

  Future<void> restoreWorkout(int id) => _db.restoreRow('workouts', id);

  Future<void> restorePlanned(int plannedId) => _db.restoreRow('planned_workouts', plannedId);

  Future<void> deleteWorkout(int id) async {
    final db = await _db.database;
    await db.update('workouts', {'is_deleted': 1, 'last_changed': _now()}, where: 'id = ?', whereArgs: [id]);
  }

  Future<List<Workout>> getWorkouts(int uid) async {
    final db = await _db.database;
    final rows = await db.query('workouts', where: 'userid = ? AND is_deleted = 0', whereArgs: [uid], orderBy: 'name COLLATE NOCASE');
    return [for (final r in rows) await _withExercises(db, r)];
  }

  Future<Workout?> getWorkout(int id) async {
    final db = await _db.database;
    final rows = await db.query('workouts', where: 'id = ?', whereArgs: [id]);
    return rows.isEmpty ? null : _withExercises(db, rows.first);
  }

  Future<Workout> _withExercises(DatabaseExecutor db, Map<String, Object?> row) async {
    final items = await db.rawQuery('''
      SELECT we.sets, we.reps, we.durationSec, we.distanceKm, e.* FROM workout_exercises we
      JOIN exercises e ON e.id = we.exerciseId
      WHERE we.workoutId = ? AND we.is_deleted = 0
      ORDER BY we.position
    ''', [row['id']]);
    return Workout(
      id: row['id'] as int,
      userid: row['userid'] as int,
      name: row['name'] as String? ?? '',
      notes: row['notes'] as String?,
      repeatWeekdays: Workout.parseWeekdays(row['repeatWeekdays']),
      method: TrainingMethod.fromDb(row['method']),
      exercises: [
        for (final i in items)
          WorkoutExercise(
            exercise: Exercise.fromMap(i),
            sets: (i['sets'] as int?) ?? 1,
            reps: i['reps'] as int?,
            durationSec: i['durationSec'] as int?,
            distanceKm: (i['distanceKm'] as num?)?.toDouble(),
          ),
      ],
    );
  }

  // ─── Katalog & Beispielpläne ─────────────────────────────────────────

  /// Übernimmt eine Katalog-Übung in die eigene Bibliothek. Gibt es sie schon
  /// (gleicher Katalog-Verweis oder gleicher Name), wird die vorhandene geliefert.
  Future<Exercise> addFromCatalog(int uid, String key) async {
    final entry = catalogByKey[key];
    if (entry == null) throw ArgumentError('Unbekannte Katalog-Übung: $key');
    final existing = (await getExercises(uid)).where(
        (e) => e.catalogKey == key || (e.catalogKey == null && e.name.toLowerCase() == entry.name.toLowerCase()));
    if (existing.isNotEmpty) return existing.first;
    final id = await saveExercise(Exercise.fromCatalog(entry, uid));
    return (await getExercises(uid)).firstWhere((e) => e.id == id);
  }

  /// Legt für jeden Tag eines Plan-Blocks ein Workout mit der Trainingsform des Tages an.
  /// [weekdays] (1 = Mo) werden den Tagen der Reihe nach als Wochenwiederholung zugeordnet.
  /// Sätze und Wiederholungen ergeben sich aus der Trainingsform; nur Zirkel haben feste
  /// Wiederholungen pro Runde. Liefert die IDs der neuen Workouts.
  ///
  /// Mit [once] werden die Tage nicht wöchentlich wiederholt, sondern je einmal am nächsten
  /// passenden Wochentag ab [start] (Standard: heute) eingeplant.
  Future<List<int>> importSampleBlock(int uid, SamplePlan plan, PlanBlock block,
      {List<int> weekdays = const [], bool once = false, DateTime? start}) async {
    final from = _dayOnly(start ?? DateTime.now());
    final ids = <int>[];
    for (final (index, day) in block.days.indexed) {
      final exercises = <WorkoutExercise>[];
      final notes = <String>[];
      for (final (g, group) in day.groups.indexed) {
        for (final item in group) {
          final exercise = await addFromCatalog(uid, item.key);
          exercises.add(WorkoutExercise(exercise: exercise, sets: 1, reps: item.reps));
          final label = day.method == TrainingMethod.supersatz ? 'Paar ${g + 1}: ' : '';
          if (item.note != null) notes.add('$label${exercise.name} – ${item.note}');
        }
      }
      ids.add(await saveWorkout(Workout(
        userid: uid,
        name: '${plan.name} ${block.title} · Tag ${index + 1} ${day.title}',
        notes: notes.isEmpty ? null : notes.join('\n'),
        repeatWeekdays: !once && index < weekdays.length ? [weekdays[index]] : const [],
        exercises: exercises,
        method: day.method,
      )));
      if (once && index < weekdays.length) {
        final offset = (weekdays[index] - from.weekday + 7) % 7;
        await planWorkout(uid, ids.last, DateTime(from.year, from.month, from.day + offset));
      }
    }
    return ids;
  }

  // ─── Plan ─────────────────────────────────────────────────────────────

  Future<int> planWorkout(int uid, int workoutId, DateTime date) async {
    final db = await _db.database;
    final w = await getWorkout(workoutId);
    return db.insert('planned_workouts', {
      'userid': uid,
      'date': _day(date),
      'workoutId': workoutId,
      'name': w?.name,
      'status': PlanStatus.planned.dbValue,
    });
  }

  /// Einmalig eingeplante, noch offene Termine eines Workouts ab [from].
  Future<List<PlanEntry>> getUpcomingOnce(int uid, int workoutId, {DateTime? from}) async {
    final start = _dayOnly(from ?? DateTime.now());
    final plan = await getPlan(uid, start, DateTime(start.year, start.month, start.day + 365));
    return [
      for (final list in plan.values)
        ...list.where((e) => !e.isFromRepeat && e.workout.id == workoutId && e.status == PlanStatus.planned),
    ]..sort((a, b) => a.date.compareTo(b.date));
  }

  Future<void> removePlanned(int plannedId) async {
    final db = await _db.database;
    await db.update('planned_workouts', {'is_deleted': 1, 'last_changed': _now()}, where: 'id = ?', whereArgs: [plannedId]);
  }

  /// Plan von [from] bis [to] (inklusive): eingeplante Workouts plus Wochenwiederholungen,
  /// sofern an dem Tag nicht schon ein Eintrag für dasselbe Workout existiert.
  Future<Map<DateTime, List<PlanEntry>>> getPlan(int uid, DateTime from, DateTime to) async {
    final db = await _db.database;
    final start = _dayOnly(from);
    final end = _dayOnly(to);
    final rows = await db.query('planned_workouts',
        where: 'userid = ? AND is_deleted = 0 AND date >= ? AND date <= ?', whereArgs: [uid, _day(start), _day(end)], orderBy: 'id');
    final workouts = {for (final w in await getWorkouts(uid)) w.id!: w};

    final plan = <DateTime, List<PlanEntry>>{};
    for (final r in rows) {
      final w = workouts[r['workoutId']] ?? (r['workoutId'] == null ? null : await getWorkout(r['workoutId'] as int));
      if (w == null) continue;
      final date = DateTime.parse(r['date'] as String);
      plan.putIfAbsent(date, () => []).add(PlanEntry(
            id: r['id'] as int,
            date: date,
            workout: w,
            status: PlanStatus.fromDb(r['status']),
            sessionId: r['sessionId'] as int?,
          ));
    }
    for (var d = start; !d.isAfter(end); d = DateTime(d.year, d.month, d.day + 1)) {
      for (final w in workouts.values.where((w) => w.repeatsOn(d))) {
        final list = plan.putIfAbsent(d, () => []);
        if (list.any((e) => e.workout.id == w.id)) continue;
        list.add(PlanEntry(date: d, workout: w));
      }
    }
    plan.removeWhere((_, list) => list.isEmpty);
    return plan;
  }

  Future<List<PlanEntry>> getPlanForDay(int uid, DateTime day) async => (await getPlan(uid, day, day))[_dayOnly(day)] ?? [];

  Future<int> _persist(DatabaseExecutor db, int uid, PlanEntry entry) async {
    if (entry.id != null) return entry.id!;
    return db.insert('planned_workouts', {
      'userid': uid,
      'date': _day(entry.date),
      'workoutId': entry.workout.id,
      'name': entry.workout.name,
      'status': PlanStatus.planned.dbValue,
    });
  }

  Future<void> skip(int uid, PlanEntry entry) async {
    final db = await _db.database;
    final id = await _persist(db, uid, entry);
    await db.update('planned_workouts', {'status': PlanStatus.skipped.dbValue, 'last_changed': _now()}, where: 'id = ?', whereArgs: [id]);
  }

  // ─── Einheiten ────────────────────────────────────────────────────────

  /// Startet (oder setzt fort) die Einheit zu [entry]. Die Sätze sind mit den Vorgaben vorbelegt.
  Future<WorkoutSession> startSession(int uid, PlanEntry entry) async {
    if (entry.sessionId != null) return (await getSession(entry.sessionId!))!;
    final db = await _db.database;
    final sessionId = await db.transaction((txn) async {
      final plannedId = await _persist(txn, uid, entry);
      final id = await txn.insert('workout_sessions', {
        'userid': uid,
        'plannedId': plannedId,
        'workoutId': entry.workout.id,
        'name': entry.workout.name,
        'date': _day(entry.date),
      });
      // Bei Trainingsformen mit Timer entstehen die Sätze erst während des Trainings.
      for (final we in entry.workout.method == null ? entry.workout.exercises : const <WorkoutExercise>[]) {
        final sets = we.exercise.metric == ExerciseMetric.distance ? 1 : we.sets;
        for (var s = 0; s < sets; s++) {
          await txn.insert('session_sets', {
            'userid': uid,
            'sessionId': id,
            'exerciseId': we.exercise.id,
            'setIndex': s,
            'reps': we.reps,
            'durationSec': we.durationSec,
            'distanceKm': we.distanceKm,
            'done': 0,
          });
        }
      }
      await txn.update('planned_workouts', {'sessionId': id, 'last_changed': _now()}, where: 'id = ?', whereArgs: [plannedId]);
      return id;
    });
    return (await getSession(sessionId))!;
  }

  /// Startet ein eingetragenes Workout sofort (heute). Ist es heute bereits eingeplant und offen,
  /// wird dieser Eintrag verwendet (und eine begonnene Einheit fortgesetzt).
  Future<(PlanEntry, WorkoutSession)> startNow(int uid, Workout workout, {DateTime? now}) async {
    final today = _dayOnly(now ?? DateTime.now());
    final entry = (await getPlanForDay(uid, today))
            .where((e) => e.workout.id == workout.id && e.status == PlanStatus.planned)
            .firstOrNull ??
        PlanEntry(date: today, workout: workout);
    final session = await startSession(uid, entry);
    final saved = (await getPlanForDay(uid, today)).firstWhere((e) => e.sessionId == session.id);
    return (saved, session);
  }

  /// Hängt die während eines Timer-Trainings erfassten Sätze an die Einheit an.
  Future<void> addSets(int sessionId, int uid, List<LoggedSet> sets) async {
    final db = await _db.database;
    final batch = db.batch();
    for (final s in sets) {
      final metric = s.exercise.metric;
      batch.insert('session_sets', {
        'userid': uid,
        'sessionId': sessionId,
        'exerciseId': s.exercise.id,
        'setIndex': s.setIndex,
        'reps': metric == ExerciseMetric.reps ? s.value?.round() : null,
        'durationSec': metric == ExerciseMetric.time ? s.value?.round() : null,
        'distanceKm': metric == ExerciseMetric.distance ? s.value?.toDouble() : null,
        'done': 1,
      });
    }
    await batch.commit(noResult: true);
  }

  Future<WorkoutSession?> getSession(int id) async {
    final db = await _db.database;
    final rows = await db.query('workout_sessions', where: 'id = ?', whereArgs: [id]);
    if (rows.isEmpty) return null;
    final r = rows.first;
    final sets = await db.rawQuery('''
      SELECT s.id AS setId, s.setIndex, s.reps AS setReps, s.durationSec AS setDuration, s.distanceKm AS setDistance,
             s.done, e.* FROM session_sets s JOIN exercises e ON e.id = s.exerciseId
      WHERE s.sessionId = ? AND s.is_deleted = 0 ORDER BY s.id
    ''', [id]);
    return WorkoutSession(
      id: id,
      plannedId: r['plannedId'] as int?,
      name: r['name'] as String? ?? '',
      date: DateTime.parse(r['date'] as String),
      durationMin: r['durationMin'] as int?,
      notes: r['notes'] as String?,
      sets: [
        for (final s in sets)
          SessionSet(
            id: s['setId'] as int,
            exercise: Exercise.fromMap(s),
            setIndex: s['setIndex'] as int,
            reps: s['setReps'] as int?,
            durationSec: s['setDuration'] as int?,
            distanceKm: (s['setDistance'] as num?)?.toDouble(),
            done: s['done'] == 1,
          ),
      ],
    );
  }

  Future<void> updateSet(SessionSet set) async {
    final db = await _db.database;
    await db.update(
      'session_sets',
      {'reps': set.reps, 'durationSec': set.durationSec, 'distanceKm': set.distanceKm, 'done': set.done ? 1 : 0, 'last_changed': _now()},
      where: 'id = ?',
      whereArgs: [set.id],
    );
  }

  /// Schließt die Einheit ab; der Planeintrag gilt dann als erledigt.
  Future<void> finishSession(WorkoutSession session, {int? durationMin, String? notes}) async {
    final db = await _db.database;
    await db.transaction((txn) async {
      await txn.update('workout_sessions', {'durationMin': durationMin, 'notes': notes, 'last_changed': _now()},
          where: 'id = ?', whereArgs: [session.id]);
      if (session.plannedId != null) {
        await txn.update('planned_workouts', {'status': PlanStatus.done.dbValue, 'last_changed': _now()},
            where: 'id = ?', whereArgs: [session.plannedId]);
      }
    });
  }

  // ─── Fortschritt ──────────────────────────────────────────────────────

  /// Bestwert je abgeschlossener Einheit (nur erledigte Sätze), älteste zuerst.
  Future<ExerciseProgress> getProgress(Exercise exercise) async {
    final db = await _db.database;
    final column = switch (exercise.metric) {
      ExerciseMetric.reps => 's.reps',
      ExerciseMetric.time => 's.durationSec',
      ExerciseMetric.distance => 's.distanceKm',
    };
    final rows = await db.rawQuery('''
      SELECT w.date AS date, MAX($column) AS best FROM session_sets s
      JOIN workout_sessions w ON w.id = s.sessionId
      WHERE s.exerciseId = ? AND s.done = 1 AND s.is_deleted = 0 AND w.is_deleted = 0 AND $column IS NOT NULL
      GROUP BY w.id ORDER BY w.date, w.id
    ''', [exercise.id]);
    return ExerciseProgress(exercise, [for (final r in rows) (DateTime.parse(r['date'] as String), r['best'] as num)]);
  }
}
