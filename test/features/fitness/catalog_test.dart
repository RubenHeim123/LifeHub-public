import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:frontend/features/fitness/catalog/exercise_howto.dart';
import 'package:frontend/core/database/database.dart';
import 'package:frontend/core/ui/theme.dart';
import 'package:frontend/features/auth/models/user.dart';
import 'package:frontend/features/fitness/catalog/exercise_catalog.dart';
import 'package:frontend/features/fitness/catalog/exercise_motion.dart';
import 'package:frontend/features/fitness/catalog/sample_plans.dart';
import 'package:frontend/features/fitness/models/workout.dart';
import 'package:frontend/features/fitness/repositories/workout_repository.dart';

import '../../helpers/test_app.dart';

void main() {
  group('catalog data', () {
    test('keys are unique and every exercise has a motion and a description', () {
      final keys = exerciseCatalog.map((e) => e.key).toList();
      expect(keys.toSet(), hasLength(keys.length));
      expect(exerciseCatalog.length, greaterThanOrEqualTo(110));
      for (final e in exerciseCatalog) {
        expect(motions.containsKey(e.motion), isTrue, reason: '${e.key}: ${e.motion}');
        // Die öffentliche Version kommt ohne Anleitungstexte aus
        if (exerciseHowTo.isNotEmpty) expect(e.howTo.length, greaterThan(20), reason: e.key);
        expect(e.minLevel, inInclusiveRange(1, 4), reason: e.key);
      }
    });

    test('how-to texts only exist for catalog exercises', () {
      final keys = exerciseCatalog.map((e) => e.key).toSet();
      expect(exerciseHowTo.keys.where((k) => !keys.contains(k)), isEmpty);
    });

    test('every category has exercises', () {
      for (final cat in CatalogCategory.values) {
        expect(exerciseCatalog.where((e) => e.category == cat), isNotEmpty, reason: cat.label);
      }
    });

    test('motions interpolate without leaving the drawing area', () {
      for (final entry in motions.entries) {
        for (var i = 0; i <= 20; i++) {
          final pose = entry.value.at(i / 20);
          expect(pose.points, hasLength(11));
          for (final p in pose.points) {
            expect(p.dx, inInclusiveRange(-2, 102), reason: entry.key);
            expect(p.dy, inInclusiveRange(-12, 100), reason: entry.key);
          }
        }
      }
    });

    test('sample plans only reference catalog exercises', () {
      expect(samplePlans.map((p) => p.name), ['Basisprogramm', 'First Class', 'Master Class', 'Chief Class']);
      for (final plan in samplePlans) {
        expect(plan.blocks, isNotEmpty);
        for (final block in plan.blocks) {
          expect(block.days.length, inInclusiveRange(4, 5), reason: '${plan.name} ${block.title}');
          for (final day in block.days) {
            expect(day.items, isNotEmpty);
            for (final item in day.items) {
              expect(catalogByKey.containsKey(item.key), isTrue, reason: '${plan.name} ${block.title}: ${item.key}');
            }
            if (day.method == TrainingMethod.supersatz) {
              expect(day.groups.every((g) => g.length == 2), isTrue, reason: '${plan.name} ${block.title} ${day.title}');
            }
          }
        }
      }
    });
  });

  group('repository', () {
    late DatabaseService db;
    late WorkoutRepository repo;
    late UserModel user;

    setUp(() async {
      db = createTestDatabase();
      repo = WorkoutRepository(db: db);
      user = await createTestUser(db);
    });
    tearDown(() => db.close());

    test('adding from the catalog is idempotent and keeps the link', () async {
      final first = await repo.addFromCatalog(user.uid, 'planke');
      final again = await repo.addFromCatalog(user.uid, 'planke');
      expect(again.id, first.id);
      expect(first.catalogKey, 'planke');
      expect(first.metric, ExerciseMetric.time);
      expect(first.catalog!.name, 'Planke');
      expect(await repo.getExercises(user.uid), hasLength(1));
    });

    test('an own exercise with the same name is reused', () async {
      await repo.saveExercise(Exercise(userid: user.uid, name: 'Kniebeuge'));
      final e = await repo.addFromCatalog(user.uid, 'kniebeuge');
      expect(e.catalogKey, isNull);
      expect(await repo.getExercises(user.uid), hasLength(1));
    });

    test('importing a block creates one workout per day with weekly repeats', () async {
      final plan = samplePlanByKey('basis')!;
      final block = plan.blocks.first;
      final ids = await repo.importSampleBlock(user.uid, plan, block, weekdays: [1, 2, 4, 5]);
      expect(ids, hasLength(4));

      final workouts = await repo.getWorkouts(user.uid);
      final day1 = workouts.firstWhere((w) => w.id == ids.first);
      expect(day1.name, 'Basisprogramm Woche 1–2 · Tag 1 Drücken/Ziehen');
      expect(day1.repeatWeekdays, [1]);
      expect(day1.exercises.map((e) => e.exercise.catalogKey),
          ['liegestuetz', 'tuerziehen', 'trizepsdip_stuhl', 'umgekehrtes_bankdruecken']);
      expect(day1.method, TrainingMethod.stufen);
      expect(day1.notes, contains('Liegestütz – Hände erhöht'));

      // Übungen werden nur einmal in die Bibliothek übernommen
      final names = (await repo.getExercises(user.uid)).map((e) => e.name).toList();
      expect(names.toSet(), hasLength(names.length));
    });

    test('imported workouts carry the training method instead of fixed sets and reps', () async {
      final plan = samplePlanByKey('first_class')!;
      final power = plan.blocks.firstWhere((b) => b.title == 'Woche 5–6');
      final push = (await repo.getWorkout((await repo.importSampleBlock(user.uid, plan, power)).first))!;
      expect(push.repeatWeekdays, isEmpty);
      expect(push.method, TrainingMethod.supersatz);
      expect(push.groups, hasLength(3));
      expect(push.groups.first.map((e) => e.exercise.catalogKey), ['liegestuetz', 'liegestuetz_abstossen']);

      final w7 = plan.blocks.firstWhere((b) => b.title == 'Woche 7');
      final circuit = (await repo.getWorkout((await repo.importSampleBlock(user.uid, plan, w7)).last))!;
      expect(circuit.method, TrainingMethod.zirkel);
      expect(circuit.exercises.map((e) => e.reps), [6, 12, 8]);
    });
  });

  testWidgets('animation renders animated and as still image', (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: ThemeData(extensions: const [AppColors.light]),
      home: const Scaffold(body: Column(children: [
        ExerciseAnimation(motion: 'pushup', size: 120),
        ExerciseAnimation(motion: 'burpee', size: 60, animate: false),
        ExerciseAnimation(motion: 'unbekannt', size: 60),
      ])),
    ));
    await tester.pump(const Duration(milliseconds: 400));
    expect(tester.takeException(), isNull);
    expect(find.byType(ExerciseAnimation), findsNWidgets(3));
  });
}
