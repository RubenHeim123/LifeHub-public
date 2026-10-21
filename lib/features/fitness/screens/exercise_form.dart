import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:frontend/core/ui/app_actions.dart';
import 'package:frontend/core/ui/app_ui.dart';
import 'package:frontend/features/fitness/models/workout.dart';
import 'package:frontend/features/fitness/repositories/workout_repository.dart';

IconData exerciseIcon(ExerciseType type) => switch (type) {
      ExerciseType.strength => Icons.fitness_center_rounded,
      ExerciseType.run => Icons.directions_run_rounded,
      ExerciseType.skill => Icons.sports_gymnastics_rounded,
      ExerciseType.other => Icons.sports_rounded,
    };

/// Eigene Übung anlegen/bearbeiten – Name, Art, Messgröße, Notiz. Liefert die gespeicherte ID
/// oder `null` bei Abbruch.
Future<int?> showExerciseDialog(BuildContext context, {required int userid, Exercise? exercise}) =>
    showEditorSheet<int>(context, (_) => _ExerciseSheet(userid: userid, exercise: exercise));

class _ExerciseSheet extends StatefulWidget {
  final int userid;
  final Exercise? exercise;
  const _ExerciseSheet({required this.userid, this.exercise});

  @override
  State<_ExerciseSheet> createState() => _ExerciseSheetState();
}

class _ExerciseSheetState extends State<_ExerciseSheet> {
  final _formKey = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.exercise?.name ?? '');
  late final _notes = TextEditingController(text: widget.exercise?.notes ?? '');
  late ExerciseType _type = widget.exercise?.type ?? ExerciseType.strength;
  late ExerciseMetric _metric = widget.exercise?.metric ?? ExerciseMetric.reps;

  @override
  void dispose() {
    _name.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final navigator = Navigator.of(context);
    final id = await runGuarded(
      context,
      () => context.read<WorkoutRepository>().saveExercise(Exercise(
            id: widget.exercise?.id,
            userid: widget.userid,
            name: _name.text.trim(),
            type: _type,
            metric: _metric,
            notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
            catalogKey: widget.exercise?.catalogKey,
          )),
    );
    if (id != null) navigator.pop(id);
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return EditorSheet(
      formKey: _formKey,
      title: widget.exercise == null ? 'Neue Übung' : 'Übung bearbeiten',
      onSave: _save,
      children: [
        TextFormField(
          controller: _name,
          autofocus: widget.exercise == null,
          decoration: const InputDecoration(labelText: 'Name'),
          validator: (v) => (v ?? '').trim().isEmpty ? 'Name erforderlich' : null,
        ),
        const SizedBox(height: 12),
        Text('Art', style: t.titleSmall),
        const SizedBox(height: 6),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final type in ExerciseType.values)
            AppChip(
              label: type.label,
              selected: type == _type,
              onTap: () => setState(() {
                _type = type;
                if (type == ExerciseType.run) _metric = ExerciseMetric.distance;
              }),
            ),
        ]),
        const SizedBox(height: 12),
        Text('Messen in', style: t.titleSmall),
        const SizedBox(height: 6),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final m in ExerciseMetric.values)
            AppChip(label: m.label, selected: m == _metric, onTap: () => setState(() => _metric = m)),
        ]),
        const SizedBox(height: 12),
        TextFormField(controller: _notes, minLines: 1, maxLines: 3, decoration: const InputDecoration(labelText: 'Notiz (optional)')),
      ],
    );
  }
}
