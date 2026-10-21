import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import 'package:frontend/core/ui/app_actions.dart';
import 'package:frontend/core/ui/app_ui.dart';
import 'package:frontend/core/ui/modern_appbar.dart';
import 'package:frontend/core/ui/theme.dart';
import 'package:frontend/features/auth/models/user.dart';
import 'package:frontend/features/fitness/models/workout.dart';
import 'package:frontend/features/fitness/repositories/workout_repository.dart';
import 'package:frontend/features/fitness/catalog/exercise_catalog.dart';
import 'package:frontend/features/fitness/screens/catalog_screen.dart';
import 'package:frontend/features/fitness/screens/progress_screen.dart';
import 'package:frontend/features/fitness/screens/sample_plans_screen.dart';
import 'package:frontend/features/fitness/screens/method_session_screen.dart';
import 'package:frontend/features/fitness/screens/workout_editor_screen.dart';

/// Trainingsplan: Wochenleiste, Workouts des gewählten Tages, Einplanen und Zugänge
/// zu Workouts, Übungen und Fortschritt.
class TrainingScreen extends StatefulWidget {
  final UserModel user;
  const TrainingScreen({super.key, required this.user});

  @override
  State<TrainingScreen> createState() => _TrainingScreenState();
}

class _TrainingScreenState extends State<TrainingScreen> {
  late final WorkoutRepository _repo = context.read<WorkoutRepository>();
  late DateTime _day = _today();
  late DateTime _weekStart = _mondayOf(_day);
  Map<DateTime, List<PlanEntry>>? _plan;
  List<Workout> _workouts = [];

  int get _uid => widget.user.uid;

  static DateTime _today() {
    final n = DateTime.now();
    return DateTime(n.year, n.month, n.day);
  }

