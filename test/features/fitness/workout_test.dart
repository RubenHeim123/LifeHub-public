import 'package:flutter_test/flutter_test.dart';

import 'package:frontend/core/database/database.dart';
import 'package:frontend/features/auth/models/user.dart';
import 'package:frontend/features/fitness/models/workout.dart';
import 'package:frontend/features/fitness/repositories/workout_repository.dart';

import '../../helpers/test_app.dart';

void main() {
  late DatabaseService db;
  late WorkoutRepository repo;
  late UserModel user;

  // Montag, 28.09.2026
  final monday = DateTime(2026, 9, 28);

  setUp(() async {
    db = createTestDatabase();
    repo = WorkoutRepository(db: db);
    user = await createTestUser(db);
  });
  tearDown(() => db.close());

  Future<Exercise> exercise(String name, {ExerciseMetric metric = ExerciseMetric.reps}) async {
    final id = await repo.saveExercise(Exercise(userid: user.uid, name: name, metric: metric));
    return (await repo.getExercises(user.uid)).firstWhere((e) => e.id == id);
  }

  Future<Workout> pushDay({List<int> repeat = const []}) async {
    final pushups = await exercise('Liegestütze');
    final plank = await exercise('Plank', metric: ExerciseMetric.time);
    final id = await repo.saveWorkout(Workout(
      userid: user.uid,
      name: 'Push',
      repeatWeekdays: repeat,
      exercises: [
        WorkoutExercise(exercise: pushups, sets: 3, reps: 15),
        WorkoutExercise(exercise: plank, sets: 2, durationSec: 60),
      ],
    ));
    return (await repo.getWorkout(id))!;
  }

  test('starter exercises are created once', () async {
    await repo.createStarterExercises(user.uid);
    await repo.createStarterExercises(user.uid);
    final names = (await repo.getExercises(user.uid)).map((e) => e.name);
    expect(names, contains('Human-Flag-Progression'));
    expect(names.where((n) => n == 'Liegestütze'), hasLength(1));
  });

  test('workouts keep exercise order and targets; saving replaces the list', () async {
    final w = await pushDay();
    expect(w.exercises.map((e) => e.exercise.name), ['Liegestütze', 'Plank']);
    expect(w.exercises.first.summary, '3 × 15');

    await repo.saveWorkout(Workout(
      id: w.id,
      userid: user.uid,
      name: 'Push kurz',
      exercises: [w.exercises.last],
    ));
    final updated = (await repo.getWorkout(w.id!))!;
    expect(updated.name, 'Push kurz');
    expect(updated.exercises.single.exercise.name, 'Plank');
  });

  test('plan combines explicit entries and weekly repeats without duplicates', () async {
    final w = await pushDay(repeat: [DateTime.monday, DateTime.thursday]);
    await repo.planWorkout(user.uid, w.id!, monday); // gleiches Workout am Montag ausdrücklich
    await repo.planWorkout(user.uid, w.id!, DateTime(2026, 9, 30)); // Mittwoch zusätzlich

    final plan = await repo.getPlan(user.uid, monday, DateTime(2026, 10, 4));
    expect(plan.keys.map((d) => d.weekday).toList()..sort(), [DateTime.monday, DateTime.wednesday, DateTime.thursday]);
    expect(plan[monday], hasLength(1));
    expect(plan[monday]!.single.isFromRepeat, isFalse);
    expect(plan[DateTime(2026, 10, 1)]!.single.isFromRepeat, isTrue);
  });

  test('a session is prefilled with targets and marks the plan as done', () async {
    final w = await pushDay(repeat: [DateTime.monday]);
    final entry = (await repo.getPlanForDay(user.uid, monday)).single;

    var session = await repo.startSession(user.uid, entry);
    expect(session.sets, hasLength(5)); // 3 × Liegestütze + 2 × Plank
    expect(session.sets.first.value, 15);

    await repo.updateSet(session.sets.first.withValue(18, done: true));
    await repo.updateSet(session.sets[1].withValue(12, done: true));
    session = (await repo.getSession(session.id))!;
    await repo.finishSession(session, durationMin: 35);

    final after = (await repo.getPlanForDay(user.uid, monday)).single;
    expect(after.status, PlanStatus.done);
    expect(after.sessionId, session.id);

    // Fortsetzen liefert dieselbe Einheit statt einer neuen
    expect((await repo.startSession(user.uid, after)).id, session.id);
    expect(w.id, isNotNull);
  });

  test('skipping a repeated workout stores it as skipped', () async {
    await pushDay(repeat: [DateTime.monday]);
    final entry = (await repo.getPlanForDay(user.uid, monday)).single;
    await repo.skip(user.uid, entry);

    final after = (await repo.getPlanForDay(user.uid, monday)).single;
    expect(after.status, PlanStatus.skipped);
    expect(after.isFromRepeat, isFalse);
  });

  test('progress takes the best done set per session', () async {
    final w = await pushDay();
    final pushups = w.exercises.first.exercise;
    for (final (day, values) in [
      (monday, [15, 17, 16]),
      (DateTime(2026, 10, 1), [18, 20, 19]),
    ]) {
      await repo.planWorkout(user.uid, w.id!, day);
      final entry = (await repo.getPlanForDay(user.uid, day)).single;
      final session = await repo.startSession(user.uid, entry);
      final sets = session.sets.where((s) => s.exercise.id == pushups.id).toList();
      for (var i = 0; i < sets.length; i++) {
        await repo.updateSet(sets[i].withValue(values[i], done: true));
      }
    }

    final progress = await repo.getProgress(pushups);
    expect(progress.bestPerSession.map((e) => e.$2), [17, 20]);
    expect(progress.best, 20);
  });

  test('formatValue', () {
    expect(formatValue(ExerciseMetric.time, 45), '45 s');
    expect(formatValue(ExerciseMetric.time, 90), '1:30 min');
    expect(formatValue(ExerciseMetric.distance, 21.1), '21,1 km');
    expect(formatValue(ExerciseMetric.reps, 12), '12');
  });
}
