import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:frontend/core/ui/app_actions.dart';
import 'package:frontend/core/ui/app_ui.dart';
import 'package:frontend/core/ui/modern_appbar.dart';
import 'package:frontend/core/ui/theme.dart';
import 'package:frontend/features/fitness/catalog/exercise_howto.dart';
import 'package:frontend/features/fitness/catalog/exercise_catalog.dart';
import 'package:frontend/features/fitness/catalog/exercise_motion.dart';
import 'package:frontend/features/fitness/models/workout.dart';
import 'package:frontend/features/fitness/repositories/workout_repository.dart';
import 'package:frontend/features/fitness/screens/exercise_form.dart';

/// Vorschaubild einer Übung: Standbild der Animation (Katalog) oder Icon.
class ExerciseThumb extends StatelessWidget {
  final Exercise exercise;
  final double size;
  const ExerciseThumb({super.key, required this.exercise, this.size = 44});

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final entry = exercise.catalog;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: c.cardAlt, borderRadius: BorderRadius.circular(size * 0.25)),
      child: entry == null
          ? Icon(_typeIcon(exercise.type), color: c.accentText, size: size * 0.5)
          : ExerciseAnimation(motion: entry.motion, size: size, animate: false),
    );
  }

  static IconData _typeIcon(ExerciseType type) => switch (type) {
        ExerciseType.strength => Icons.fitness_center_rounded,
        ExerciseType.run => Icons.directions_run_rounded,
        ExerciseType.skill => Icons.sports_gymnastics_rounded,
        ExerciseType.other => Icons.sports_rounded,
      };
}

/// Öffnet die Detailseite einer Katalog-Übung.
Future<Exercise?> openCatalogDetail(BuildContext context, {required int userid, required CatalogExercise entry, bool pick = false}) {
  return Navigator.of(context).push<Exercise>(
    MaterialPageRoute(builder: (_) => CatalogDetailScreen(userid: userid, entry: entry, pick: pick)),
  );
}

/// Der eine Übungskatalog: mitgelieferte Übungen (mit Animation) und eigene Übungen, mit Suche
/// und Filter. Eigene Übungen legt man über „Eigene Übung“ an; Wischen bearbeitet bzw. löscht sie.
/// Mit [pick] = true liefert der Screen die gewählte Übung zurück (Katalogübungen werden dabei
/// in die eigenen Übungen übernommen).
class CatalogScreen extends StatefulWidget {
  final int userid;
  final bool pick;
  const CatalogScreen({super.key, required this.userid, this.pick = false});

  @override
  State<CatalogScreen> createState() => _CatalogScreenState();
}

class _CatalogScreenState extends State<CatalogScreen> {
  late final WorkoutRepository _repo = context.read<WorkoutRepository>();
  String _query = '';
  CatalogCategory? _category;
  bool _ownOnly = false;

