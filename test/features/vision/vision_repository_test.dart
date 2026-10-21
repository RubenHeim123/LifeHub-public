import 'package:flutter_test/flutter_test.dart';

import 'package:frontend/core/database/database.dart';
import 'package:frontend/features/auth/models/user.dart';
import 'package:frontend/features/calendar/models/appointment.dart';
import 'package:frontend/features/calendar/repositories/appointment_repository.dart';
import 'package:frontend/features/todos/models/todo.dart';
import 'package:frontend/features/todos/repositories/todo_repository.dart';
import 'package:frontend/features/vision/models/vision.dart';
import 'package:frontend/features/vision/repositories/vision_repository.dart';

import '../../helpers/test_app.dart';

void main() {
  late DatabaseService db;
  late VisionRepository vision;
  late TodoRepository todos;
  late UserModel user;

  setUp(() async {
    db = createTestDatabase();
    vision = VisionRepository(db: db);
    todos = TodoRepository(db: db);
    user = await createTestUser(db);
  });
  tearDown(() => db.close());

  Future<int> goalWithSteps(List<String> steps) async {
    final areaId = await vision.createArea(VisionArea(userid: user.uid, title: 'Bereich'));
    final goalId = await vision.createGoal(VisionGoal(areaId: areaId, userid: user.uid, title: 'Ziel'));
    for (final s in steps) {
      await vision.createStep(GoalStep(goalId: goalId, userid: user.uid, title: s));
    }
    return goalId;
  }

  group('deriveStepStates', () {
    GoalStep s(bool done) => GoalStep(goalId: 1, userid: 1, title: '', isDone: done);

    test('steps unlock one after another', () {
      expect(deriveStepStates([s(false), s(false), s(false)]), [PlanStepState.active, PlanStepState.locked, PlanStepState.locked]);
      expect(deriveStepStates([s(true), s(false), s(false)]), [PlanStepState.done, PlanStepState.active, PlanStepState.locked]);
      expect(deriveStepStates([s(true), s(true)]), [PlanStepState.done, PlanStepState.done]);
      expect(deriveStepStates([]), isEmpty);
    });
  });

  group('board', () {
    test('template creates all areas and goals in order', () async {
      await vision.createTemplateBoard(user.uid);

      final board = await vision.getBoard(user.uid);
      expect(board, hasLength(visionBoardTemplate.length));
      expect(board.expand((a) => a.goals), hasLength(visionBoardTemplate.expand((t) => t.$4).length));
      for (final (i, (title, _, _, goals)) in visionBoardTemplate.indexed) {
        expect(board[i].area.title, title);
        expect(board[i].goals.map((g) => (g.goal.title, g.goal.note)), goals);
      }
    });

    test('counts achieved goals per area and plan progress per goal', () async {
      final goalId = await goalWithSteps(['A', 'B']);
      final plan = await vision.getPlan(goalId);
      await vision.setStepDone(plan.steps.first.step.id!, true);
      await vision.setGoalAchieved(goalId, true);

      final area = (await vision.getBoard(user.uid)).single;
      expect(area.achieved, 1);
      expect(area.goals.single.stepsDone, 1);
      expect(area.goals.single.stepsTotal, 2);
    });

    test('board only shows the user\'s own areas', () async {
      final other = await createTestUser(db, email: 'other@test.de');
      await vision.createArea(VisionArea(userid: other.uid, title: 'Fremd'));
      expect(await vision.getBoard(user.uid), isEmpty);
    });
  });

  group('plan', () {
    test('todos and appointments of a step appear in the plan and gate completion', () async {
      final goalId = await goalWithSteps(['Businessplan', 'Gründung']);
      var plan = await vision.getPlan(goalId);
      final first = plan.steps.first.step;

      await todos.createTodo(Todo(title: 'Markt analysieren', userid: user.uid, goalStepId: first.id));
      await AppointmentRepository(db: db).createAppointment(
          Appointment(title: 'Termin Steuerberater', date: DateTime(2027, 2, 1, 10), userid: user.uid, goalStepId: first.id));

      plan = await vision.getPlan(goalId);
      expect(plan.steps.first.todos.single.title, 'Markt analysieren');
      expect(plan.steps.first.appointments.single.title, 'Termin Steuerberater');
      expect(plan.steps.first.canComplete, isFalse);
      expect(plan.steps.first.blockedReason, '1 To-Do offen');
      expect(plan.steps.last.state, PlanStepState.locked);
      expect(plan.steps.last.blockedReason, 'Erst den vorherigen Schritt abschließen');

      // To-Do in der normalen To-Do-Liste erledigen → Schritt kann abgeschlossen werden
      await todos.updateTodo(plan.steps.first.todos.single.copyWith(isCompleted: true));
      plan = await vision.getPlan(goalId);
      expect(plan.steps.first.canComplete, isTrue);

      await vision.setStepDone(first.id!, true);
      plan = await vision.getPlan(goalId);
      expect(plan.steps.last.state, PlanStepState.active);
      expect(plan.progress, 0.5);
    });

    test('linking an existing todo and listing unlinked ones', () async {
      final goalId = await goalWithSteps(['A']);
      final stepId = (await vision.getPlan(goalId)).steps.single.step.id!;
      await todos.createTodo(Todo(title: 'Lose Aufgabe', userid: user.uid));
      final todo = (await vision.unlinkedOpenTodos(user.uid)).single;

      await vision.linkTodo(todo.id!, stepId);

      expect(await vision.unlinkedOpenTodos(user.uid), isEmpty);
      expect((await vision.getPlan(goalId)).steps.single.todos.single.title, 'Lose Aufgabe');
      expect(await vision.goalTitlesForSteps(user.uid), {stepId: 'Ziel'});
    });

    test('moveStep reorders steps', () async {
      final goalId = await goalWithSteps(['A', 'B', 'C']);
      final c = (await vision.getPlan(goalId)).steps.last.step;

      await vision.moveStep(goalId, c.id!, -1);

      expect((await vision.getPlan(goalId)).steps.map((s) => s.step.title), ['A', 'C', 'B']);
    });

    test('deleting a goal removes its steps but keeps the todos (unlinked)', () async {
      final goalId = await goalWithSteps(['A']);
      final stepId = (await vision.getPlan(goalId)).steps.single.step.id!;
      await todos.createTodo(Todo(title: 'Bleibt', userid: user.uid, goalStepId: stepId));

      await vision.deleteGoal(goalId);

      expect((await vision.getBoard(user.uid)).single.goals, isEmpty);
      final remaining = await todos.getAllTodos(user.uid);
      expect(remaining.single.title, 'Bleibt');
      expect(remaining.single.goalStepId, isNull);
    });

    test('undo after deleting an area brings back goals, steps and todo links', () async {
      final goalId = await goalWithSteps(['A', 'B']);
      final plan = await vision.getPlan(goalId);
      final stepId = plan.steps.first.step.id!;
      await todos.createTodo(Todo(title: 'Verknüpft', userid: user.uid, goalStepId: stepId));
      final areaId = plan.goal.areaId;
      // vorher schon gelöschter Schritt bleibt gelöscht
      final old = await vision.deleteStep(plan.steps.last.step.id!);
      expect(old.links, isEmpty);

      final deletion = await vision.deleteArea(areaId);
      expect(await vision.getBoard(user.uid), isEmpty);
      expect((await todos.getAllTodos(user.uid)).single.goalStepId, isNull);
      expect(deletion.links, [('todos', (await todos.getAllTodos(user.uid)).single.id!, stepId)]);

      await vision.restoreDeletion(deletion);
      final board = await vision.getBoard(user.uid);
      expect(board.single.goals.single.goal.id, goalId);
      expect((await vision.getPlan(goalId)).steps.map((s) => s.step.title), ['A']);
      expect((await todos.getAllTodos(user.uid)).single.goalStepId, stepId);
    });

    test('toggling a linked todo keeps its link', () async {
      final goalId = await goalWithSteps(['A']);
      final stepId = (await vision.getPlan(goalId)).steps.single.step.id!;
      await todos.createTodo(Todo(title: 'X', userid: user.uid, goalStepId: stepId));
      final todo = (await todos.getAllTodos(user.uid)).single;

      await todos.updateTodo(todo.copyWith(isCompleted: true));

      expect((await todos.getAllTodos(user.uid)).single.goalStepId, stepId);
    });
  });
}
