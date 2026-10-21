import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:frontend/core/models/repeat.dart';
import 'package:frontend/core/ui/app_actions.dart';
import 'package:frontend/core/ui/form_widgets.dart';
import 'package:frontend/core/ui/modern_appbar.dart';
import 'package:frontend/core/ui/repeat_picker.dart';
import 'package:frontend/features/todos/models/todo.dart';
import 'package:frontend/features/todos/repositories/todo_repository.dart';
import 'package:frontend/features/vision/repositories/vision_repository.dart';

/// Aufgabe anlegen oder bearbeiten – mit allen Feldern: Titel, Beschreibung, Fälligkeit
/// (Standard heute) mit optionaler Uhrzeit, Wiederholung und Ziel-Schritt.
/// Liefert `true` nach dem Speichern bzw. [kDeletedResult] bei „Löschen“.
class AddUpdateTodoScreen extends StatefulWidget {
  final int userid;
  final Todo? todo;

  /// Neue Aufgabe direkt einem Schritt eines Ziel-Plans zuordnen.
  final int? goalStepId;

  /// Vorgabe fürs Fälligkeitsdatum neuer Aufgaben (sonst heute).
  final DateTime? initialDate;

  const AddUpdateTodoScreen({super.key, required this.userid, this.todo, this.goalStepId, this.initialDate});

  @override
  State<AddUpdateTodoScreen> createState() => _AddUpdateTodoScreenState();
}

class _AddUpdateTodoScreenState extends State<AddUpdateTodoScreen> {
  final _formKey = GlobalKey<FormState>();
  late final Todo? _old = widget.todo;
  late final _title = TextEditingController(text: _old?.title);
  late final _description = TextEditingController(text: _old?.description);
  late DateTime? _date = _old != null ? _dateOnly(_old.dueDate) : _dateOnly(widget.initialDate ?? DateTime.now());
  late TimeOfDay? _time = _timeOf(_old?.dueDate);
  late Repeat _repeat = _old?.repeat ?? Repeat.none;
  late bool _done = _old?.isCompleted ?? false;
  late int? _stepId = _old?.goalStepId ?? widget.goalStepId;
  List<(int, String)> _steps = const [];
  bool _saving = false;

  bool get _isNew => _old == null;

  static DateTime? _dateOnly(DateTime? d) => d == null ? null : DateTime(d.year, d.month, d.day);
  static TimeOfDay? _timeOf(DateTime? d) => d == null || (d.hour == 0 && d.minute == 0) ? null : TimeOfDay.fromDateTime(d);

