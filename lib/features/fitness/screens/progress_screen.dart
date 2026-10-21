import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import 'package:frontend/core/ui/app_actions.dart';
import 'package:frontend/core/ui/app_ui.dart';
import 'package:frontend/core/ui/modern_appbar.dart';
import 'package:frontend/core/ui/theme.dart';
import 'package:frontend/features/fitness/models/workout.dart';
import 'package:frontend/features/fitness/repositories/workout_repository.dart';
import 'package:frontend/features/fitness/screens/exercise_form.dart';

/// Fortschritt je Übung: Bestwert und Verlauf der Bestwerte pro Einheit.
class ProgressScreen extends StatefulWidget {
  final int userid;
  const ProgressScreen({super.key, required this.userid});

  @override
  State<ProgressScreen> createState() => _ProgressScreenState();
}

class _ProgressScreenState extends State<ProgressScreen> {
  late final WorkoutRepository _repo = context.read<WorkoutRepository>();
  List<ExerciseProgress>? _progress;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final exercises = await _repo.getExercises(widget.userid);
    final progress = [for (final e in exercises) await _repo.getProgress(e)];
    progress.sort((a, b) => b.bestPerSession.length.compareTo(a.bestPerSession.length));
    if (mounted) setState(() => _progress = progress);
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final t = Theme.of(context).textTheme;
    final list = _progress;
    final withData = list?.where((p) => p.bestPerSession.isNotEmpty).toList();
    return Scaffold(
      appBar: const ModernAppBar(title: 'Fortschritt'),
      body: list == null
          ? Center(child: CircularProgressIndicator(color: c.accent))
          : withData!.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text('Noch keine protokollierten Sätze.\nStarte ein Training, um Fortschritt zu sehen.',
                        textAlign: TextAlign.center, style: t.bodyMedium?.copyWith(color: c.muted)),
                  ),
                )
              : ListView(
                  padding: detailPadding(context),
                  children: [for (final p in withData) _ProgressCard(progress: p)],
                ),
    );
  }
}

class _ProgressCard extends StatelessWidget {
  final ExerciseProgress progress;
  const _ProgressCard({required this.progress});

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final t = Theme.of(context).textTheme;
    final e = progress.exercise;
    final points = progress.bestPerSession;
    final last = points.last;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: AppCard(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            IconTile(icon: exerciseIcon(e.type), color: c.accentText),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(e.name, style: t.titleMedium, overflow: TextOverflow.ellipsis),
                Text('Zuletzt ${formatValue(e.metric, last.$2)} · ${DateFormat('d.M.', 'de_DE').format(last.$1)}',
                    style: t.labelMedium),
              ]),
            ),
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text(formatValue(e.metric, progress.best!), style: t.titleLarge?.copyWith(color: c.accentText)),
              Text('Bestwert', style: t.labelSmall),
            ]),
          ]),
          if (points.length > 1) ...[
            const SizedBox(height: 12),
            SizedBox(
              height: 80,
              child: LineChart(LineChartData(
                gridData: const FlGridData(show: false),
                titlesData: const FlTitlesData(show: false),
                borderData: FlBorderData(show: false),
                lineTouchData: const LineTouchData(enabled: false),
                lineBarsData: [
                  LineChartBarData(
                    spots: [for (var i = 0; i < points.length; i++) FlSpot(i.toDouble(), points[i].$2.toDouble())],
                    isCurved: true,
                    color: c.accent,
                    barWidth: 3,
                    dotData: const FlDotData(show: true),
                    belowBarData: BarAreaData(show: true, color: c.accent.withValues(alpha: 0.12)),
                  ),
                ],
              )),
            ),
          ],
        ]),
      ),
    );
  }
}
