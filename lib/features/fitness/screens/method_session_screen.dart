import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'package:frontend/core/ui/app_actions.dart';
import 'package:frontend/core/ui/app_ui.dart';
import 'package:frontend/core/ui/dialogs.dart';
import 'package:frontend/core/ui/modern_appbar.dart';
import 'package:frontend/core/ui/theme.dart';
import 'package:frontend/features/fitness/catalog/exercise_motion.dart';
import 'package:frontend/features/fitness/models/method_timer.dart';
import 'package:frontend/features/fitness/models/workout.dart';
import 'package:frontend/features/fitness/repositories/workout_repository.dart';
import 'package:frontend/features/fitness/screens/catalog_screen.dart';
import 'package:frontend/features/fitness/screens/session_screen.dart';

/// Öffnet eine Einheit: bei Trainingsformen den Timer, sonst (oder zum Nachsehen
/// eines erledigten Trainings) das Satz-Protokoll. Liefert `true`, wenn gespeichert wurde.
Future<bool?> openSessionFor(BuildContext context, Workout workout, WorkoutSession session, {bool review = false}) {
  final Widget screen = workout.method != null && !review
      ? MethodSessionScreen(workout: workout, session: session)
      : SessionScreen(session: session);
  return Navigator.of(context).push<bool>(MaterialPageRoute(builder: (_) => screen));
}

String formatClock(Duration d) {
  final s = d.isNegative ? 0 : d.inSeconds;
  return '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
}

/// Training mit Timer passend zur Trainingsform (Stufenintervall, Intervallsatz, Supersatz,
/// Zirkel, Hochintensität). Gibt `true` zurück, wenn die Einheit gespeichert wurde.
class MethodSessionScreen extends StatefulWidget {
  final Workout workout;
  final WorkoutSession session;

  /// Für Tests: Timer nicht automatisch per Sekundentakt laufen lassen.
  final bool autoTick;

  const MethodSessionScreen({super.key, required this.workout, required this.session, this.autoTick = true});

  @override
  State<MethodSessionScreen> createState() => MethodSessionScreenState();
}

class MethodSessionScreenState extends State<MethodSessionScreen> {
  late final MethodTimer timer = MethodTimer.forWorkout(widget.workout);
  late final WorkoutRepository _repo = context.read<WorkoutRepository>();
  Timer? _ticker;
  bool _running = false;
  bool _started = false;
  bool _saving = false;
  int _lastCue = 0;
  Duration _elapsed = Duration.zero;

  /// Eingabewerte für Intervall-/Supersätze (je Übung der aktuellen Gruppe).
  final Map<int, int> _repsInput = {};

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  void _start() {
    setState(() {
      _started = true;
      _running = true;
    });
    if (widget.autoTick) _ticker = Timer.periodic(const Duration(seconds: 1), (_) => advance(const Duration(seconds: 1)));
  }

  void _togglePause() => setState(() => _running = !_running);

  /// Zeit weiterdrehen (vom Sekundentakt oder in Tests).
  void advance(Duration dt) {
    if (!_running || timer.finished) return;
    setState(() {
      _elapsed += dt;
      timer.tick(dt);
    });
    _signal();
  }

  void _act(void Function() action) {
    setState(action);
    _signal();
  }

  void _signal() {
    if (timer.cues == _lastCue) return;
    _lastCue = timer.cues;
    HapticFeedback.mediumImpact();
    SystemSound.play(SystemSoundType.alert);
    if (timer.finished) _ticker?.cancel();
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    final navigator = Navigator.of(context);
    if (!timer.finished) timer.finish();
    final minutes = _elapsed.inMinutes;
    final ok = await runGuarded(context, () async {
      await _repo.addSets(widget.session.id, widget.workout.userid, timer.log);
      await _repo.finishSession(widget.session, durationMin: minutes < 1 ? null : minutes);
      return true;
    });
    if (ok != true) {
      if (mounted) setState(() => _saving = false);
      return;
    }
    navigator.pop(true);
  }

  Future<void> _confirmFinish() async {
    final ok = await confirmDestructive(
      context,
      title: 'Training beenden?',
      message: 'Bisher Geschafftes wird gespeichert.',
      confirmLabel: 'Beenden',
    );
    if (ok) await _save();
  }