  @override
  void initState() {
    super.initState();
    context.read<VisionRepository>().stepChoices(widget.userid).then((s) {
      if (mounted) setState(() => _steps = s);
    });
  }

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    super.dispose();
  }

  DateTime? get _due {
    final d = _date;
    if (d == null) return null;
    final t = _time;
    return t == null ? d : DateTime(d.year, d.month, d.day, t.hour, t.minute);
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(context: context, initialTime: _time ?? const TimeOfDay(hour: 9, minute: 0));
    if (picked != null) setState(() => _time = picked);
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    final navigator = Navigator.of(context);
    final repo = context.read<TodoRepository>();
    final repeat = _date == null ? Repeat.none : _repeat;
    final todo = Todo(
      id: _old?.id,
      title: _title.text.trim(),
      description: _description.text.trim().isEmpty ? null : _description.text.trim(),
      dueDate: _due,
      isCompleted: _done,
      userid: widget.userid,
      goalStepId: _stepId,
      repeat: repeat,
      // Neue Regel → die Serie beginnt mit diesem Datum
      repeatStart: repeat == _old?.repeat ? _old?.repeatStart : _date,
      seriesId: _old?.seriesId,
    );
    final ok = await runGuarded(context, () async {
      if (_isNew) {
        await repo.createTodo(todo);
      } else if (_done && !_old!.isCompleted) {
        await repo.updateTodo(todo.copyWith(isCompleted: false));
        await repo.setCompleted(todo, true); // legt bei Wiederholung das nächste Vorkommen an
      } else {
        await repo.updateTodo(todo);
      }
      return true;
    });
    if (!mounted) return;
    setState(() => _saving = false);
    if (ok == true) navigator.pop(true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: ModernAppBar(title: _isNew ? 'Neue Aufgabe' : 'Aufgabe bearbeiten'),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Form(
            key: _formKey,
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              FormFieldCard(
                icon: Icons.task_alt_rounded,
                label: 'Titel',
                child: TextFormField(
                  controller: _title,
                  autofocus: _isNew,
                  decoration: bareInputDecoration.copyWith(hintText: 'z. B. Bad putzen'),
                  validator: (v) => (v ?? '').trim().isEmpty ? 'Bitte Titel eingeben' : null,
                ),
              ),
              FormFieldCard(
                icon: Icons.notes_rounded,
                label: 'Beschreibung',
                child: TextFormField(
                  controller: _description,
                  minLines: 1,
                  maxLines: 4,
                  decoration: bareInputDecoration.copyWith(hintText: 'Optional'),
                ),
              ),
              DateField(
                label: 'Fällig am',
                icon: Icons.event_rounded,
                value: _date,
                required: false,
                onChanged: (d) => setState(() => _date = d),
                onCleared: () => setState(() {
                  _date = null;
                  _time = null;
                  _repeat = Repeat.none;
                }),
              ),
              if (_date != null)
                FormFieldCard(
                  icon: Icons.schedule_rounded,
                  label: 'Uhrzeit (Erinnerung)',
                  child: Row(children: [
                    Expanded(
                      child: InkWell(
                        onTap: _pickTime,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Text(_time == null ? 'Ohne Uhrzeit – Erinnerung um 9 Uhr' : _time!.format(context)),
                        ),
                      ),
                    ),
                    if (_time != null)
                      IconButton(
                        tooltip: 'Uhrzeit entfernen',
                        visualDensity: VisualDensity.compact,
                        icon: const Icon(Icons.close_rounded, size: 18),
                        onPressed: () => setState(() => _time = null),
                      ),
                  ]),
                ),
              if (_date != null) RepeatPicker(value: _repeat, start: _date, onChanged: (r) => setState(() => _repeat = r)),
              if (_steps.isNotEmpty || _stepId != null)
                FormFieldCard(
                  icon: Icons.flag_outlined,
                  label: 'Ziel-Schritt (Vision Board)',
                  child: DropdownButtonFormField<int?>(
                    isExpanded: true,
                    value: _steps.any((s) => s.$1 == _stepId) ? _stepId : null,
                    decoration: bareInputDecoration,
                    items: [
                      const DropdownMenuItem(value: null, child: Text('Keiner')),
                      for (final (id, label) in _steps)
                        DropdownMenuItem(value: id, child: Text(label, overflow: TextOverflow.ellipsis)),
                    ],
                    onChanged: (v) => setState(() => _stepId = v),
                  ),
                ),
              if (!_isNew)
                SwitchListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                  title: const Text('Erledigt'),
                  value: _done,
                  onChanged: (v) => setState(() => _done = v),
                ),
              const SizedBox(height: 12),
              FormActions(
                isNew: _isNew,
                busy: _saving,
                onSave: _save,
                onDelete: _isNew ? null : () => Navigator.of(context).pop(kDeletedResult),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

/// Öffnet den Editor für [todo] (oder eine neue Aufgabe). „Löschen“ im Editor löscht mit
/// „Rückgängig“; [onChanged] lädt die aufrufende Ansicht neu.
Future<void> openTodoEditor(
  BuildContext context, {
  required int userid,
  Todo? todo,
  DateTime? initialDate,
  required VoidCallback onChanged,
}) async {
  final repo = context.read<TodoRepository>();
  final result = await Navigator.of(context).push<Object?>(
    MaterialPageRoute(builder: (_) => AddUpdateTodoScreen(userid: userid, todo: todo, initialDate: initialDate)),
  );
  if (!context.mounted) return;
  if (result == kDeletedResult && todo != null) {
    await deleteWithUndo(
      context,
      label: todo.title,
      delete: () => repo.deleteTodo(todo.id!),
      restore: () => repo.restoreTodo(todo),
      onChanged: onChanged,
    );
  } else if (result != null) {
    onChanged();
  }
}