  /// Eigene Übungen ohne Katalog-Bezug (Katalogübungen erscheinen im Katalogteil).
  List<Exercise> _own = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    var list = await _repo.getExercises(widget.userid);
    if (list.isEmpty) {
      await _repo.createStarterExercises(widget.userid);
      list = await _repo.getExercises(widget.userid);
    }
    if (mounted) setState(() => _own = list.where((e) => e.catalogKey == null).toList());
  }

  bool _matches(String text) => _query.trim().isEmpty || text.toLowerCase().contains(_query.trim().toLowerCase());

  List<CatalogExercise> get _filtered => _ownOnly
      ? const []
      : exerciseCatalog
          .where((e) => _category == null || e.category == _category)
          .where((e) => _matches(e.name) || _matches(e.muscles))
          .toList();

  List<Exercise> get _ownFiltered => _category != null ? const [] : _own.where((e) => _matches(e.name)).toList();

  Future<void> _open(CatalogExercise entry) async {
    final navigator = Navigator.of(context);
    final picked = await openCatalogDetail(context, userid: widget.userid, entry: entry, pick: widget.pick);
    if (widget.pick && picked != null) navigator.pop(picked);
  }

  Future<void> _openOwn(Exercise e) async {
    if (widget.pick) {
      Navigator.of(context).pop(e);
      return;
    }
    await _edit(e);
  }

  Future<void> _edit([Exercise? e]) async {
    final navigator = Navigator.of(context);
    final id = await showExerciseDialog(context, userid: widget.userid, exercise: e);
    if (id == null) return;
    await _load();
    if (!mounted || !widget.pick || e != null) return;
    final created = _own.where((x) => x.id == id).firstOrNull;
    if (created != null) navigator.pop(created);
  }

  Future<void> _delete(Exercise e) => deleteWithUndo(
        context,
        label: e.name,
        delete: () => _repo.deleteExercise(e.id!),
        restore: () => _repo.restoreExercise(e.id!),
        onChanged: _load,
      );

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final t = Theme.of(context).textTheme;
    final list = _filtered;
    final own = _ownFiltered;
    return Scaffold(
      appBar: ModernAppBar(title: widget.pick ? 'Übung wählen' : 'Übungskatalog'),
      floatingActionButton: AppFab(label: 'Eigene Übung', heroTag: 'exercise-fab', onPressed: () => _edit()),
      body: ListView(padding: pagePadding(context), children: [
        TextField(
          decoration: const InputDecoration(prefixIcon: Icon(Icons.search_rounded), hintText: 'Übung oder Muskel suchen'),
          onChanged: (v) => setState(() => _query = v),
        ),
        const SizedBox(height: 10),
        Wrap(spacing: 6, runSpacing: 6, children: [
          AppChip(
            label: 'Alle',
            count: exerciseCatalog.length + _own.length,
            selected: _category == null && !_ownOnly,
            onTap: () => setState(() {
              _category = null;
              _ownOnly = false;
            }),
          ),
          AppChip(
            label: 'Eigene',
            count: _own.length,
            selected: _ownOnly,
            onTap: () => setState(() {
              _ownOnly = !_ownOnly;
              _category = null;
            }),
          ),
          for (final cat in CatalogCategory.values)
            AppChip(
              label: cat.label,
              count: exerciseCatalog.where((e) => e.category == cat).length,
              selected: _category == cat,
              onTap: () => setState(() {
                _category = _category == cat ? null : cat;
                _ownOnly = false;
              }),
            ),
        ]),
        const SizedBox(height: 12),
        if (list.isEmpty && own.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 32),
            child: Text(
              _ownOnly ? 'Noch keine eigenen Übungen – leg über „Eigene Übung“ eine an.' : 'Keine Übung gefunden',
              textAlign: TextAlign.center,
              style: t.bodyMedium?.copyWith(color: c.muted),
            ),
          ),
        if (own.isNotEmpty) ...[
          GroupLabel('Eigene Übungen', trailing: '${own.length}'),
          for (final e in own)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: SwipeTile(
                id: 'exercise-${e.id}',
                onEdit: () => _edit(e),
                onDelete: () => _delete(e),
                child: AppCard(
                  onTap: () => _openOwn(e),
                  padding: const EdgeInsets.all(10),
                  child: Row(children: [
                    ExerciseThumb(exercise: e, size: 56),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(e.name, style: t.titleMedium, maxLines: 2, overflow: TextOverflow.ellipsis),
                        Text('${e.type.label} · ${e.metric.label}', style: t.labelMedium),
                      ]),
                    ),
                  ]),
                ),
              ),
            ),
          if (list.isNotEmpty) const SizedBox(height: 8),
        ],
        if (list.isNotEmpty && own.isNotEmpty) GroupLabel('Katalog', trailing: '${list.length}'),
        for (final e in list)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: AppCard(
              onTap: () => _open(e),
              padding: const EdgeInsets.all(10),
              child: Row(children: [
                Container(
                  decoration: BoxDecoration(color: c.cardAlt, borderRadius: BorderRadius.circular(12)),
                  child: ExerciseAnimation(motion: e.motion, size: 56, animate: false),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(e.name, style: t.titleMedium, maxLines: 2, overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 2),
                    Text(e.muscles, style: t.labelMedium, maxLines: 1, overflow: TextOverflow.ellipsis),
                  ]),
                ),
                const SizedBox(width: 8),
                Text(e.levelLabel, style: t.labelSmall?.copyWith(color: c.accentText)),
              ]),
            ),
          ),
      ]),
    );
  }
}

