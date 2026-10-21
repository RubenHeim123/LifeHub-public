import 'package:flutter/material.dart';
import 'package:frontend/core/ui/app_actions.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import 'package:frontend/core/ui/app_ui.dart';
import 'package:frontend/core/ui/dialogs.dart';
import 'package:frontend/core/ui/form_widgets.dart';
import 'package:frontend/core/ui/modern_appbar.dart';
import 'package:frontend/core/ui/theme.dart';
import 'package:frontend/features/fitness/models/workout.dart';
import 'package:frontend/features/fitness/repositories/workout_repository.dart';
import 'package:frontend/features/fitness/screens/catalog_screen.dart';

/// Workout aus Übungen der Bibliothek zusammenstellen. Gibt `true` zurück, wenn gespeichert/gelöscht.
class WorkoutEditorScreen extends StatefulWidget {
  final int userid;
  final Workout? workout;
  const WorkoutEditorScreen({super.key, required this.userid, this.workout});

  @override
  State<WorkoutEditorScreen> createState() => _WorkoutEditorScreenState();
}

class _WorkoutEditorScreenState extends State<WorkoutEditorScreen> {
  final _formKey = GlobalKey<FormState>();
  late final WorkoutRepository _repo = context.read<WorkoutRepository>();
  late final _name = TextEditingController(text: widget.workout?.name ?? '');
  late final _notes = TextEditingController(text: widget.workout?.notes ?? '');
  late final Set<int> _weekdays = {...?widget.workout?.repeatWeekdays};
  late final List<WorkoutExercise> _exercises = [...?widget.workout?.exercises];
  late TrainingMethod? _method = widget.workout?.method;
  bool _saving = false;

  /// Einmalige Termine: bereits gespeicherte (offen, ab heute) und neu hinzugefügte.
  List<PlanEntry> _onceSaved = [];
  final List<DateTime> _onceNew = [];
  final Set<int> _onceRemoved = {};

  @override
  void initState() {
    super.initState();
    final id = widget.workout?.id;
    if (id != null) {
      _repo.getUpcomingOnce(widget.userid, id).then((list) {
        if (mounted) setState(() => _onceSaved = list);
      });
    }
  }

