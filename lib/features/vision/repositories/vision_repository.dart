export 'package:frontend/features/vision/data/vision_template.dart';

import 'package:sqflite/sqflite.dart';

import 'package:frontend/core/database/database.dart';
import 'package:frontend/features/vision/data/vision_template.dart';
import 'package:frontend/features/calendar/models/appointment.dart';
import 'package:frontend/features/todos/models/todo.dart';
import 'package:frontend/features/vision/models/vision.dart';

/// Vision Board: Bereiche, Ziele und Schritt-für-Schritt-Pläne.
///
/// To-Dos und Termine gehören zu einem Schritt, wenn ihr `goalStepId` gesetzt ist.
/// Angelegt werden sie über Todo-/AppointmentRepository; hier werden sie nur gelesen
/// und verknüpft.
class VisionRepository {
  VisionRepository({DatabaseService? db}) : _db = db ?? DatabaseService.instance;

  final DatabaseService _db;

  static String _now() => syncStamp();

  Future<int> _nextPosition(DatabaseExecutor db, String table, String column, int value) async {
    final r = await db.rawQuery('SELECT COALESCE(MAX(position), -1) + 1 AS p FROM $table WHERE $column = ? AND is_deleted = 0', [value]);
    return (r.first['p'] as num).toInt();
  }

  Future<int> _insertAtEnd(String table, String column, int value, Map<String, dynamic> row) async {
    final db = await _db.database;
    return db.transaction((txn) async {
      final position = await _nextPosition(txn, table, column, value);
      return txn.insert(table, {...row..remove('id'), 'position': position});
    });
  }

  Future<void> _update(String table, int id, Map<String, dynamic> values) async {
    final db = await _db.database;
    await db.update(table, {...values, 'last_changed': _now()}, where: 'id = ?', whereArgs: [id]);
  }

  // ─── Bereiche ─────────────────────────────────────────────────────────

  Future<int> createArea(VisionArea area) => _insertAtEnd('vision_areas', 'userid', area.userid, area.toMap());

  Future<void> updateArea(VisionArea area) => _update('vision_areas', area.id!, area.toMap()..remove('id'));

  /// Löscht den Bereich samt Zielen und Schritten. Verknüpfte To-Dos und Termine
  /// bleiben erhalten und verlieren nur die Zuordnung.
  Future<VisionDeletion> deleteArea(int areaId) async {
    final db = await _db.database;
    final deletion = VisionDeletion(_now());
    await db.transaction((txn) async {
      final goals = await txn.query('vision_goals',
          columns: ['id'], where: 'areaId = ? AND is_deleted = 0', whereArgs: [areaId]);
      for (final g in goals) {
        await _deleteGoal(txn, g['id'] as int, deletion);
      }
      await txn.update('vision_areas', {'is_deleted': 1, 'last_changed': deletion.at}, where: 'id = ?', whereArgs: [areaId]);
    });
    return deletion;
  }

  /// Macht ein Löschen rückgängig: alles, was dabei gelöscht wurde, wird wieder sichtbar,
  /// verknüpfte To-Dos und Termine hängen wieder an ihrem Schritt.
  Future<void> restoreDeletion(VisionDeletion deletion) async {
    final db = await _db.database;
    final now = _now();
    await db.transaction((txn) async {
      for (final table in ['vision_areas', 'vision_goals', 'goal_steps']) {
        await txn.update(table, {'is_deleted': 0, 'last_changed': now},
            where: 'is_deleted = 1 AND last_changed = ?', whereArgs: [deletion.at]);
      }
      for (final (table, id, stepId) in deletion.links) {
        await txn.update(table, {'goalStepId': stepId, 'last_changed': now}, where: 'id = ?', whereArgs: [id]);
      }
    });
  }

  // ─── Ziele ────────────────────────────────────────────────────────────

  Future<int> createGoal(VisionGoal goal) => _insertAtEnd('vision_goals', 'areaId', goal.areaId, goal.toMap());

  Future<void> updateGoal(VisionGoal goal) => _update('vision_goals', goal.id!, goal.toMap()..remove('id'));

  Future<void> setGoalAchieved(int goalId, bool achieved) =>
      _update('vision_goals', goalId, {'isAchieved': achieved ? 1 : 0});

  Future<VisionDeletion> deleteGoal(int goalId) async {
    final db = await _db.database;
    final deletion = VisionDeletion(_now());
    await db.transaction((txn) => _deleteGoal(txn, goalId, deletion));
    return deletion;
  }

  Future<void> _deleteGoal(DatabaseExecutor txn, int goalId, VisionDeletion deletion) async {
    final steps = await txn.query('goal_steps', columns: ['id'], where: 'goalId = ? AND is_deleted = 0', whereArgs: [goalId]);
    for (final s in steps) {
      await _unlinkStep(txn, s['id'] as int, deletion);
    }
    await txn.update('goal_steps', {'is_deleted': 1, 'last_changed': deletion.at},
        where: 'goalId = ? AND is_deleted = 0', whereArgs: [goalId]);
    await txn.update('vision_goals', {'is_deleted': 1, 'last_changed': deletion.at}, where: 'id = ?', whereArgs: [goalId]);
  }

