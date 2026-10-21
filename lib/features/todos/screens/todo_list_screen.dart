import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:provider/provider.dart';
import 'package:frontend/core/models/dates.dart';
import 'package:frontend/features/todos/repositories/todo_repository.dart';
import 'package:frontend/features/vision/repositories/vision_repository.dart';
import 'package:frontend/features/vision/widgets/goal_hint.dart';
import 'package:frontend/core/ui/app_actions.dart';
import 'package:frontend/core/ui/app_ui.dart';
import 'package:frontend/core/ui/theme.dart';
import 'package:frontend/features/auth/models/user.dart';
import 'package:frontend/features/todos/models/todo.dart';
import 'package:frontend/features/todos/screens/add_update_todo_screen.dart';

class TodoListScreen extends StatefulWidget {
  final UserModel user;
  const TodoListScreen({super.key, required this.user});

  @override
  State<TodoListScreen> createState() => _TodoListScreenState();
}

class _TodoListScreenState extends State<TodoListScreen> {
  static const _filters = ['Alle', 'Offen', 'Erledigt'];
  static const _groupOrder = ['Überfällig', 'Heute', 'Diese Woche', 'Später', 'Ohne Datum'];

  late final TodoRepository _db = context.read<TodoRepository>();
  String _selectedFilter = 'Alle';
  List<Todo> _todos = [];
  Map<int, String> _goalByStep = {};
  bool _isLoading = true;

  DateTime get _today {
    final n = DateTime.now();
    return DateTime(n.year, n.month, n.day);
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final vision = context.read<VisionRepository>();
    final list = await _db.getAllTodos(widget.user.uid);
    final goals = await vision.goalTitlesForSteps(widget.user.uid);
    if (!mounted) return;
    setState(() {
      _todos = list;
      _goalByStep = goals;
      _isLoading = false;
    });
  }

  bool _matches(Todo t, String f) => f == 'Alle' ? true : (f == 'Offen' ? !t.isCompleted : t.isCompleted);

  String _groupOf(Todo t) {
    final d = t.dueDate;
    if (d == null) return 'Ohne Datum';
    final day = DateTime(d.year, d.month, d.day);
    if (day.isBefore(_today)) return t.isCompleted ? 'Diese Woche' : 'Überfällig';
    if (day == _today) return 'Heute';
    if (daysBetween(_today, day) < 7) return 'Diese Woche';
    return 'Später';
  }

  String _dueLabel(Todo t) {
    final d = t.dueDate;
    if (d == null) return '';
    final day = DateTime(d.year, d.month, d.day);
    if (day == _today) return 'Heute';
    if (day == addDays(_today, 1)) return 'Morgen';
    return DateFormat('E, dd.MM.', 'de_DE').format(d);
  }

  Future<void> _openEditor([Todo? todo]) =>
      openTodoEditor(context, userid: widget.user.uid, todo: todo, onChanged: _load);

  Future<void> _toggleTodo(Todo todo) async {
    final updated = todo.copyWith(isCompleted: !todo.isCompleted);
    setState(() => _todos = _todos.map((x) => x.id == todo.id ? updated : x).toList());
    final next = await runGuarded(context, () => _db.setCompleted(todo, updated.isCompleted));
    if (next != null && mounted) {
      showAppSnack(context, 'Nächstes Mal: ${_dueLabel(next)}');
    }
    _load();
  }

  Future<void> _deleteTodo(Todo todo) => deleteWithUndo(
        context,
        label: todo.title,
        delete: () => _db.deleteTodo(todo.id!),
        restore: () => _db.restoreTodo(todo),
        onChanged: _load,
      );

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final open = _todos.where((x) => !x.isCompleted).length;

    final filtered = _todos.where((x) => _matches(x, _selectedFilter)).toList();
    final groups = <String, List<Todo>>{};
    for (final todo in filtered) {
      groups.putIfAbsent(_groupOf(todo), () => []).add(todo);
    }
    for (final list in groups.values) {
      list.sort((a, b) {
        if (a.isCompleted != b.isCompleted) return a.isCompleted ? 1 : -1;
        return (a.dueDate ?? DateTime(9999)).compareTo(b.dueDate ?? DateTime(9999));
      });
    }

