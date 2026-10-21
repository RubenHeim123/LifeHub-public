import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:frontend/core/ui/app_actions.dart';
import 'package:frontend/core/ui/app_ui.dart';
import 'package:frontend/core/ui/modern_appbar.dart';
import 'package:frontend/core/ui/theme.dart';
import 'package:frontend/features/fitness/models/workout.dart';
import 'package:frontend/features/fitness/repositories/workout_repository.dart';
import 'package:frontend/features/fitness/screens/catalog_screen.dart';

/// Protokoll einer Trainingseinheit: Sätze abhaken und tatsächliche Werte eintragen.
/// Gibt `true` zurück, wenn die Einheit beendet wurde.
class SessionScreen extends StatefulWidget {
  final WorkoutSession session;
  const SessionScreen({super.key, required this.session});

  @override
  State<SessionScreen> createState() => _SessionScreenState();
}

class _SessionScreenState extends State<SessionScreen> {
  late final WorkoutRepository _repo = context.read<WorkoutRepository>();
  late final List<SessionSet> _sets = [...widget.session.sets];
  final _started = DateTime.now();
  bool _saving = false;

  Future<void> _update(int index, SessionSet set) async {
    setState(() => _sets[index] = set);
    await _repo.updateSet(set);
  }

  Future<void> _editValue(int index) async {
    final set = _sets[index];
    final metric = set.exercise.metric;
    final value = await showDialog<num>(
      context: context,
      builder: (_) => _ValueDialog(
        title: '${set.exercise.name} · Satz ${set.setIndex + 1}',
        label: switch (metric) {
          ExerciseMetric.reps => 'Wiederholungen',
          ExerciseMetric.time => 'Zeit (Sekunden)',
          ExerciseMetric.distance => 'Distanz (km)',
        },
        initial: set.value == null ? '' : '${set.value}'.replaceAll('.', ','),
      ),
    );
    if (value != null) await _update(index, set.withValue(value, done: true));
  }

  Future<void> _finish() async {
    setState(() => _saving = true);
    final navigator = Navigator.of(context);
    final elapsed = DateTime.now().difference(_started).inMinutes;
    final ok = await runGuarded(context, () async {
      await _repo.finishSession(
        widget.session,
        durationMin: widget.session.durationMin ?? (elapsed < 1 ? null : elapsed),
      );
      return true;
    });
    if (ok != true) {
      if (mounted) setState(() => _saving = false);
      return;
    }
    navigator.pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final t = Theme.of(context).textTheme;
    final done = _sets.where((s) => s.done).length;

    // Sätze nach Übung gruppieren, Reihenfolge wie im Workout
    final groups = <int, List<int>>{};
    for (var i = 0; i < _sets.length; i++) {
      groups.putIfAbsent(_sets[i].exercise.id!, () => []).add(i);
    }

    return Scaffold(
      appBar: ModernAppBar(title: widget.session.name),
      body: SafeArea(
        child: ListView(padding: detailPadding(context), children: [
          AppCard(
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('$done von ${_sets.length} Sätzen erledigt', style: t.titleSmall),
              const SizedBox(height: 8),
              AppProgressBar(value: _sets.isEmpty ? 0 : done / _sets.length),
            ]),
          ),
          const SizedBox(height: 16),
          if (_sets.isEmpty)
            Text('Dieses Workout enthält noch keine Übungen.', style: t.bodyMedium?.copyWith(color: c.muted)),
          for (final indices in groups.values) ...[
            Row(children: [
              GestureDetector(
                onTap: _sets[indices.first].exercise.catalog == null
                    ? null
                    : () => openCatalogDetail(context,
                        userid: _sets[indices.first].exercise.userid, entry: _sets[indices.first].exercise.catalog!),
                child: ExerciseThumb(exercise: _sets[indices.first].exercise, size: 40),
              ),
              const SizedBox(width: 10),
              Expanded(child: SectionTitle(_sets[indices.first].exercise.name)),
            ]),
            AppCard(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Column(children: [
                for (final i in indices)
                  ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                    leading: AppCheck(
                      checked: _sets[i].done,
                      onTap: () => _update(i, _sets[i].withValue(_sets[i].value, done: !_sets[i].done)),
                    ),
                    title: Text('Satz ${_sets[i].setIndex + 1}', style: t.bodyLarge),
                    trailing: TextButton(
                      onPressed: () => _editValue(i),
                      child: Text(_sets[i].value == null ? 'Wert' : _label(_sets[i])),
                    ),
                  ),
              ]),
            ),
            const SizedBox(height: 16),
          ],
          ElevatedButton.icon(
            onPressed: _saving ? null : _finish,
            icon: const Icon(Icons.flag_rounded),
            label: const Text('Training beenden'),
          ),
        ]),
      ),
    );
  }

  static String _label(SessionSet s) {
    final v = formatValue(s.exercise.metric, s.value!);
    return s.exercise.metric == ExerciseMetric.reps ? '$v Wdh.' : v;
  }
}

class _ValueDialog extends StatefulWidget {
  final String title;
  final String label;
  final String initial;
  const _ValueDialog({required this.title, required this.label, required this.initial});

  @override
  State<_ValueDialog> createState() => _ValueDialogState();
}

class _ValueDialogState extends State<_ValueDialog> {
  late final _controller = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() => Navigator.of(context).pop(num.tryParse(_controller.text.trim().replaceAll(',', '.')));

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        controller: _controller,
        autofocus: true,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: InputDecoration(labelText: widget.label),
        onSubmitted: (_) => _submit(),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Abbrechen')),
        ElevatedButton(onPressed: _submit, child: const Text('Übernehmen')),
      ],
    );
  }
}
