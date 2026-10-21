import 'package:frontend/features/calendar/models/appointment.dart';
import 'package:frontend/features/todos/models/todo.dart';

/// Bereich des Vision Boards, z. B. "Scale & Enterprise".
class VisionArea {
  final int? id;
  final int userid;
  final String title;
  final String? imagePath;
  final int colorValue;
  final int position;

  const VisionArea({
    this.id,
    required this.userid,
    required this.title,
    this.imagePath,
    this.colorValue = 0xFF5ED99E,
    this.position = 0,
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'userid': userid,
        'title': title,
        'imagePath': imagePath,
        'colorValue': colorValue,
        'position': position,
      };

  factory VisionArea.fromMap(Map<String, dynamic> m) => VisionArea(
        id: m['id'],
        userid: m['userid'],
        title: m['title'],
        imagePath: m['imagePath'],
        colorValue: (m['colorValue'] as int?) ?? 0xFF5ED99E,
        position: (m['position'] as int?) ?? 0,
      );
}

/// Konkretes Ziel innerhalb eines Bereichs.
class VisionGoal {
  final int? id;
  final int areaId;
  final int userid;
  final String title;

  /// Zusatz wie "(21,1 km)".
  final String? note;
  final bool isAchieved;
  final int position;

  const VisionGoal({
    this.id,
    required this.areaId,
    required this.userid,
    required this.title,
    this.note,
    this.isAchieved = false,
    this.position = 0,
  });

  VisionGoal copyWith({String? title, String? note, bool? isAchieved}) => VisionGoal(
        id: id,
        areaId: areaId,
        userid: userid,
        title: title ?? this.title,
        note: note ?? this.note,
        isAchieved: isAchieved ?? this.isAchieved,
        position: position,
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'areaId': areaId,
        'userid': userid,
        'title': title,
        'note': note,
        'isAchieved': isAchieved ? 1 : 0,
        'position': position,
      };

  factory VisionGoal.fromMap(Map<String, dynamic> m) => VisionGoal(
        id: m['id'],
        areaId: m['areaId'],
        userid: m['userid'],
        title: m['title'],
        note: m['note'],
        isAchieved: m['isAchieved'] == 1,
        position: (m['position'] as int?) ?? 0,
      );
}

/// Ein Schritt im Plan eines Ziels.
class GoalStep {
  final int? id;
  final int goalId;
  final int userid;
  final String title;
  final String? description;
  final bool isDone;
  final int position;

  const GoalStep({
    this.id,
    required this.goalId,
    required this.userid,
    required this.title,
    this.description,
    this.isDone = false,
    this.position = 0,
  });

  GoalStep copyWith({String? title, String? description, bool? isDone}) => GoalStep(
        id: id,
        goalId: goalId,
        userid: userid,
        title: title ?? this.title,
        description: description ?? this.description,
        isDone: isDone ?? this.isDone,
        position: position,
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'goalId': goalId,
        'userid': userid,
        'title': title,
        'description': description,
        'isDone': isDone ? 1 : 0,
        'position': position,
      };

  factory GoalStep.fromMap(Map<String, dynamic> m) => GoalStep(
        id: m['id'],
        goalId: m['goalId'],
        userid: m['userid'],
        title: m['title'],
        description: m['description'],
        isDone: m['isDone'] == 1,
        position: (m['position'] as int?) ?? 0,
      );
}

// ─── Lese-Modelle ──────────────────────────────────────────────────────

/// Ziel mit Plan-Fortschritt für die Board-Übersicht.
class GoalSummary {
  final VisionGoal goal;
  final int stepsDone;
  final int stepsTotal;
  const GoalSummary(this.goal, this.stepsDone, this.stepsTotal);
}

class AreaWithGoals {
  final VisionArea area;
  final List<GoalSummary> goals;
  const AreaWithGoals(this.area, this.goals);

  int get achieved => goals.where((g) => g.goal.isAchieved).length;
}

/// Zustand eines Schritts im Plan.
enum PlanStepState {
  /// Erledigt.
  done,

  /// Der aktuelle Schritt: vorherige sind erledigt.
  active,

  /// Wartet auf einen vorherigen Schritt.
  locked,
}

/// Schritt mit verknüpften To-Dos und Terminen und abgeleitetem Zustand.
class PlanStep {
  final GoalStep step;
  final List<Todo> todos;
  final List<Appointment> appointments;
  final PlanStepState state;

  const PlanStep(this.step, this.todos, this.appointments, this.state);

  int get openTodos => todos.where((t) => !t.isCompleted).length;

  /// Ein Schritt kann erst abgeschlossen werden, wenn er dran ist und alle
  /// verknüpften To-Dos erledigt sind.
  bool get canComplete => state == PlanStepState.active && openTodos == 0;

  /// Warum der Schritt (noch) nicht abgeschlossen werden kann – oder `null`.
  String? get blockedReason {
    if (state == PlanStepState.locked) return 'Erst den vorherigen Schritt abschließen';
    if (state == PlanStepState.active && openTodos > 0) {
      return openTodos == 1 ? '1 To-Do offen' : '$openTodos To-Dos offen';
    }
    return null;
  }
}

class GoalPlan {
  final VisionGoal goal;
  final VisionArea area;
  final List<PlanStep> steps;
  const GoalPlan(this.goal, this.area, this.steps);

  int get stepsDone => steps.where((s) => s.step.isDone).length;
  double get progress => steps.isEmpty ? 0 : stepsDone / steps.length;
}

/// Leitet die Zustände der Schritte ab: Schritte werden der Reihe nach
/// freigeschaltet – ein Schritt ist erst dran, wenn alle vorherigen erledigt sind.
List<PlanStepState> deriveStepStates(List<GoalStep> stepsInOrder) {
  var previousDone = true;
  return [
    for (final s in stepsInOrder)
      () {
        final state = s.isDone ? PlanStepState.done : (previousDone ? PlanStepState.active : PlanStepState.locked);
        previousDone = previousDone && s.isDone;
        return state;
      }(),
  ];
}