    return Scaffold(
      floatingActionButton: AppFab(label: 'Aufgabe', heroTag: 'todo-fab', onPressed: () => _openEditor()),
      body: SafeArea(
        bottom: false,
        child: _isLoading
              ? Center(child: CircularProgressIndicator(color: c.accent))
              : RefreshIndicator(
                  color: c.accent,
                  onRefresh: _load,
                  child: ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: pagePadding(context),
                    children: [
                      SummaryRow('$open offen'),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        children: _filters
                            .map((f) => AppChip(
                                  label: f,
                                  count: _todos.where((x) => _matches(x, f)).length,
                                  selected: f == _selectedFilter,
                                  onTap: () => setState(() => _selectedFilter = f),
                                ))
                            .toList(),
                      ),
                      const SizedBox(height: 18),
                      if (filtered.isEmpty)
                        _todos.isEmpty
                            ? const EmptyState(
                                icon: Icons.checklist_rounded,
                                title: 'Keine To-Dos vorhanden.',
                                message: 'Leg über „Aufgabe“ an, was zu erledigen ist – mit Fälligkeit erinnert dich die App.',
                              )
                            : const EmptyState(icon: Icons.filter_alt_off_outlined, title: 'Keine To-Dos für diesen Filter.'),
                      for (final g in _groupOrder)
                        if (groups[g] != null) ...[
                          GroupLabel(g, trailing: '${groups[g]!.length}'),
                          AppCard(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                            child: Column(
                              children: groups[g]!.asMap().entries.map((e) => _todoRow(context, e.value, e.key == 0)).toList(),
                            ),
                          ),
                          const SizedBox(height: 18),
                        ],
                    ],
                  ),
                ),
      ),
    );
  }

  Widget _todoRow(BuildContext context, Todo todo, bool first) {
    final c = AppColors.of(context);
    final t = Theme.of(context).textTheme;
    final done = todo.isCompleted;
    final overdue = !done && _groupOf(todo) == 'Überfällig';
    final dueToday = !done && _groupOf(todo) == 'Heute';

    return SwipeTile(
      id: 'todo-${todo.id}',
      startAction: SwipeAction(
        label: done ? 'Offen' : 'Erledigt',
        icon: done ? Icons.undo_rounded : Icons.check_rounded,
        onPressed: () => _toggleTodo(todo),
      ),
      onEdit: () => _openEditor(todo),
      onDelete: () => _deleteTodo(todo),
      child: InkWell(
        onTap: () => _openEditor(todo),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 13),
          decoration: BoxDecoration(border: first ? null : Border(top: BorderSide(color: c.line.withValues(alpha: 0.5)))),
          child: Row(children: [
            AppCheck(checked: done, onTap: () => _toggleTodo(todo)),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(todo.title,
                    style: t.bodyLarge?.copyWith(
                      color: done ? c.dim : c.text,
                      decoration: done ? TextDecoration.lineThrough : null,
                    )),
                if (todo.description?.isNotEmpty ?? false) ...[
                  const SizedBox(height: 2),
                  Text(todo.description!, style: t.labelMedium?.copyWith(color: c.dim), maxLines: 1, overflow: TextOverflow.ellipsis),
                ],
                if (todo.repeats)
                  Row(children: [
                    Icon(Icons.repeat_rounded, size: 13, color: c.dim),
                    const SizedBox(width: 4),
                    Flexible(child: Text(todo.repeat.label(todo.repeatStart ?? todo.dueDate), style: t.labelMedium?.copyWith(color: c.dim))),
                  ]),
                if (_goalByStep[todo.goalStepId] != null) GoalHint(_goalByStep[todo.goalStepId]!),
              ]),
            ),
            const SizedBox(width: 8),
            Text(
              _dueLabel(todo),
              style: TextStyle(fontSize: 12, color: overdue ? c.negative : (dueToday ? c.streak : c.dim)),
            ),
          ]),
        ),
      ),
    );
  }
}