  Future<void> _addOnceDate() async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final picked = await showDatePicker(
      context: context,
      initialDate: today,
      firstDate: today,
      lastDate: DateTime(today.year + 1, today.month, today.day),
      helpText: 'Einmalig einplanen',
    );
    if (picked == null) return;
    final day = DateTime(picked.year, picked.month, picked.day);
    final exists = _onceNew.contains(day) || _onceSaved.any((e) => e.date == day && !_onceRemoved.contains(e.id));
    if (!exists) setState(() => _onceNew.add(day));
  }

  /// Vorschau mit aktueller Trainingsform (für Anzeige der Vorgaben und Paare).
  Workout get _draft => Workout(userid: widget.userid, name: '', exercises: _exercises, method: _method);

  bool get _isNew => widget.workout == null;

  @override
  void dispose() {
    _name.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    final navigator = Navigator.of(context);
    final ok = await runGuarded(context, () async {
      final id = await _repo.saveWorkout(Workout(
        id: widget.workout?.id,
        userid: widget.userid,
        name: _name.text.trim(),
        notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
        repeatWeekdays: _weekdays.toList()..sort(),
        exercises: _exercises,
        method: _method,
      ));
      for (final d in _onceNew) {
        await _repo.planWorkout(widget.userid, id, d);
      }
      for (final plannedId in _onceRemoved) {
        await _repo.removePlanned(plannedId);
      }
      return true;
    });
    if (ok != true) {
      if (mounted) setState(() => _saving = false);
      return;
    }
    navigator.pop(true);
  }

  /// Die Liste löscht mit „Rückgängig“; bisherige Protokolle bleiben erhalten.
  void _delete() => Navigator.of(context).pop(kDeletedResult);

  Future<void> _addExercise() async {
    // Ein Katalog für alles: mitgelieferte und eigene Übungen
    final picked = await Navigator.of(context).push<Exercise>(
      MaterialPageRoute(builder: (_) => CatalogScreen(userid: widget.userid, pick: true)),
    );
    if (picked == null) return;
    setState(() => _exercises.add(switch (picked.metric) {
          ExerciseMetric.reps => WorkoutExercise(exercise: picked, sets: 3, reps: 10),
          ExerciseMetric.time => WorkoutExercise(exercise: picked, sets: 3, durationSec: 30),
          ExerciseMetric.distance => WorkoutExercise(exercise: picked, sets: 1, distanceKm: 5),
        }));
  }

  Future<void> _editTarget(int index) async {
    if (_method == TrainingMethod.zirkel) return _editCircuitReps(index);
    // Bei Trainingsformen mit Timer ergeben sich Sätze und Wiederholungen aus der Form.
    if (_method != null) return;
    final we = _exercises[index];
    final metric = we.exercise.metric;
    final isDistance = metric == ExerciseMetric.distance;
    final values = await showTextFieldsDialog(context, title: we.exercise.name, fields: [
      if (!isDistance) DialogField('Sätze', initial: '${we.sets}', required: true),
      DialogField(
        switch (metric) {
          ExerciseMetric.reps => 'Wiederholungen',
          ExerciseMetric.time => 'Zeit (Sekunden)',
          ExerciseMetric.distance => 'Distanz (km)',
        },
        initial: we.target == null ? null : '${we.target}'.replaceAll('.', ','),
      ),
    ]);
    if (values == null) return;
    final sets = isDistance ? 1 : int.tryParse(values[0] ?? '') ?? we.sets;
    final target = num.tryParse((values.last ?? '').replaceAll(',', '.'));
    setState(() => _exercises[index] = WorkoutExercise(
          exercise: we.exercise,
          sets: sets.clamp(1, 20),
          reps: metric == ExerciseMetric.reps ? target?.round() : null,
          durationSec: metric == ExerciseMetric.time ? target?.round() : null,
          distanceKm: metric == ExerciseMetric.distance ? target?.toDouble() : null,
        ));
  }

  Future<void> _editCircuitReps(int index) async {
    final we = _exercises[index];
    final isTime = we.exercise.metric == ExerciseMetric.time;
    final values = await showTextFieldsDialog(context, title: we.exercise.name, fields: [
      DialogField(isTime ? 'Sekunden pro Runde' : 'Wiederholungen pro Runde',
          initial: '${(isTime ? we.durationSec : we.reps) ?? (isTime ? 30 : 10)}', required: true),
    ]);
    final v = int.tryParse(values?.first ?? '');
    if (v == null) return;
    setState(() => _exercises[index] = WorkoutExercise(
          exercise: we.exercise,
          sets: 1,
          reps: isTime ? null : v,
          durationSec: isTime ? v : null,
        ));
  }

  String _subtitle(int i) {
    final we = _exercises[i];
    if (_method == TrainingMethod.supersatz) return 'Paar ${i ~/ 2 + 1} · ${i.isEven ? '1–5 Wdh., langsam' : '6–12 Wdh., schnell'}';
    if (_method == TrainingMethod.zirkel) {
      return we.exercise.metric == ExerciseMetric.time ? '${we.durationSec ?? 30} s pro Runde' : '${we.reps ?? 10} Wdh. pro Runde';
    }
    return _draft.targetOf(we);
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final t = Theme.of(context).textTheme;
    return Scaffold(
      appBar: ModernAppBar(title: _isNew ? 'Neues Workout' : 'Workout bearbeiten'),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(padding: const EdgeInsets.all(16), children: [
            FormFieldCard(
              icon: Icons.fitness_center_rounded,
              label: 'Name',
              child: TextFormField(
                controller: _name,
                decoration: bareInputDecoration.copyWith(hintText: 'z. B. Push, Beine, Lauf'),
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Name erforderlich' : null,
              ),
            ),
            FormFieldCard(
              icon: Icons.notes_rounded,
              label: 'Notiz',
              child: TextFormField(controller: _notes, decoration: bareInputDecoration.copyWith(hintText: 'Optional')),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 4, 4, 4),
              child: Text('Einplanen', style: t.titleSmall),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 0, 4, 6),
              child: Text('Jede Woche wiederholen', style: t.labelMedium),
            ),
            Wrap(spacing: 6, runSpacing: 6, children: [
              for (var d = 1; d <= 7; d++)
                AppChip(
                  label: weekdayShort[d - 1],
                  selected: _weekdays.contains(d),
                  onTap: () => setState(() => _weekdays.contains(d) ? _weekdays.remove(d) : _weekdays.add(d)),
                ),
            ]),
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 12, 4, 6),
              child: Text('Einmalig an bestimmten Tagen', style: t.labelMedium),
            ),
            Wrap(spacing: 6, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
              for (final e in _onceSaved.where((e) => !_onceRemoved.contains(e.id)))
                InputChip(
                  label: Text(DateFormat('EE d.M.', 'de_DE').format(e.date)),
                  onDeleted: () => setState(() => _onceRemoved.add(e.id!)),
                  deleteButtonTooltipMessage: 'Termin entfernen',
                ),
              for (final d in _onceNew)
                InputChip(
                  label: Text(DateFormat('EE d.M.', 'de_DE').format(d)),
                  onDeleted: () => setState(() => _onceNew.remove(d)),
                  deleteButtonTooltipMessage: 'Termin entfernen',
                ),
              ActionChip(
                avatar: const Icon(Icons.event_rounded, size: 18),
                label: const Text('Datum hinzufügen'),
                onPressed: _addOnceDate,
              ),
            ]),
            const SizedBox(height: 20),
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
              child: Text('Trainingsform', style: t.titleSmall),
            ),
            Wrap(spacing: 6, runSpacing: 6, children: [
              AppChip(label: 'Frei (Sätze × Wdh.)', selected: _method == null, onTap: () => setState(() => _method = null)),
              for (final m in TrainingMethod.values)
                AppChip(label: m.label, selected: _method == m, onTap: () => setState(() => _method = m)),
            ]),
            const SizedBox(height: 6),
            Text(
              _method == null
                  ? 'Du legst Sätze und Wiederholungen je Übung selbst fest.'
                  : '${_method!.description} Der Timer führt dich durchs Training – Sätze und Wiederholungen musst du nicht festlegen.',
              style: t.bodySmall?.copyWith(color: c.muted),
            ),
            if (_method == TrainingMethod.supersatz && _exercises.length.isOdd)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text('Supersätze brauchen Übungspaare – füge noch eine Übung hinzu.',
                    style: t.bodySmall?.copyWith(color: c.streak)),
              ),
            const SizedBox(height: 20),
            SectionTitle('Übungen', trailing: _exercises.isEmpty ? null : '${_exercises.length}'),
            if (_exercises.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text('Noch keine Übungen – füge welche aus deiner Bibliothek hinzu.', style: t.bodyMedium?.copyWith(color: c.muted)),
              )
            else
              AppCard(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: ReorderableListView(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  buildDefaultDragHandles: false,
                  onReorder: (from, to) => setState(() {
                    if (to > from) to--;
                    _exercises.insert(to, _exercises.removeAt(from));
                  }),
                  children: [
                    for (var i = 0; i < _exercises.length; i++)
                      ListTile(
                        key: ValueKey('we-$i-${_exercises[i].exercise.id}'),
                        leading: ReorderableDragStartListener(index: i, child: const Icon(Icons.drag_indicator_rounded)),
                        title: Text(_exercises[i].exercise.name, style: t.bodyLarge),
                        subtitle: Text(_subtitle(i), style: t.labelMedium),
                        onTap: _method == null || _method == TrainingMethod.zirkel ? () => _editTarget(i) : null,
                        trailing: IconButton(
                          tooltip: 'Entfernen',
                          icon: const Icon(Icons.close_rounded),
                          onPressed: () => setState(() => _exercises.removeAt(i)),
                        ),
                      ),
                  ],
                ),
              ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _addExercise,
              icon: const Icon(Icons.add_rounded),
              label: const Text('Übung hinzufügen'),
            ),
            const SizedBox(height: 20),
            FormActions(isNew: _isNew, busy: _saving, onSave: _save, onDelete: _isNew ? null : _delete),
            const SizedBox(height: 24),
          ]),
        ),
      ),
    );
  }
}