  int _defaultReps(int indexInGroup) => switch (widget.workout.method) {
        TrainingMethod.supersatz => indexInGroup == 0 ? 3 : 8,
        _ => 8,
      };

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final t = Theme.of(context).textTheme;
    final method = widget.workout.method!;
    return Scaffold(
      appBar: ModernAppBar(title: widget.workout.name),
      body: SafeArea(
        child: ListView(padding: detailPadding(context), children: [
          Row(children: [
            AppChip(label: method.label, selected: true),
            const SizedBox(width: 8),
            Expanded(child: Text(method.short, style: t.labelMedium, maxLines: 2, overflow: TextOverflow.ellipsis)),
          ]),
          const SizedBox(height: 12),
          _exerciseCard(context),
          const SizedBox(height: 16),
          Center(
            child: ScoreRing(
              progress: timer.progress,
              color: timer.phase == TimerPhase.work ? c.accent : c.event,
              track: c.cardAlt,
              size: 190,
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Text(
                  // Verlängerung beim Stufenintervall: Zeit über 7:30 hinaus
                  '${timer is StufenTimer && (timer as StufenTimer).overtime ? '+' : ''}${formatClock(timer.clock)}',
                  style: t.displaySmall?.copyWith(fontFeatures: const [FontFeature.tabularFigures()]),
                ),
                const SizedBox(height: 4),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 18),
                  child: Text(timer.headline, textAlign: TextAlign.center, style: t.labelMedium, maxLines: 2),
                ),
              ]),
            ),
          ),
          const SizedBox(height: 16),
          if (!_started)
            ElevatedButton.icon(onPressed: _start, icon: const Icon(Icons.play_arrow_rounded), label: const Text("Los geht's"))
          else if (timer.finished)
            _summary(context)
          else ...[
            _controls(context),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _togglePause,
                  icon: Icon(_running ? Icons.pause_rounded : Icons.play_arrow_rounded),
                  label: Text(_running ? 'Pause' : 'Weiter'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _act(timer.skip),
                  icon: const Icon(Icons.skip_next_rounded),
                  label: const Text('Weiter zur nächsten'),
                ),
              ),
            ]),
            const SizedBox(height: 8),
            TextButton(onPressed: _saving ? null : _confirmFinish, child: const Text('Training beenden')),
          ],
          const SizedBox(height: 12),
          Text(method.description, style: t.bodySmall?.copyWith(color: c.muted)),
          if (widget.workout.notes != null) ...[
            const SizedBox(height: 8),
            Text(widget.workout.notes!, style: t.bodySmall?.copyWith(color: c.muted)),
          ],
        ]),
      ),
    );
  }

  Widget _exerciseCard(BuildContext context) {
    final c = AppColors.of(context);
    final t = Theme.of(context).textTheme;
    // In der Pause bzw. im Wechsel vor der nächsten Übung wird diese schon groß gezeigt.
    final preview = timer.upNext;
    final current = preview ?? timer.current;
    final next = preview != null || timer is ZirkelTimer || timer.groupIndex >= timer.groups.length - 1
        ? null
        : timer.groups[timer.groupIndex + 1].map((e) => e.exercise.name).join(' + ');
    return AppCard(
      padding: const EdgeInsets.all(12),
      color: preview != null ? c.accent.withValues(alpha: 0.12) : null,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (preview != null)
          Text('Gleich: Übung ${timer.groupIndex + 2} von ${timer.groups.length} – mach dich bereit',
              style: t.labelMedium?.copyWith(color: c.accentText, fontWeight: FontWeight.w700))
        else if (timer is! ZirkelTimer)
          Text('Übung ${timer.groupIndex + 1} von ${timer.groups.length}', style: t.labelMedium),
        for (final we in current)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Row(children: [
              GestureDetector(
                onTap: we.exercise.catalog == null
                    ? null
                    : () => openCatalogDetail(context, userid: we.exercise.userid, entry: we.exercise.catalog!),
                child: Container(
                  decoration: BoxDecoration(color: c.cardAlt, borderRadius: BorderRadius.circular(12)),
                  child: we.exercise.catalog == null
                      ? ExerciseThumb(exercise: we.exercise, size: current.length > 2 ? 44 : 72)
                      : ExerciseAnimation(
                          motion: we.exercise.catalog!.motion,
                          size: current.length > 2 ? 44 : 72,
                          animate: current.length <= 2 && widget.autoTick,
                        ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(we.exercise.name, style: t.titleMedium),
                  if (timer is ZirkelTimer)
                    Text(widget.workout.targetOf(we), style: t.labelMedium),
                ]),
              ),
            ]),
          ),
        if (next != null) ...[
          const SizedBox(height: 8),
          Text('Als Nächstes: $next', style: t.labelMedium?.copyWith(color: c.muted)),
        ],
      ]),
    );
  }

  Widget _controls(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final c = AppColors.of(context);
    final timer = this.timer;
    switch (timer) {
      case StufenTimer():
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          ElevatedButton.icon(
            onPressed: timer.phase == TimerPhase.work && _running ? () => _act(timer.stepDone) : null,
            icon: const Icon(Icons.check_rounded),
            label: Text('Stufe ${timer.step} geschafft'),
          ),
          const SizedBox(height: 8),
          OutlinedButton(
            onPressed: timer.phase == TimerPhase.work && timer.ascending && _running ? () => _act(timer.muscleFailure) : null,
            child: Text('Muskelversagen bei Stufe ${timer.step} – ab jetzt abwärts'),
          ),
          const SizedBox(height: 6),
          Text(
            'Bisher ${timer.totalReps} Wdh. · höchste Stufe ${timer.highestStep} · '
            '${timer.overtime ? 'Verlängerung – danach Pause und nächste Übung' : 'Übung noch ${formatClock(timer.clock)}'}',
            textAlign: TextAlign.center,
            style: t.labelMedium,
          ),
        ]);
      case IntervalTimer():
        if (timer.phase == TimerPhase.rest) {
          return Text('Satz eingetragen – der nächste startet automatisch.',
              textAlign: TextAlign.center, style: t.bodyMedium?.copyWith(color: c.muted));
        }
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          for (final (i, we) in timer.current.indexed)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _Stepper(
                label: we.exercise.metric == ExerciseMetric.time ? '${we.exercise.name} (s)' : we.exercise.name,
                value: _repsInput[i] ?? _defaultReps(i),
                onChanged: (v) => setState(() => _repsInput[i] = v),
              ),
            ),
          ElevatedButton.icon(
            onPressed: _running
                ? () => _act(() {
                      timer.logRound([for (var i = 0; i < timer.current.length; i++) _repsInput[i] ?? _defaultReps(i)]);
                      _repsInput.clear();
                    })
                : null,
            icon: const Icon(Icons.check_rounded),
            label: Text(timer.isSuperset ? 'Supersatz geschafft' : 'Satz geschafft'),
          ),
        ]);
      case ZirkelTimer():
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          ElevatedButton.icon(
            onPressed: _running ? () => _act(timer.roundDone) : null,
            icon: const Icon(Icons.loop_rounded),
            label: const Text('Runde geschafft'),
          ),
          const SizedBox(height: 6),
          Text('${timer.rounds} Runden', textAlign: TextAlign.center, style: t.titleMedium),
        ]);
      case HochTimer():
        // Hier zählt nur Tempo: so viele saubere Wiederholungen wie möglich, nichts mitzählen.
        return Text(
          timer.phase == TimerPhase.work ? 'So schnell wie möglich – sauber bleiben!' : 'Kurz durchatmen.',
          textAlign: TextAlign.center,
          style: t.titleMedium?.copyWith(color: c.muted),
        );
    }
  }

  Widget _summary(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final byExercise = <String, num>{};
    for (final s in timer.log) {
      byExercise[s.exercise.name] = (byExercise[s.exercise.name] ?? 0) + (s.value ?? 0);
    }
    return AppCard(
      padding: const EdgeInsets.all(14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('Stark! Training geschafft.', style: t.titleMedium),
        const SizedBox(height: 6),
        for (final e in byExercise.entries) Text('${e.key}: ${e.value.round()}', style: t.bodyMedium),
        if (byExercise.isEmpty) Text('Keine Werte erfasst.', style: t.bodyMedium),
        const SizedBox(height: 12),
        ElevatedButton.icon(
          onPressed: _saving ? null : _save,
          icon: const Icon(Icons.save_rounded),
          label: const Text('Speichern'),
        ),
      ]),
    );
  }
}

class _Stepper extends StatelessWidget {
  final String label;
  final int value;
  final ValueChanged<int> onChanged;
  const _Stepper({required this.label, required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return AppCard(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Row(children: [
        Expanded(child: Text(label, style: t.bodyLarge, maxLines: 2, overflow: TextOverflow.ellipsis)),
        IconButton(tooltip: 'Weniger', onPressed: value > 0 ? () => onChanged(value - 1) : null, icon: const Icon(Icons.remove_rounded)),
        SizedBox(width: 32, child: Text('$value', textAlign: TextAlign.center, style: t.titleMedium)),
        IconButton(tooltip: 'Mehr', onPressed: () => onChanged(value + 1), icon: const Icon(Icons.add_rounded)),
      ]),
    );
  }
}