  // ─── Schritte ─────────────────────────────────────────────────────────

  Future<int> createStep(GoalStep step) => _insertAtEnd('goal_steps', 'goalId', step.goalId, step.toMap());

  Future<void> updateStep(GoalStep step) => _update('goal_steps', step.id!, step.toMap()..remove('id'));

  Future<void> setStepDone(int stepId, bool done) => _update('goal_steps', stepId, {'isDone': done ? 1 : 0});

  Future<VisionDeletion> deleteStep(int stepId) async {
    final db = await _db.database;
    final deletion = VisionDeletion(_now());
    await db.transaction((txn) async {
      await _unlinkStep(txn, stepId, deletion);
      await txn.update('goal_steps', {'is_deleted': 1, 'last_changed': deletion.at}, where: 'id = ?', whereArgs: [stepId]);
    });
    return deletion;
  }

  /// Tauscht die Position eines Schritts mit seinem Nachbarn ([delta] = -1 hoch, +1 runter).
  Future<void> moveStep(int goalId, int stepId, int delta) async {
    final db = await _db.database;
    await db.transaction((txn) async {
      final rows = await txn.query('goal_steps',
          where: 'goalId = ? AND is_deleted = 0', whereArgs: [goalId], orderBy: 'position, id');
      final ids = rows.map((r) => r['id'] as int).toList();
      final i = ids.indexOf(stepId);
      final j = i + delta;
      if (i < 0 || j < 0 || j >= ids.length) return;
      ids[i] = ids[j];
      ids[j] = stepId;
      for (var p = 0; p < ids.length; p++) {
        await txn.update('goal_steps', {'position': p, 'last_changed': _now()}, where: 'id = ?', whereArgs: [ids[p]]);
      }
    });
  }

  Future<void> _unlinkStep(DatabaseExecutor txn, int stepId, VisionDeletion deletion) async {
    for (final table in ['todos', 'appointments']) {
      final linked = await txn.query(table, columns: ['id'], where: 'goalStepId = ?', whereArgs: [stepId]);
      for (final row in linked) {
        deletion.links.add((table, row['id'] as int, stepId));
      }
      await txn.update(table, {'goalStepId': null, 'last_changed': deletion.at}, where: 'goalStepId = ?', whereArgs: [stepId]);
    }
  }

  // ─── Verknüpfung ──────────────────────────────────────────────────────

  /// Ordnet eine bestehende Aufgabe einem Schritt zu (`null` löst die Zuordnung).
  Future<void> linkTodo(int todoId, int? stepId) => _update('todos', todoId, {'goalStepId': stepId});

  /// Ordnet einen bestehenden Termin einem Schritt zu (`null` löst die Zuordnung).
  Future<void> linkAppointment(int appointmentId, int? stepId) =>
      _update('appointments', appointmentId, {'goalStepId': stepId});

  /// Offene To-Dos ohne Ziel-Zuordnung (zum Verknüpfen im Plan).
  Future<List<Todo>> unlinkedOpenTodos(int uid) async {
    final db = await _db.database;
    final rows = await db.query('todos',
        where: 'userid = ? AND is_deleted = 0 AND isCompleted = 0 AND goalStepId IS NULL',
        whereArgs: [uid],
        orderBy: 'dueDate');
    return rows.map(Todo.fromMap).toList();
  }

  /// Name des Ziels, zu dem ein Schritt gehört – für Hinweise in To-Do-Liste und Kalender.
  /// Alle offenen Plan-Schritte zur Auswahl („Ziel › Schritt“), z. B. im To-Do-Editor.
  Future<List<(int, String)>> stepChoices(int uid) async {
    final db = await _db.database;
    final rows = await db.rawQuery('''
      SELECT s.id AS stepId, g.title AS goal, s.title AS step FROM goal_steps s
      JOIN vision_goals g ON g.id = s.goalId
      WHERE s.userid = ? AND s.is_deleted = 0 AND g.is_deleted = 0
      ORDER BY g.position, g.id, s.position, s.id
    ''', [uid]);
    return [for (final r in rows) (r['stepId'] as int, '${r['goal']} › ${r['step']}')];
  }

  Future<Map<int, String>> goalTitlesForSteps(int uid) async {
    final db = await _db.database;
    final rows = await db.rawQuery('''
      SELECT s.id AS stepId, g.title AS goal FROM goal_steps s
      JOIN vision_goals g ON g.id = s.goalId
      WHERE s.userid = ? AND s.is_deleted = 0 AND g.is_deleted = 0
    ''', [uid]);
    return {for (final r in rows) r['stepId'] as int: r['goal'] as String};
  }

