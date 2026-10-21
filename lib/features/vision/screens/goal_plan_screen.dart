import 'package:flutter/material.dart';
import 'package:frontend/core/ui/modern_appbar.dart';
import 'package:frontend/core/ui/app_actions.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import 'package:frontend/core/ui/app_ui.dart';
import 'package:frontend/core/ui/dialogs.dart';
import 'package:frontend/core/ui/theme.dart';
import 'package:frontend/features/auth/models/user.dart';
import 'package:frontend/features/calendar/models/appointment.dart';
import 'package:frontend/features/calendar/screens/add_update_appointment_screen.dart';
import 'package:frontend/features/todos/models/todo.dart';
import 'package:frontend/features/todos/repositories/todo_repository.dart';
import 'package:frontend/features/todos/screens/add_update_todo_screen.dart';
import 'package:frontend/features/vision/models/vision.dart';
import 'package:frontend/features/vision/repositories/vision_repository.dart';

/// Schritt-für-Schritt-Plan eines Ziels. Schritte werden der Reihe nach
/// freigeschaltet; ein Schritt ist erst abschließbar, wenn seine To-Dos erledigt sind.
class GoalPlanScreen extends StatefulWidget {
  final UserModel user;
  final int goalId;
  const GoalPlanScreen({super.key, required this.user, required this.goalId});

  @override
  State<GoalPlanScreen> createState() => _GoalPlanScreenState();
}

