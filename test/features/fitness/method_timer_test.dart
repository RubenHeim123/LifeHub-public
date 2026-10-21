import 'package:flutter_test/flutter_test.dart';

import 'package:frontend/features/fitness/models/method_timer.dart';
import 'package:frontend/features/fitness/models/workout.dart';

void main() {
  const pushups = Exercise(id: 1, userid: 1, name: 'Liegestütz');
  const rows = Exercise(id: 2, userid: 1, name: 'Türziehen');
  const plank = Exercise(id: 3, userid: 1, name: 'Planke', metric: ExerciseMetric.time);
  const squats = Exercise(id: 4, userid: 1, name: 'Kniebeuge');

  Workout workout(TrainingMethod method, List<Exercise> exercises, {int? reps}) => Workout(
        userid: 1,
        name: 'Test',
        method: method,
        exercises: [for (final e in exercises) WorkoutExercise(exercise: e, sets: 1, reps: reps)],
      );

  const s = Duration(seconds: 1);
  Duration secs(int n) => Duration(seconds: n);

  group('Stufenintervall', () {
    test('ladder up, rest as long as the work, failure counts and goes down, 7:30 per exercise', () {
      final t = MethodTimer.forWorkout(workout(TrainingMethod.stufen, [pushups, rows])) as StufenTimer;
      expect(t.clock, TrainingMethod.stufenBlock);

      t.tick(secs(3)); // Stufe 1 dauert 3 s → 3 s Pause
      t.stepDone();
      expect(t.phase, TimerPhase.rest);
      expect(t.restLeft, secs(3));
      expect(t.step, 2);
      t.tick(secs(3));
      expect(t.phase, TimerPhase.work);

      t.stepDone(); // sofort geschafft → Mindestpause 1 s
      expect(t.restLeft, secs(1));
      t.tick(secs(1));

      t.tick(secs(10)); // Stufe 3 mit Muskelversagen: zählt, Pause startet sofort
      t.muscleFailure();
      expect(t.phase, TimerPhase.rest);
      expect(t.restLeft, secs(10));
      expect(t.totalReps, 6);
      expect(t.highestStep, 3);
      expect(t.step, 2); // danach die nächstniedrigere Stufe
      expect(t.ascending, isFalse);
      t.tick(secs(10));

      t.tick(secs(4));
      t.stepDone();
      expect(t.step, 1);
      expect(t.totalReps, 8);
      t.tick(secs(4));
      t.stepDone(); // Stufe 1 abwärts → beginnt wieder aufwärts
      expect(t.step, 1);
      expect(t.ascending, isTrue);
      expect(t.totalReps, 9);

      // Block läuft während der Pause ab → nach der Pause die nächste Übung
      t.tick(t.blockLeft);
      expect(t.groupIndex, 1);
      expect(t.log.single.exercise.name, 'Liegestütz');
      expect(t.log.single.value, 9);
      expect(t.step, 1);

      // Letzte Übung: der laufende Satz wird nach 7:30 noch zu Ende gebracht, dann ist Schluss
      t.tick(TrainingMethod.stufenBlock + secs(5));
      expect(t.finished, isFalse);
      expect(t.overtime, isTrue);
      expect(t.clock, secs(5));
      t.stepDone();
      expect(t.finished, isTrue);
    });

    test('a set started before 7:30 is finished; rest as long as the set, then the next exercise', () {
      final t = MethodTimer.forWorkout(workout(TrainingMethod.stufen, [pushups, rows])) as StufenTimer;
      t.tick(secs(218)); // Stufe 1: 3:38
      t.stepDone(); // 3:38 Pause → Stufe 2 beginnt bei 7:16
      t.tick(secs(218));
      expect(t.phase, TimerPhase.work);
      expect(t.clock, secs(14)); // noch 0:14 bis 7:30

      t.tick(secs(49)); // Satz endet bei 8:05 – keine Unterbrechung bei 7:30
      expect(t.groupIndex, 0);
      expect(t.overtime, isTrue);
      expect(t.clock, secs(35)); // „+0:35“
      expect(t.headline, contains('noch zu Ende'));
      expect(t.upNext, isNull);

      t.stepDone(); // Pause = Satzdauer 49 s, danach Türziehen
      expect(t.phase, TimerPhase.rest);
      expect(t.restLeft, secs(49));
      expect(t.upNext!.single.exercise.name, 'Türziehen');
      expect(t.headline, 'Pause – danach: Türziehen');
      t.tick(secs(48));
      expect(t.groupIndex, 0);
      t.tick(secs(1));
      expect(t.groupIndex, 1);
      expect(t.phase, TimerPhase.work);
      expect(t.clock, TrainingMethod.stufenBlock);
      expect(t.log.single.value, 3); // Stufe 1 + 2
    });

    test('if 7:30 ends during a rest, no new set starts', () {
      final t = MethodTimer.forWorkout(workout(TrainingMethod.stufen, [pushups, rows])) as StufenTimer;
      t.tick(secs(400));
      t.stepDone(); // 400 s Pause reicht über 7:30 hinaus
      t.tick(secs(60));
      expect(t.phase, TimerPhase.rest);
      expect(t.upNext!.single.exercise.name, 'Türziehen');
      t.tick(secs(340));
      expect(t.groupIndex, 1);
      expect(t.step, 1);
    });

    test('time exercises log the seconds worked', () {
      final t = MethodTimer.forWorkout(workout(TrainingMethod.stufen, [plank])) as StufenTimer;
      t.tick(secs(20));
      t.stepDone();
      t.finish();
      expect(t.log.single.value, 20);
    });
  });

  group('Intervallsatz', () {
    test('three sets per exercise, a new set every 3 minutes', () {
      final t = MethodTimer.forWorkout(workout(TrainingMethod.intervall, [pushups, rows])) as IntervalTimer;
      expect(t.headline, 'Satz 1 von 3');
      t.tick(secs(40));
      t.logRound([10]);
      expect(t.phase, TimerPhase.rest);
      t.tick(const Duration(minutes: 3) - secs(40));
      expect(t.phase, TimerPhase.work);
      expect(t.headline, 'Satz 2 von 3');
      expect(t.clock, const Duration(minutes: 3));

      t.logRound([9]);
      t.tick(const Duration(minutes: 3));
      t.logRound([8]);
      t.tick(const Duration(minutes: 3));
      expect(t.current.single.exercise.name, 'Türziehen');
      expect(t.log.map((l) => l.value), [10, 9, 8]);
      expect(t.log.map((l) => l.setIndex), [0, 1, 2]);

      for (var i = 0; i < 3; i++) {
        t.logRound([7]);
        if (!t.finished) t.tick(const Duration(minutes: 3));
      }
      expect(t.finished, isTrue);
      expect(t.log, hasLength(6));
    });

    test('a missed set is skipped when the interval ends', () {
      final t = MethodTimer.forWorkout(workout(TrainingMethod.intervall, [pushups])) as IntervalTimer;
      t.tick(const Duration(minutes: 3));
      expect(t.round, 1);
      expect(t.log, isEmpty);
    });
  });

  test('Supersatz: pairs, two rounds every 4 minutes, values for both exercises', () {
    final t = MethodTimer.forWorkout(workout(TrainingMethod.supersatz, [pushups, rows, squats, plank])) as IntervalTimer;
    expect(t.groups, hasLength(2));
    expect(t.current.map((e) => e.exercise.name), ['Liegestütz', 'Türziehen']);
    expect(t.headline, 'Supersatz 1 von 2');
    t.logRound([4, 10]);
    t.tick(const Duration(minutes: 4));
    t.logRound([3, 9]);
    t.tick(const Duration(minutes: 4));
    expect(t.current.map((e) => e.exercise.name), ['Kniebeuge', 'Planke']);
    expect(t.log.map((l) => '${l.exercise.name}:${l.value}'), ['Liegestütz:4', 'Türziehen:10', 'Liegestütz:3', 'Türziehen:9']);
  });

  test('Zirkel: 20 minutes, rounds times reps per round', () {
    final t = MethodTimer.forWorkout(workout(TrainingMethod.zirkel, [pushups, squats], reps: 6)) as ZirkelTimer;
    expect(t.clock, const Duration(minutes: 20));
    t.roundDone();
    t.roundDone();
    t.roundDone();
    t.tick(const Duration(minutes: 20));
    expect(t.finished, isTrue);
    expect(t.log.map((l) => l.value), [18, 18]);
  });

  test('Hochintensität: 8 × 20 s / 10 s, 60 s change with preview, no reps – only time is logged', () {
    final t = MethodTimer.forWorkout(workout(TrainingMethod.hochintensiv, [plank, squats])) as HochTimer;
    expect(t.clock, secs(20));
    t.tick(secs(20));
    expect(t.phase, TimerPhase.rest);
    expect(t.upNext, isNull);
    t.tick(secs(10));
    expect(t.phase, TimerPhase.work);
    expect(t.round, 1);

    // restliche 7 Runden: 6 × (20 + 10) + 20
    for (var i = 0; i < 6 * 30 + 20; i++) {
      t.tick(s);
    }
    expect(t.phase, TimerPhase.change);
    expect(t.upNext!.single.exercise.name, 'Kniebeuge');
    expect(t.headline, 'Wechsel – gleich: Kniebeuge');
    expect(t.log.single.value, 160); // 8 × 20 s Planke
    t.tick(secs(60));
    expect(t.phase, TimerPhase.work);
    expect(t.groupIndex, 1);
    t.tick(secs(8 * 30));
    expect(t.finished, isTrue);
    expect(t.log, hasLength(1)); // Kniebeugen (Wiederholungen) werden nicht gezählt
  });

  test('cues count phase changes and skip moves to the next exercise', () {
    final t = MethodTimer.forWorkout(workout(TrainingMethod.intervall, [pushups, rows]));
    final before = t.cues;
    t.skip();
    expect(t.groupIndex, 1);
    expect(t.cues, greaterThan(before));
    t.skip();
    expect(t.finished, isTrue);
  });

  test('supersets pair exercises and the workout shows targets per method', () {
    final w = workout(TrainingMethod.zirkel, [pushups], reps: 8);
    expect(w.targetOf(w.exercises.first), '8 pro Runde');
    final free = Workout(userid: 1, name: 'x', exercises: const [WorkoutExercise(exercise: pushups, sets: 3, reps: 12)]);
    expect(free.targetOf(free.exercises.first), '3 × 12');
    expect(workout(TrainingMethod.supersatz, [pushups, rows, squats]).groups.map((g) => g.length), [2, 1]);
  });
}