  // ─── Lesen ────────────────────────────────────────────────────────────

  /// Das gesamte Board: Bereiche mit ihren Zielen und dem Plan-Fortschritt je Ziel.
  Future<List<AreaWithGoals>> getBoard(int uid) async {
    final db = await _db.database;
    final areas = (await db.query('vision_areas',
            where: 'userid = ? AND is_deleted = 0', whereArgs: [uid], orderBy: 'position, id'))
        .map(VisionArea.fromMap)
        .toList();
    final goals = (await db.query('vision_goals',
            where: 'userid = ? AND is_deleted = 0', whereArgs: [uid], orderBy: 'position, id'))
        .map(VisionGoal.fromMap)
        .toList();
    final stepCounts = await db.rawQuery('''
      SELECT goalId, COUNT(*) AS total, SUM(isDone) AS done FROM goal_steps
      WHERE userid = ? AND is_deleted = 0 GROUP BY goalId
    ''', [uid]);
    final counts = {
      for (final r in stepCounts) r['goalId'] as int: ((r['done'] as num?)?.toInt() ?? 0, (r['total'] as num).toInt()),
    };

    return [
      for (final a in areas)
        AreaWithGoals(a, [
          for (final g in goals.where((g) => g.areaId == a.id))
            GoalSummary(g, counts[g.id]?.$1 ?? 0, counts[g.id]?.$2 ?? 0),
        ]),
    ];
  }

  /// Plan eines Ziels: Schritte in Reihenfolge mit verknüpften To-Dos und Terminen.
  Future<GoalPlan> getPlan(int goalId) async {
    final db = await _db.database;
    final goal = VisionGoal.fromMap((await db.query('vision_goals', where: 'id = ?', whereArgs: [goalId])).single);
    final area = VisionArea.fromMap((await db.query('vision_areas', where: 'id = ?', whereArgs: [goal.areaId])).single);
    final steps = (await db.query('goal_steps',
            where: 'goalId = ? AND is_deleted = 0', whereArgs: [goalId], orderBy: 'position, id'))
        .map(GoalStep.fromMap)
        .toList();

    final ids = steps.map((s) => s.id).toList();
    final todos = <Todo>[];
    final appointments = <Appointment>[];
    if (ids.isNotEmpty) {
      final placeholders = List.filled(ids.length, '?').join(',');
      todos.addAll((await db.query('todos',
              where: 'goalStepId IN ($placeholders) AND is_deleted = 0', whereArgs: ids, orderBy: 'dueDate'))
          .map(Todo.fromMap));
      appointments.addAll((await db.query('appointments',
              where: 'goalStepId IN ($placeholders) AND is_deleted = 0', whereArgs: ids, orderBy: 'date'))
          .map(Appointment.fromMap));
    }

    final states = deriveStepStates(steps);
    return GoalPlan(goal, area, [
      for (var i = 0; i < steps.length; i++)
        PlanStep(
          steps[i],
          todos.where((t) => t.goalStepId == steps[i].id).toList(),
          appointments.where((a) => a.goalStepId == steps[i].id).toList(),
          states[i],
        ),
    ]);
  }

  /// Legt die Bereiche und Ziele der Vision-Board-Vorlage ([visionBoardTemplate]) an.
  /// [imagePaths] sind die bereits in den App-Ordner kopierten Vorlagenbilder
  /// (gleiche Reihenfolge wie [visionBoardTemplate], Einträge dürfen `null` sein).
  /// Alles in einem DB-Transaktionsblock – schnell und ohne halb angelegtes Board.
  Future<void> createTemplateBoard(int uid, {List<String?> imagePaths = const []}) async {
    final db = await _db.database;
    await db.transaction((txn) async {
      var areaPosition = await _nextPosition(txn, 'vision_areas', 'userid', uid);
      for (var a = 0; a < visionBoardTemplate.length; a++) {
        final (title, color, _, goals) = visionBoardTemplate[a];
        final area = VisionArea(
          userid: uid,
          title: title,
          colorValue: color,
          imagePath: a < imagePaths.length ? imagePaths[a] : null,
          position: areaPosition++,
        );
        final areaId = await txn.insert('vision_areas', area.toMap()..remove('id'));
        for (var i = 0; i < goals.length; i++) {
          final (goal, note) = goals[i];
          await txn.insert('vision_goals',
              (VisionGoal(areaId: areaId, userid: uid, title: goal, note: note, position: i).toMap()..remove('id')));
        }
      }
    });
  }
}

/// Was beim Löschen eines Bereichs, Ziels oder Schritts passiert ist – für „Rückgängig“.
class VisionDeletion {
  /// Zeitstempel, mit dem alle gelöschten Zeilen markiert wurden.
  final String at;

  /// Gelöste Verknüpfungen: (Tabelle, ID, Schritt).
  final List<(String, int, int)> links = [];
  VisionDeletion(this.at);
}
