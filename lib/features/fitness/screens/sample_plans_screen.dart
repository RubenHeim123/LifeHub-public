import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import 'package:frontend/core/ui/app_actions.dart';
import 'package:frontend/core/ui/app_ui.dart';
import 'package:frontend/core/ui/modern_appbar.dart';
import 'package:frontend/core/ui/theme.dart';
import 'package:frontend/features/fitness/catalog/exercise_catalog.dart';
import 'package:frontend/features/fitness/catalog/sample_plans.dart';
import 'package:frontend/features/fitness/models/workout.dart';
import 'package:frontend/features/fitness/repositories/workout_repository.dart';
import 'package:frontend/features/fitness/screens/catalog_screen.dart';

/// Übersicht der Beispiel-Trainingspläne.
class SamplePlansScreen extends StatelessWidget {
  final int userid;
  const SamplePlansScreen({super.key, required this.userid});

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final t = Theme.of(context).textTheme;
    return Scaffold(
      appBar: const ModernAppBar(title: 'Beispielpläne'),
      body: ListView(padding: detailPadding(context), children: [
        Text('10-Wochen-Programme mit dem eigenen Körpergewicht. Übernimm einen Block als eigene Workouts – '
            'jeder Tag hat seine Trainingsform, der Timer führt dich beim Start durch Sätze und Pausen.',
            style: t.bodyMedium?.copyWith(color: c.muted)),
        const SizedBox(height: 12),
        for (final plan in samplePlans)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: AppCard(
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => SamplePlanScreen(userid: userid, plan: plan)),
              ),
              padding: const EdgeInsets.all(14),
              child: Row(children: [
                IconTile(icon: Icons.event_note_rounded, color: c.accentText),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(plan.name, style: t.titleMedium),
                    Text('${plan.audience} · ${plan.blocks.length} Blöcke', style: t.labelMedium),
                    const SizedBox(height: 4),
                    Text(plan.description, style: t.bodySmall, maxLines: 2, overflow: TextOverflow.ellipsis),
                  ]),
                ),
                const Icon(Icons.chevron_right_rounded),
              ]),
            ),
          ),
      ]),
    );
  }
}

/// Ein Plan mit seinen Blöcken und Tagen; jeder Block lässt sich übernehmen.
class SamplePlanScreen extends StatelessWidget {
  final int userid;
  final SamplePlan plan;
  const SamplePlanScreen({super.key, required this.userid, required this.plan});

  Future<void> _import(BuildContext context, PlanBlock block) async {
    final messenger = ScaffoldMessenger.of(context);
    final repo = context.read<WorkoutRepository>();
    final choice = await showDialog<(List<int>, bool, DateTime)>(
      context: context,
      builder: (_) => _WeekdayDialog(block: block),
    );
    if (choice == null) return;
    final (weekdays, once, start) = choice;
    final ids = await repo.importSampleBlock(userid, plan, block, weekdays: weekdays, once: once, start: start);
    messenger.showSnackBar(SnackBar(content: Text('${ids.length} Workouts angelegt – zu finden unter „Workouts“')));
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final t = Theme.of(context).textTheme;
    return Scaffold(
      appBar: ModernAppBar(title: plan.name),
      body: ListView(padding: detailPadding(context), children: [
        Text(plan.description, style: t.bodyMedium),
        if (plan.requirements != null) ...[
          const SizedBox(height: 12),
          AppCard(
            padding: const EdgeInsets.all(14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Einstiegstest', style: t.titleSmall),
              const SizedBox(height: 4),
              Text(plan.requirements!, style: t.bodySmall),
            ]),
          ),
        ],
        for (final block in plan.blocks) ...[
          const SizedBox(height: 16),
          SectionTitle('${block.title} · ${block.focus}'),
          for (final (i, day) in block.days.indexed)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: AppCard(
                padding: const EdgeInsets.all(12),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Tag ${i + 1} · ${day.title}', style: t.titleSmall),
                  Text('${day.method.label} · ${day.method.short}', style: t.labelMedium?.copyWith(color: c.accentText)),
                  const SizedBox(height: 6),
                  for (final (g, group) in day.groups.indexed)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Wrap(crossAxisAlignment: WrapCrossAlignment.center, spacing: 6, runSpacing: 4, children: [
                        if (group.length > 1) Text('${g + 1}.', style: t.labelMedium),
                        for (final (k, item) in group.indexed) ...[
                          if (k > 0) Text('+', style: t.labelMedium),
                          _ItemChip(userid: userid, item: item),
                        ],
                      ]),
                    ),
                ]),
              ),
            ),
          OutlinedButton.icon(
            onPressed: () => _import(context, block),
            icon: const Icon(Icons.download_rounded),
            label: Text('${block.title} übernehmen'),
          ),
        ],
      ]),
    );
  }
}