/// Detailseite: Animation, Muskeln, Stufe und Anleitung einer Katalog-Übung.
class CatalogDetailScreen extends StatefulWidget {
  final int userid;
  final CatalogExercise entry;
  final bool pick;
  const CatalogDetailScreen({super.key, required this.userid, required this.entry, this.pick = false});

  @override
  State<CatalogDetailScreen> createState() => _CatalogDetailScreenState();
}

class _CatalogDetailScreenState extends State<CatalogDetailScreen> {
  late final WorkoutRepository _repo = context.read<WorkoutRepository>();
  bool? _inLibrary;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _repo.getExercises(widget.userid).then((list) {
      if (mounted) setState(() => _inLibrary = list.any((e) => e.catalogKey == widget.entry.key));
    });
  }

  Future<void> _add() async {
    setState(() => _busy = true);
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final exercise = await runGuarded(context, () => _repo.addFromCatalog(widget.userid, widget.entry.key));
    if (exercise == null) {
      if (mounted) setState(() => _busy = false);
      return;
    }
    if (widget.pick) {
      navigator.pop(exercise);
      return;
    }
    messenger.showSnackBar(SnackBar(content: Text('„${exercise.name}“ ist in deinen Übungen')));
    if (mounted) {
      setState(() {
        _busy = false;
        _inLibrary = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final t = Theme.of(context).textTheme;
    final e = widget.entry;
    Widget section(String title, String text, {Color? color}) => Padding(
          padding: const EdgeInsets.only(top: 14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: t.titleSmall?.copyWith(color: color)),
            const SizedBox(height: 4),
            Text(text, style: t.bodyMedium),
          ]),
        );
    return Scaffold(
      appBar: ModernAppBar(title: e.name),
      body: SafeArea(
        child: ListView(padding: const EdgeInsets.all(16), children: [
          AppCard(
            padding: const EdgeInsets.all(12),
            child: Center(child: ExerciseAnimation(motion: e.motion, size: 220)),
          ),
          const SizedBox(height: 12),
          Wrap(spacing: 6, runSpacing: 6, children: [
            AppChip(label: e.category.label),
            AppChip(label: e.levelLabel),
            AppChip(label: e.metric == ExerciseMetric.time ? 'Auf Zeit' : 'Wiederholungen'),
          ]),
          section('Muskeln', e.muscles),
          if (e.howTo.isNotEmpty) section('Ausführung', e.howTo),
          if (e.easier != null) section('Leichter', e.easier!, color: c.positive),
          if (e.harder != null) section('Schwerer', e.harder!, color: c.streak),
          const SizedBox(height: 24),
          if (_inLibrary == true && !widget.pick)
            OutlinedButton.icon(
              onPressed: null,
              icon: const Icon(Icons.check_rounded),
              label: const Text('In deinen Übungen'),
            )
          else
            ElevatedButton.icon(
              onPressed: _inLibrary == null || _busy ? null : _add,
              icon: Icon(widget.pick ? Icons.add_task_rounded : Icons.add_rounded),
              label: Text(widget.pick ? 'Auswählen' : 'Zu meinen Übungen'),
            ),
          if (exerciseHowToSource != null) ...[
            const SizedBox(height: 8),
            Text(exerciseHowToSource!, style: t.labelSmall?.copyWith(color: c.muted), textAlign: TextAlign.center),
          ],
        ]),
      ),
    );
  }
}
