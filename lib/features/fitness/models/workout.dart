import 'dart:convert';

import 'package:frontend/features/fitness/catalog/exercise_catalog.dart';
import 'package:frontend/features/fitness/models/training_method.dart';

export 'package:frontend/features/fitness/models/training_method.dart';

/// Art einer Übung.
enum ExerciseType {
  strength('strength', 'Kraft'),
  run('run', 'Laufen'),
  skill('skill', 'Skill'),
  other('other', 'Sonstiges');

  const ExerciseType(this.dbValue, this.label);
  final String dbValue;
  final String label;

  static ExerciseType fromDb(Object? v) => values.firstWhere((t) => t.dbValue == v, orElse: () => other);
}

/// Was bei einer Übung gemessen wird.
enum ExerciseMetric {
  reps('reps', 'Wiederholungen', 'Wdh.'),
  time('time', 'Zeit', 's'),
  distance('distance', 'Distanz', 'km');

  const ExerciseMetric(this.dbValue, this.label, this.unit);
  final String dbValue;
  final String label;
  final String unit;

  static ExerciseMetric fromDb(Object? v) => values.firstWhere((m) => m.dbValue == v, orElse: () => reps);
}

/// Übung aus der eigenen Bibliothek.
class Exercise {
  final int? id;
  final int userid;
  final String name;
  final ExerciseType type;
  final ExerciseMetric metric;
  final String? notes;

  /// Verweis auf eine Übung aus dem mitgelieferten Katalog (Animation, Anleitung).
  final String? catalogKey;

  const Exercise({
    this.id,
    required this.userid,
    required this.name,
    this.type = ExerciseType.strength,
    this.metric = ExerciseMetric.reps,
    this.notes,
    this.catalogKey,
  });

  CatalogExercise? get catalog => catalogKey == null ? null : catalogByKey[catalogKey];

  factory Exercise.fromCatalog(CatalogExercise c, int userid) =>
      Exercise(userid: userid, name: c.name, type: c.type, metric: c.metric, catalogKey: c.key);

  Map<String, dynamic> toMap() => {
        'id': id,
        'userid': userid,
        'name': name,
        'type': type.dbValue,
        'metric': metric.dbValue,
        'notes': notes,
        'catalogKey': catalogKey,
      };

  factory Exercise.fromMap(Map<String, dynamic> m) => Exercise(
        id: m['id'],
        userid: m['userid'],
        name: m['name'] ?? '',
        type: ExerciseType.fromDb(m['type']),
        metric: ExerciseMetric.fromDb(m['metric']),
        notes: m['notes'],
        catalogKey: m['catalogKey'],
      );
}

/// Übung innerhalb eines Workouts mit Vorgabe (Sätze × Wdh./Zeit/Distanz).
class WorkoutExercise {
  final Exercise exercise;
  final int sets;
  final int? reps;
  final int? durationSec;
  final double? distanceKm;

  const WorkoutExercise({required this.exercise, this.sets = 3, this.reps, this.durationSec, this.distanceKm});

  /// Zielwert passend zur Messgröße.
  num? get target => switch (exercise.metric) {
        ExerciseMetric.reps => reps,
        ExerciseMetric.time => durationSec,
        ExerciseMetric.distance => distanceKm,
      };

  String get summary {
    final t = target;
    final value = t == null ? '' : ' × ${formatValue(exercise.metric, t)}';
    return exercise.metric == ExerciseMetric.distance ? formatValue(exercise.metric, t ?? 0) : '$sets$value';
  }

  Map<String, dynamic> toMap(int workoutId, int userid, int position) => {
        'workoutId': workoutId,
        'exerciseId': exercise.id,
        'userid': userid,
        'sets': sets,
        'reps': reps,
        'durationSec': durationSec,
        'distanceKm': distanceKm,
        'position': position,
      };
}

/// Zusammengestelltes Workout, optional jede Woche an [repeatWeekdays] (1 = Montag).
class Workout {
  final int? id;
  final int userid;
  final String name;
  final String? notes;
  final List<int> repeatWeekdays;
  final List<WorkoutExercise> exercises;

  /// Trainingsform mit Timer; `null` = frei mit eigenen Sätzen × Wiederholungen.
  final TrainingMethod? method;

  const Workout({
    this.id,
    required this.userid,
    required this.name,
    this.notes,
    this.repeatWeekdays = const [],
    this.exercises = const [],
    this.method,
  });