  static DateTime _mondayOf(DateTime d) => DateTime(d.year, d.month, d.day - (d.weekday - 1));

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final end = DateTime(_weekStart.year, _weekStart.month, _weekStart.day + 6);
    final plan = await _repo.getPlan(_uid, _weekStart, end);
    final workouts = await _repo.getWorkouts(_uid);
    if (mounted) {
      setState(() {
        _plan = plan;
        _workouts = workouts;
      });
    }
  }

  void _shiftWeek(int weeks) {
    setState(() {
      _weekStart = DateTime(_weekStart.year, _weekStart.month, _weekStart.day + 7 * weeks);
      _day = DateTime(_day.year, _day.month, _day.day + 7 * weeks);
    });
    _load();
  }

  Future<void> _push(Widget screen) async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));
    _load();
  }

  Future<void> _start(PlanEntry entry) async {
    final session = await _repo.startSession(_uid, entry);
    if (!mounted) return;
    await openSessionFor(context, entry.workout, session, review: entry.status == PlanStatus.done);
    _load();
  }

  Future<void> _skip(PlanEntry entry) async {
    await _repo.skip(_uid, entry);
    _load();
  }

  Future<void> _remove(PlanEntry entry) => deleteWithUndo(
        context,
        label: entry.workout.name,
        delete: () => _repo.removePlanned(entry.id!),
        restore: () => _repo.restorePlanned(entry.id!),
        onChanged: _load,
      );

  Future<void> _editWorkout([Workout? workout]) => editWorkout(context, _uid, workout, onChanged: _load);

  Future<void> _planWorkout() async {
    final result = await showModalBottomSheet<Object>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text('Workout einplanen', style: Theme.of(ctx).textTheme.titleLarge),
            Text(DateFormat('EEEE, d. MMMM', 'de_DE').format(_day), style: Theme.of(ctx).textTheme.labelMedium),
            const SizedBox(height: 8),
            ConstrainedBox(
              constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.5),
              child: ListView(shrinkWrap: true, children: [
                for (final w in _workouts)
                  ListTile(
                    title: Text(w.name),
                    subtitle: Text('${w.exercises.length} Übungen'),
                    onTap: () => Navigator.of(ctx).pop(w),
                  ),
              ]),
            ),
            TextButton.icon(
              onPressed: () => Navigator.of(ctx).pop('new'),
              icon: const Icon(Icons.add_rounded),
              label: const Text('Neues Workout'),
            ),
          ]),
        ),
      ),
    );
    if (result is Workout) {
      await _repo.planWorkout(_uid, result.id!, _day);
      _load();
    } else if (result == 'new') {
      await _editWorkout();
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final plan = _plan;
    return Scaffold(
      floatingActionButton: AppFab(
        heroTag: 'training-fab',
        onPressed: plan == null ? null : _planWorkout,
        label: 'Einplanen',
      ),
      body: plan == null
          ? Center(child: CircularProgressIndicator(color: c.accent))
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: pagePadding(context),
                children: [
                  _weekStrip(context, plan),
                  const SizedBox(height: 16),
                  _dayEntries(context, plan[_day] ?? const []),
                  const SizedBox(height: 20),
                  _links(context),
                ],
              ),
            ),
    );
  }

  Widget _weekStrip(BuildContext context, Map<DateTime, List<PlanEntry>> plan) {
    final c = AppColors.of(context);
    final t = Theme.of(context).textTheme;
    final today = _today();
    final end = DateTime(_weekStart.year, _weekStart.month, _weekStart.day + 6);
    return Column(children: [
      Row(children: [
        IconButton(tooltip: 'Vorherige Woche', icon: const Icon(Icons.chevron_left_rounded), onPressed: () => _shiftWeek(-1)),
        Expanded(
          child: Text(
            '${DateFormat('d. MMM', 'de_DE').format(_weekStart)} – ${DateFormat('d. MMM', 'de_DE').format(end)}',
            textAlign: TextAlign.center,
            style: t.titleMedium,
          ),
        ),
        IconButton(tooltip: 'Nächste Woche', icon: const Icon(Icons.chevron_right_rounded), onPressed: () => _shiftWeek(1)),
      ]),
      const SizedBox(height: 8),
      Row(children: [
        for (var i = 0; i < 7; i++)
          Builder(builder: (context) {
            final d = DateTime(_weekStart.year, _weekStart.month, _weekStart.day + i);
            final entries = plan[d] ?? const <PlanEntry>[];
            final selected = d == _day;
            final allDone = entries.isNotEmpty && entries.every((e) => e.status != PlanStatus.planned);
            return Expanded(
              child: GestureDetector(
                key: ValueKey('training-day-$i'),
                onTap: () => setState(() => _day = d),
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 2),
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  decoration: BoxDecoration(
                    color: selected ? c.accent : c.card,
                    borderRadius: BorderRadius.circular(12),
                    border: d == today && !selected ? Border.all(color: c.accent) : null,
                  ),
                  child: Column(children: [
                    Text(weekdayShort[i], style: t.labelSmall?.copyWith(color: selected ? c.onAccent : c.muted)),
                    const SizedBox(height: 2),
                    Text('${d.day}', style: t.titleSmall?.copyWith(color: selected ? c.onAccent : c.text)),
                    const SizedBox(height: 4),
                    Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: entries.isEmpty
                            ? Colors.transparent
                            : allDone
                                ? c.positive
                                : (selected ? c.onAccent : c.accent),
                      ),
                    ),
                  ]),
                ),
              ),
            );
          }),
      ]),
    ]);
  }

  Widget _dayEntries(BuildContext context, List<PlanEntry> entries) {
    final c = AppColors.of(context);
    final t = Theme.of(context).textTheme;
    final title = _day == _today() ? 'Heute' : DateFormat('EEEE, d. MMMM', 'de_DE').format(_day);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      SectionTitle(title),
      if (entries.isEmpty)
        AppCard(
          padding: const EdgeInsets.all(16),
          child: Text(
            _workouts.isEmpty ? 'Stell dir zuerst ein Workout zusammen.' : 'Kein Training geplant – Ruhetag oder einplanen?',
            style: t.bodyMedium?.copyWith(color: c.muted),
          ),
        ),
      for (final e in entries)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: SwipeTile(
            id: 'plan-${e.id ?? '${e.workout.id}-${e.date}'}',
            startAction: e.status == PlanStatus.planned
                ? SwipeAction(label: 'Überspringen', icon: Icons.redo_rounded, onPressed: () => _skip(e))
                : null,
            onEdit: () => _editWorkout(e.workout),
            onDelete: e.isFromRepeat || e.id == null ? null : () => _remove(e),
            child: AppCard(
              padding: const EdgeInsets.all(14),
              onTap: () => _editWorkout(e.workout),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Row(children: [
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(e.workout.name, style: t.titleMedium),
                      Text(
                        [
                          switch (e.status) {
                            PlanStatus.done => 'Erledigt',
                            PlanStatus.skipped => 'Übersprungen',
                            PlanStatus.planned => e.isFromRepeat ? 'Wöchentlich' : 'Eingeplant',
                          },
                          e.workout.method?.label ?? '${e.workout.exercises.length} Übungen',
                        ].join(' · '),
                        style: t.labelMedium?.copyWith(color: e.status == PlanStatus.done ? c.positive : null),
                      ),
                    ]),
                  ),
                ]),
                if (e.workout.exercises.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Wrap(spacing: 6, runSpacing: 6, children: [
                    for (final we in e.workout.exercises)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(color: c.cardAlt, borderRadius: BorderRadius.circular(8)),
                        child: Text(_chipLabel(e.workout, we), style: t.labelMedium),
                      ),
                  ]),
                ],
                if (e.status != PlanStatus.skipped) ...[
                  const SizedBox(height: 10),
                  ElevatedButton.icon(
                    onPressed: () => _start(e),
                    icon: Icon(e.sessionId == null ? Icons.play_arrow_rounded : Icons.edit_note_rounded),
                    label: Text(e.sessionId == null ? 'Starten' : (e.status == PlanStatus.done ? 'Protokoll ansehen' : 'Fortsetzen')),
                  ),
                ],
              ]),
            ),
          ),
        ),
    ]);
  }

  static String _chipLabel(Workout w, WorkoutExercise we) => switch (w.method) {
        null => '${we.exercise.name} ${we.summary}',
        TrainingMethod.zirkel => '${we.reps ?? 10}× ${we.exercise.name}',
        _ => we.exercise.name,
      };

  Widget _links(BuildContext context) {
    final c = AppColors.of(context);
    final t = Theme.of(context).textTheme;
    Widget tile(IconData icon, String label, String sub, Widget screen) => Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: AppCard(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            onTap: () => _push(screen),
            child: ListTile(
              contentPadding: EdgeInsets.zero,
              leading: IconTile(icon: icon, color: c.accentText),
              title: Text(label, style: t.titleMedium),
              subtitle: Text(sub, style: t.labelMedium),
              trailing: const Icon(Icons.chevron_right_rounded),
            ),
          ),
        );
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const SectionTitle('Mein Training'),
      tile(Icons.view_list_rounded, 'Workouts', _workouts.isEmpty ? 'Noch keine' : '${_workouts.length} zusammengestellt',
          _WorkoutListScreen(userid: _uid)),
      tile(Icons.menu_book_rounded, 'Übungskatalog', '${exerciseCatalog.length} Übungen mit Animation und deine eigenen',
          CatalogScreen(userid: _uid)),
      tile(Icons.event_note_rounded, 'Beispielpläne', 'Basis bis Chief Class übernehmen', SamplePlansScreen(userid: _uid)),
      tile(Icons.show_chart_rounded, 'Fortschritt', 'Bestwerte und Verlauf', ProgressScreen(userid: _uid)),
    ]);
  }
}