class _GoalPlanScreenState extends State<GoalPlanScreen> {
  late final VisionRepository _repo = context.read<VisionRepository>();
  GoalPlan? _plan;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final plan = await _repo.getPlan(widget.goalId);
    if (mounted) setState(() => _plan = plan);
  }

  Future<void> _run(Future<void> Function() action) async {
    await action();
    await _load();
  }

  // ─── Ziel ──────────────────────────────────────────────────────────────

  Future<void> _editGoal() async {
    final goal = _plan!.goal;
    final values = await showTextFieldsDialog(context, title: 'Ziel bearbeiten', fields: [
      DialogField('Ziel', initial: goal.title, required: true),
      DialogField('Zusatz (z. B. Kennzahl)', initial: goal.note),
    ]);
    if (values == null) return;
    await _run(() => _repo.updateGoal(VisionGoal(
          id: goal.id,
          areaId: goal.areaId,
          userid: goal.userid,
          title: values[0]!,
          note: values[1],
          isAchieved: goal.isAchieved,
          position: goal.position,
        )));
  }

  /// Das Board löscht dann mit „Rückgängig“.
  void _deleteGoal() => Navigator.of(context).pop(kDeletedResult);

  // ─── Schritte ──────────────────────────────────────────────────────────

  Future<void> _addStep() async {
    final values = await showTextFieldsDialog(context, title: 'Neuer Schritt', fields: const [
      DialogField('Schritt', required: true),
      DialogField('Beschreibung'),
    ]);
    if (values == null) return;
    await _run(() => _repo.createStep(
        GoalStep(goalId: widget.goalId, userid: widget.user.uid, title: values[0]!, description: values[1])));
  }

  Future<void> _editStep(GoalStep step) async {
    final values = await showTextFieldsDialog(context, title: 'Schritt bearbeiten', fields: [
      DialogField('Schritt', initial: step.title, required: true),
      DialogField('Beschreibung', initial: step.description),
    ]);
    if (values == null) return;
    await _run(() => _repo.updateStep(GoalStep(
          id: step.id,
          goalId: step.goalId,
          userid: step.userid,
          title: values[0]!,
          description: values[1],
          isDone: step.isDone,
          position: step.position,
        )));
  }

  Future<void> _deleteStep(GoalStep step) {
    late VisionDeletion deletion;
    return deleteWithUndo(
      context,
      label: step.title,
      delete: () async => deletion = await _repo.deleteStep(step.id!),
      restore: () => _repo.restoreDeletion(deletion),
      onChanged: _load,
    );
  }

  Future<void> _addTodo(GoalStep step) async {
    await Navigator.push(context,
        MaterialPageRoute(builder: (_) => AddUpdateTodoScreen(userid: widget.user.uid, goalStepId: step.id)));
    _load();
  }

  Future<void> _addAppointment(GoalStep step) async {
    await Navigator.push(context,
        MaterialPageRoute(builder: (_) => AddUpdateAppointmentScreen(userid: widget.user.uid, goalStepId: step.id)));
    _load();
  }

  Future<void> _linkExistingTodo(GoalStep step) async {
    final open = await _repo.unlinkedOpenTodos(widget.user.uid);
    if (!mounted) return;
    final picked = await showModalBottomSheet<Todo>(
      context: context,
      builder: (context) => SafeArea(
        child: open.isEmpty
            ? const Padding(padding: EdgeInsets.all(24), child: Text('Keine offenen To-Dos ohne Ziel vorhanden.'))
            : ListView(shrinkWrap: true, children: [
                const ListTile(title: Text('To-Do verknüpfen', style: TextStyle(fontWeight: FontWeight.w600))),
                for (final t in open)
                  ListTile(
                    leading: const Icon(Icons.check_box_outline_blank_rounded),
                    title: Text(t.title),
                    subtitle: t.dueDate == null ? null : Text(DateFormat('dd.MM.yyyy').format(t.dueDate!)),
                    onTap: () => Navigator.pop(context, t),
                  ),
              ]),
      ),
    );
    if (picked != null) await _run(() => _repo.linkTodo(picked.id!, step.id));
  }

  Future<void> _toggleTodo(Todo todo) =>
      _run(() => context.read<TodoRepository>().setCompleted(todo, !todo.isCompleted));

  // ─── UI ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final plan = _plan;
    return Scaffold(
      appBar: ModernAppBar(
        title: 'Plan',
        customActions: [
          if (plan != null) ...[
            IconButton(tooltip: 'Ziel bearbeiten', icon: const Icon(Icons.edit_outlined), onPressed: _editGoal),
            IconButton(tooltip: 'Ziel löschen', icon: const Icon(Icons.delete_outline), onPressed: _deleteGoal),
          ],
        ],
      ),
      floatingActionButton: plan == null
          ? null
          : AppFab(label: 'Schritt', heroTag: 'step-fab', onPressed: _addStep),
      body: plan == null
          ? Center(child: CircularProgressIndicator(color: c.accent))
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 120),
                children: [
                  _goalHeader(context, plan),
                  const SizedBox(height: 20),
                  if (plan.steps.isEmpty)
                    AppCard(
                      child: Text(
                        'Noch keine Schritte. Zerlege das Ziel in Etappen – jede mit eigenen To-Dos und Terminen.',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    )
                  else
                    for (var i = 0; i < plan.steps.length; i++)
                      _stepTile(context, i, plan.steps[i], isLast: i == plan.steps.length - 1),
                ],
              ),
            ),
    );
  }

  Widget _goalHeader(BuildContext context, GoalPlan plan) {
    final c = AppColors.of(context);
    final t = Theme.of(context).textTheme;
    final goal = plan.goal;
    final allDone = plan.steps.isNotEmpty && plan.stepsDone == plan.steps.length;
    return AppCard(
      padding: const EdgeInsets.all(18),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('// ${plan.area.title.toUpperCase()}',
            style: TextStyle(fontFamily: 'monospace', fontSize: 11, letterSpacing: 1, color: Color(plan.area.colorValue))),
        const SizedBox(height: 8),
        Text(goal.title, style: t.headlineMedium),
        if (goal.note != null) ...[
          const SizedBox(height: 4),
          Text(goal.note!, style: TextStyle(fontFamily: 'monospace', fontSize: 12, color: c.muted)),
        ],
        const SizedBox(height: 16),
        Row(children: [
          Expanded(child: AppProgressBar(value: plan.progress)),
          const SizedBox(width: 12),
          Flexible(child: Text('${plan.stepsDone} von ${plan.steps.length} Schritten', style: t.labelMedium)),
        ]),
        const SizedBox(height: 12),
        InkWell(
          onTap: () => _run(() => _repo.setGoalAchieved(goal.id!, !goal.isAchieved)),
          child: Row(children: [
            AppCheck(checked: goal.isAchieved, size: 20),
            const SizedBox(width: 10),
            Flexible(child: Text(goal.isAchieved ? 'Ziel erreicht' : 'Als erreicht markieren', style: t.bodyMedium)),
          ]),
        ),
        if (allDone && !goal.isAchieved) ...[
          const SizedBox(height: 10),
          Text('Alle Schritte erledigt – Zeit, das Ziel abzuhaken.', style: t.bodySmall?.copyWith(color: c.positive)),
        ],
      ]),
    );
  }

  Widget _stepTile(BuildContext context, int index, PlanStep ps, {required bool isLast}) {
    final c = AppColors.of(context);
    final t = Theme.of(context).textTheme;
    final step = ps.step;
    final (badgeColor, badgeFg) = switch (ps.state) {
      PlanStepState.done => (c.positive, c.onAccent),
      PlanStepState.active => (c.accent, c.onAccent),
      PlanStepState.locked => (c.cardAlt, c.dim),
    };
    final locked = ps.state == PlanStepState.locked;

    return IntrinsicHeight(
      child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        // Zeitleiste
        SizedBox(
          width: 34,
          child: Column(children: [
            Container(
              width: 30,
              height: 30,
              alignment: Alignment.center,
              decoration: BoxDecoration(color: badgeColor, shape: BoxShape.circle),
              child: ps.state == PlanStepState.done
                  ? Icon(Icons.check_rounded, size: 18, color: badgeFg)
                  : locked
                      ? Icon(Icons.lock_outline_rounded, size: 15, color: badgeFg)
                      : Text('${index + 1}', style: TextStyle(color: badgeFg, fontWeight: FontWeight.w700)),
            ),
            if (!isLast) Expanded(child: Container(width: 2, color: c.line)),
          ]),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Opacity(
              opacity: locked ? 0.6 : 1,
              child: SwipeTile(
                id: 'step-${step.id}',
                onEdit: () => _editStep(step),
                onDelete: () => _deleteStep(step),
                child: AppCard(
                onTap: () => _editStep(step),
                padding: const EdgeInsets.fromLTRB(14, 10, 4, 12),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Expanded(
                      child: Text(step.title,
                          style: t.titleMedium?.copyWith(
                            decoration: step.isDone ? TextDecoration.lineThrough : null,
                            color: step.isDone ? c.dim : c.text,
                          )),
                    ),
                    if (index > 0)
                      IconButton(
                        tooltip: 'Nach oben',
                        visualDensity: VisualDensity.compact,
                        icon: Icon(Icons.arrow_upward_rounded, size: 18, color: c.muted),
                        onPressed: () => _run(() => _repo.moveStep(widget.goalId, step.id!, -1)),
                      ),
                    if (!isLast)
                      IconButton(
                        tooltip: 'Nach unten',
                        visualDensity: VisualDensity.compact,
                        icon: Icon(Icons.arrow_downward_rounded, size: 18, color: c.muted),
                        onPressed: () => _run(() => _repo.moveStep(widget.goalId, step.id!, 1)),
                      ),
                  ]),
                  if (step.description != null) ...[
                    Text(step.description!, style: t.bodySmall),
                    const SizedBox(height: 6),
                  ],
                  for (final todo in ps.todos) _todoRow(context, todo),
                  for (final a in ps.appointments) _appointmentRow(context, a),
                  const SizedBox(height: 6),
                  Wrap(spacing: 4, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
                    _chipButton(Icons.add_task_rounded, 'To-Do', () => _addTodo(step)),
                    _chipButton(Icons.event_rounded, 'Termin', () => _addAppointment(step)),
                    _chipButton(Icons.link_rounded, 'Verknüpfen', () => _linkExistingTodo(step)),
                  ]),
                  const SizedBox(height: 8),
                  _completeButton(context, ps),
                ]),
              ),
              ),
            ),
          ),
        ),
      ]),
    );
  }

  Widget _completeButton(BuildContext context, PlanStep ps) {
    final c = AppColors.of(context);
    if (ps.step.isDone) {
      return TextButton.icon(
        onPressed: () => _run(() => _repo.setStepDone(ps.step.id!, false)),
        icon: const Icon(Icons.undo_rounded, size: 18),
        label: const Text('Wieder öffnen'),
      );
    }
    // Wrap statt Row: auf schmalen Geräten rutscht der Hinweis unter den Button.
    return Wrap(spacing: 10, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
      ElevatedButton.icon(
        onPressed: ps.canComplete ? () => _run(() => _repo.setStepDone(ps.step.id!, true)) : null,
        icon: const Icon(Icons.check_rounded, size: 18),
        label: const Text('Schritt abschließen'),
      ),
      if (ps.blockedReason != null) Text(ps.blockedReason!, style: TextStyle(fontSize: 12, color: c.muted)),
    ]);
  }

  Widget _chipButton(IconData icon, String label, VoidCallback onTap) {
    return TextButton.icon(
      style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 8), visualDensity: VisualDensity.compact),
      onPressed: onTap,
      icon: Icon(icon, size: 16),
      label: Text(label),
    );
  }

  Widget _todoRow(BuildContext context, Todo todo) {
    final c = AppColors.of(context);
    final t = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(children: [
        AppCheck(checked: todo.isCompleted, size: 20, onTap: () => _toggleTodo(todo)),
        const SizedBox(width: 10),
        Expanded(
          child: Text(todo.title,
              style: t.bodyMedium?.copyWith(
                color: todo.isCompleted ? c.dim : c.text,
                decoration: todo.isCompleted ? TextDecoration.lineThrough : null,
              )),
        ),
        if (todo.dueDate != null) Text(DateFormat('dd.MM.').format(todo.dueDate!), style: t.labelMedium),
        IconButton(
          tooltip: 'Verknüpfung lösen',
          visualDensity: VisualDensity.compact,
          icon: Icon(Icons.link_off_rounded, size: 18, color: c.dim),
          onPressed: () => _run(() => _repo.linkTodo(todo.id!, null)),
        ),
      ]),
    );
  }

  Widget _appointmentRow(BuildContext context, Appointment a) {
    final c = AppColors.of(context);
    final t = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(children: [
        Icon(Icons.event_rounded, size: 20, color: c.event),
        const SizedBox(width: 10),
        Expanded(child: Text(a.title, style: t.bodyMedium)),
        Text(DateFormat('dd.MM. HH:mm').format(a.date), style: t.labelMedium),
        IconButton(
          tooltip: 'Verknüpfung lösen',
          visualDensity: VisualDensity.compact,
          icon: Icon(Icons.link_off_rounded, size: 18, color: c.dim),
          onPressed: () => _run(() => _repo.linkAppointment(a.id!, null)),
        ),
      ]),
    );
  }
}