class _ItemChip extends StatelessWidget {
  final int userid;
  final PlanItem item;
  const _ItemChip({required this.userid, required this.item});

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final t = Theme.of(context).textTheme;
    final entry = catalogByKey[item.key];
    final label = [
      if (item.reps != null) '${item.reps}×',
      entry?.name ?? item.key,
      if (item.note != null) '(${item.note})',
    ].join(' ');
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: entry == null ? null : () => openCatalogDetail(context, userid: userid, entry: entry),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(color: c.cardAlt, borderRadius: BorderRadius.circular(8)),
        child: Text(label, style: t.labelMedium),
      ),
    );
  }
}

/// Wochentage für die Tage des Blocks wählen (der Reihe nach zugeordnet).
class _WeekdayDialog extends StatefulWidget {
  final PlanBlock block;
  const _WeekdayDialog({required this.block});

  @override
  State<_WeekdayDialog> createState() => _WeekdayDialogState();
}

class _WeekdayDialogState extends State<_WeekdayDialog> {
  late final Set<int> _days = widget.block.days.length >= 5 ? {1, 2, 3, 4, 5} : {1, 2, 4, 5};
  bool _once = false;
  DateTime _start = _today();

  static DateTime _today() {
    final n = DateTime.now();
    return DateTime(n.year, n.month, n.day);
  }

  Future<void> _pickStart() async {
    final today = _today();
    final picked = await showDatePicker(
      context: context,
      initialDate: _start,
      firstDate: today,
      lastDate: DateTime(today.year + 1, today.month, today.day),
      helpText: 'Einplanen ab',
    );
    if (picked != null) setState(() => _start = DateTime(picked.year, picked.month, picked.day));
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final n = widget.block.days.length;
    return AlertDialog(
      title: Text('${widget.block.title} übernehmen'),
      content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('$n Trainingstage – an welchen Wochentagen?', style: t.bodyMedium),
        const SizedBox(height: 10),
        Wrap(spacing: 6, runSpacing: 6, children: [
          AppChip(label: 'Jede Woche', selected: !_once, onTap: () => setState(() => _once = false)),
          AppChip(label: 'Einmalig', selected: _once, onTap: () => setState(() => _once = true)),
        ]),
        if (_once) ...[
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: _pickStart,
            icon: const Icon(Icons.event_rounded),
            label: Text(_start == _today() ? 'Ab heute' : 'Ab ${DateFormat('EEEE, d. MMMM', 'de_DE').format(_start)}'),
          ),
        ],
        const SizedBox(height: 12),
        Wrap(spacing: 6, runSpacing: 6, children: [
          for (var d = 1; d <= 7; d++)
            AppChip(
              label: weekdayShort[d - 1],
              selected: _days.contains(d),
              onTap: () => setState(() => _days.contains(d) ? _days.remove(d) : _days.add(d)),
            ),
        ]),
        const SizedBox(height: 8),
        Text(
          _once
              ? 'Jeder Tag wird einmal am nächsten passenden Wochentag ab dem Startdatum eingeplant.'
              : 'Ohne Auswahl werden die Workouts nur angelegt, nicht eingeplant.',
          style: t.labelSmall,
        ),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Abbrechen')),
        ElevatedButton(onPressed: () => Navigator.of(context).pop((_days.toList()..sort(), _once, _start)), child: const Text('Übernehmen')),
      ],
    );
  }
}