/// Liste der zusammengestellten Workouts.
class _WorkoutListScreen extends StatefulWidget {
  final int userid;
  const _WorkoutListScreen({required this.userid});

  @override
  State<_WorkoutListScreen> createState() => _WorkoutListScreenState();
}

class _WorkoutListScreenState extends State<_WorkoutListScreen> {
  late final WorkoutRepository _repo = context.read<WorkoutRepository>();
  List<Workout>? _workouts;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final list = await _repo.getWorkouts(widget.userid);
    if (mounted) setState(() => _workouts = list);
  }

  Future<void> _edit([Workout? w]) => editWorkout(context, widget.userid, w, onChanged: _load);

  Future<void> _planOnce(Workout w) async {
    final messenger = ScaffoldMessenger.of(context);
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
    await _repo.planWorkout(widget.userid, w.id!, picked);
    messenger.showSnackBar(SnackBar(content: Text('Eingeplant für ${DateFormat('EEEE, d. MMMM', 'de_DE').format(picked)}')));
  }

  Future<void> _startNow(Workout w) async {
    final (entry, session) = await _repo.startNow(widget.userid, w);
    if (!mounted) return;
    await openSessionFor(context, entry.workout, session);
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final t = Theme.of(context).textTheme;
    final list = _workouts;
    return Scaffold(
      appBar: const ModernAppBar(title: 'Workouts'),
      floatingActionButton: AppFab(label: 'Workout', heroTag: 'workout-list-fab', onPressed: () => _edit()),
      body: list == null
          ? Center(child: CircularProgressIndicator(color: c.accent))
          : list.isEmpty
              ? Center(child: Text('Noch keine Workouts', style: t.titleMedium))
              : ListView(padding: pagePadding(context), children: [
                  for (final w in list)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: SwipeTile(
                        id: 'workout-${w.id}',
                        onEdit: () => _edit(w),
                        onDelete: () => deleteWorkoutWithUndo(context, w, onChanged: _load),
                        child: AppCard(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                          onTap: () => _edit(w),
                          child: ListTile(
                            contentPadding: EdgeInsets.zero,
                            title: Text(w.name, style: t.titleMedium),
                            subtitle: Text(
                              [
                                '${w.exercises.length} Übungen',
                                if (w.method != null) w.method!.label,
                                if (w.repeatWeekdays.isNotEmpty) w.repeatWeekdays.map((d) => weekdayShort[d - 1]).join(', '),
                              ].join(' · '),
                              style: t.labelMedium,
                            ),
                            trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                              IconButton(
                                tooltip: 'Einmalig einplanen',
                                icon: const Icon(Icons.event_rounded),
                                onPressed: () => _planOnce(w),
                              ),
                              IconButton(
                                tooltip: 'Jetzt starten',
                                icon: Icon(Icons.play_circle_fill_rounded, color: c.accent, size: 32),
                                onPressed: w.exercises.isEmpty ? null : () => _startNow(w),
                              ),
                            ]),
                          ),
                        ),
                      ),
                    ),
                ]),
    );
  }
}

/// Workout anlegen oder bearbeiten; „Löschen“ im Editor löscht mit „Rückgängig“.
Future<void> editWorkout(BuildContext context, int userid, Workout? workout, {required VoidCallback onChanged}) async {
  final result = await Navigator.of(context).push<Object?>(
    MaterialPageRoute(builder: (_) => WorkoutEditorScreen(userid: userid, workout: workout)),
  );
  if (!context.mounted) return;
  if (result == kDeletedResult && workout != null) {
    await deleteWorkoutWithUndo(context, workout, onChanged: onChanged);
  } else {
    onChanged();
  }
}

Future<void> deleteWorkoutWithUndo(BuildContext context, Workout workout, {required VoidCallback onChanged}) {
  final repo = context.read<WorkoutRepository>();
  return deleteWithUndo(
    context,
    label: workout.name,
    delete: () => repo.deleteWorkout(workout.id!),
    restore: () => repo.restoreWorkout(workout.id!),
    onChanged: onChanged,
  );
}