  /// Übungspaare für Supersätze (je zwei aufeinanderfolgende Übungen), sonst je eine Übung.
  List<List<WorkoutExercise>> get groups => method == TrainingMethod.supersatz
      ? [for (var i = 0; i < exercises.length; i += 2) exercises.sublist(i, (i + 2).clamp(0, exercises.length))]
      : [for (final e in exercises) [e]];

  /// Anzeige der Vorgabe einer Übung passend zur Trainingsform.
  String targetOf(WorkoutExercise e) => switch (method) {
        null => e.summary,
        TrainingMethod.zirkel => '${e.reps ?? 10} pro Runde',
        _ => method!.label,
      };

  bool repeatsOn(DateTime day) => repeatWeekdays.contains(day.weekday);

  Map<String, dynamic> toMap() => {
        'id': id,
        'userid': userid,
        'name': name,
        'notes': notes,
        'repeatWeekdays': jsonEncode(repeatWeekdays),
        'method': method?.dbValue,
      };

  static List<int> parseWeekdays(Object? raw) {
    try {
      return (jsonDecode(raw as String? ?? '[]') as List).cast<int>();
    } catch (_) {
      return const [];
    }
  }
}

enum PlanStatus {
  planned('planned'),
  done('done'),
  skipped('skipped');

  const PlanStatus(this.dbValue);
  final String dbValue;

  static PlanStatus fromDb(Object? v) => values.firstWhere((s) => s.dbValue == v, orElse: () => planned);
}

/// Ein Workout an einem Tag – entweder ausdrücklich eingeplant ([id] gesetzt) oder aus
/// der Wochenwiederholung abgeleitet ([id] null, wird beim Starten/Überspringen gespeichert).
class PlanEntry {
  final int? id;
  final DateTime date;
  final Workout workout;
  final PlanStatus status;
  final int? sessionId;

  const PlanEntry({this.id, required this.date, required this.workout, this.status = PlanStatus.planned, this.sessionId});

  bool get isFromRepeat => id == null;
}

/// Ein protokollierter Satz.
class SessionSet {
  final int? id;
  final Exercise exercise;
  final int setIndex;
  final int? reps;
  final int? durationSec;
  final double? distanceKm;
  final bool done;

  const SessionSet({
    this.id,
    required this.exercise,
    required this.setIndex,
    this.reps,
    this.durationSec,
    this.distanceKm,
    this.done = false,
  });

  num? get value => switch (exercise.metric) {
        ExerciseMetric.reps => reps,
        ExerciseMetric.time => durationSec,
        ExerciseMetric.distance => distanceKm,
      };

  SessionSet withValue(num? v, {bool? done}) => SessionSet(
        id: id,
        exercise: exercise,
        setIndex: setIndex,
        reps: exercise.metric == ExerciseMetric.reps ? v?.round() : reps,
        durationSec: exercise.metric == ExerciseMetric.time ? v?.round() : durationSec,
        distanceKm: exercise.metric == ExerciseMetric.distance ? v?.toDouble() : distanceKm,
        done: done ?? this.done,
      );
}

class WorkoutSession {
  final int id;
  final int? plannedId;
  final String name;
  final DateTime date;
  final int? durationMin;
  final String? notes;
  final List<SessionSet> sets;

  const WorkoutSession({
    required this.id,
    this.plannedId,
    required this.name,
    required this.date,
    this.durationMin,
    this.notes,
    this.sets = const [],
  });
}

/// Fortschritt einer Übung: Bestwert je Einheit (für den Verlauf) und insgesamt.
class ExerciseProgress {
  final Exercise exercise;
  final List<(DateTime, num)> bestPerSession;
  const ExerciseProgress(this.exercise, this.bestPerSession);

  num? get best => bestPerSession.isEmpty
      ? null
      : bestPerSession.map((e) => e.$2).reduce((a, b) => a > b ? a : b);
}

String formatValue(ExerciseMetric metric, num value) => switch (metric) {
      ExerciseMetric.reps => '${value.round()}',
      ExerciseMetric.time => value >= 60 ? '${value ~/ 60}:${(value % 60).round().toString().padLeft(2, '0')} min' : '${value.round()} s',
      ExerciseMetric.distance => '${value.toStringAsFixed(value == value.roundToDouble() ? 0 : 1).replaceAll('.', ',')} km',
    };

/// Wochentage kurz (1 = Mo).
const weekdayShort = ['Mo', 'Di', 'Mi', 'Do', 'Fr', 'Sa', 'So'];
