import 'package:frontend/features/fitness/models/workout.dart';

/// Ein während eines Timer-Trainings erfasster Satz.
class LoggedSet {
  final Exercise exercise;
  final int setIndex;
  final num? value;
  const LoggedSet(this.exercise, this.setIndex, this.value);
}

enum TimerPhase { work, rest, change, finished }

/// Ablaufsteuerung eines Workouts je nach Trainingsform. Die Zeit wird von außen mit
/// [tick] weitergedreht (im Screen per Sekundentakt, in Tests direkt) – so bleibt die Logik testbar.
sealed class MethodTimer {
  MethodTimer(this.workout) : groups = workout.groups;

  factory MethodTimer.forWorkout(Workout workout) => switch (workout.method!) {
        TrainingMethod.stufen => StufenTimer(workout),
        TrainingMethod.intervall => IntervalTimer(workout, TrainingMethod.intervallSets, TrainingMethod.intervallEvery),
        TrainingMethod.supersatz => IntervalTimer(workout, TrainingMethod.supersatzRounds, TrainingMethod.supersatzEvery),
        TrainingMethod.zirkel => ZirkelTimer(workout),
        TrainingMethod.hochintensiv => HochTimer(workout),
      };

  final Workout workout;
  final List<List<WorkoutExercise>> groups;
  final List<LoggedSet> log = [];

  int groupIndex = 0;
  TimerPhase phase = TimerPhase.work;

  /// Zählt Phasenwechsel – der Screen gibt bei jeder Änderung ein Signal (Ton/Vibration).
  int cues = 0;

  bool get finished => phase == TimerPhase.finished;
  List<WorkoutExercise> get current => groups.isEmpty ? const [] : groups[groupIndex.clamp(0, groups.length - 1)];

  /// Große Uhr im Screen.
  Duration get clock;

  /// Kurze Zeile über der Uhr, z. B. „Satz 2 von 3“.
  String get headline;

  /// Fortschritt 0…1 der aktuellen Phase (für den Ring).
  double get progress;

  /// Die nächste Übung (bzw. das nächste Paar), solange gerade die Pause bzw. der Wechsel davor läuft –
  /// so kann man sich schon darauf vorbereiten. Sonst `null`.
  List<WorkoutExercise>? get upNext => null;

  List<WorkoutExercise>? get _nextGroup => groupIndex < groups.length - 1 ? groups[groupIndex + 1] : null;

  static String names(List<WorkoutExercise> group) => group.map((we) => we.exercise.name).join(' + ');

  void tick(Duration dt);

  /// Zur nächsten Übung (bzw. Übungspaar) springen.
  void skip();

  /// Training vorzeitig beenden; bereits Geleistetes wird übernommen.
  void finish();

  void _cue() => cues++;

  void _end() {
    phase = TimerPhase.finished;
    _cue();
  }
}

Duration _max(Duration a, Duration b) => a > b ? a : b;
double _ratio(Duration left, Duration total) =>
    total.inMilliseconds == 0 ? 0 : (1 - left.inMilliseconds / total.inMilliseconds).clamp(0.0, 1.0);

// ─── Stufenintervall ──────────────────────────────────────────────────────

/// 7:30 min pro Übung: Stufe 1, 2, 3 … mit Pausen so lang wie die vorige Arbeitsphase.
/// Mit [muscleFailure] zählt die Stufe als geschafft und es geht danach abwärts weiter.
/// Ein Satz, der vor Ablauf der 7:30 begonnen hat, wird zu Ende gebracht („Verlängerung“);
/// danach gilt die übliche Pause (so lang wie der Satz), erst dann beginnt die nächste Übung.
class StufenTimer extends MethodTimer {
  StufenTimer(super.workout);

  Duration blockLeft = TrainingMethod.stufenBlock;
  Duration workElapsed = Duration.zero;
  Duration restLeft = Duration.zero;
  Duration _restTotal = Duration.zero;
  Duration _workTotal = Duration.zero;
  int step = 1;
  bool ascending = true;
  int totalReps = 0;
  int highestStep = 0;

  /// Die 7:30 sind abgelaufen, der zuvor begonnene Satz läuft noch.
  bool get overtime => phase == TimerPhase.work && blockLeft < Duration.zero;

  /// Nach diesem Satz bzw. dieser Pause ist die Übung vorbei.
  bool get _blockOver => blockLeft <= Duration.zero;

  @override
  Duration get clock => phase == TimerPhase.rest ? restLeft : (blockLeft.isNegative ? -blockLeft : blockLeft);

  @override
  String get headline => switch (phase) {
        TimerPhase.rest when _blockOver && upNext != null => 'Pause – danach: ${MethodTimer.names(upNext!)}',
        TimerPhase.rest => 'Pause – danach Stufe $step',
        TimerPhase.finished => 'Geschafft',
        _ when overtime => 'Zeit um – Stufe $step noch zu Ende',
        _ => 'Stufe $step · ${ascending ? 'aufwärts' : 'abwärts'}',
      };

  @override
  List<WorkoutExercise>? get upNext => phase == TimerPhase.rest && _blockOver ? _nextGroup : null;

  @override
  double get progress => phase == TimerPhase.rest
      ? _ratio(restLeft, _restTotal)
      : (overtime ? 1 : _ratio(blockLeft, TrainingMethod.stufenBlock));

  /// Kürzeste Pause nach einer Stufe.
  static const minRest = Duration(seconds: 1);

  /// Stufe geschafft → Pause so lang wie die Arbeitsphase (mindestens [minRest]).
  void stepDone() => _completeStep(failure: false);

  /// Muskelversagen bei der aktuellen Stufe: Sie zählt als geschafft, die Pause startet sofort
  /// und danach geht es mit der nächstniedrigeren Stufe abwärts weiter.
  void muscleFailure() => _completeStep(failure: true);

  void _completeStep({required bool failure}) {
    if (phase != TimerPhase.work) return;
    totalReps += step;
    if (step > highestStep) highestStep = step;
    _workTotal += workElapsed;
    _restTotal = _max(workElapsed, minRest);
    restLeft = _restTotal;
    workElapsed = Duration.zero;
    if (failure) ascending = false;
    if (ascending) {
      step++;
    } else {
      step--;
      if (step < 1) {
        step = 1;
        ascending = true;
      }
    }
    // Letzter Satz der letzten Übung: keine Pause mehr nötig
    if (_blockOver && _nextGroup == null) {
      _logGroup();
      return _end();
    }
    phase = TimerPhase.rest;
    _cue();
  }

  @override
  void tick(Duration dt) {
    if (finished) return;
    blockLeft -= dt;
    if (phase == TimerPhase.work) {
      // Ein laufender Satz wird nie abgebrochen – auch nicht nach 7:30.
      workElapsed += dt;
      return;
    }
    if (phase == TimerPhase.rest) {
      restLeft -= dt;
      if (restLeft <= Duration.zero) {
        restLeft = Duration.zero;
        if (_blockOver) return _toNextGroup();
        phase = TimerPhase.work;
        _cue();
      }
    }
  }

  void _logGroup() {
    for (final we in current) {
      final seconds = (_workTotal + (phase == TimerPhase.work ? workElapsed : Duration.zero)).inSeconds;
      final value = we.exercise.metric == ExerciseMetric.reps ? totalReps : seconds;
      if (value > 0) log.add(LoggedSet(we.exercise, 0, value));
    }
  }

  void _toNextGroup() {
    _logGroup();
    if (groupIndex >= groups.length - 1) return _end();
    groupIndex++;
    blockLeft = TrainingMethod.stufenBlock;
    workElapsed = restLeft = _workTotal = Duration.zero;
    step = 1;
    ascending = true;
    totalReps = highestStep = 0;
    phase = TimerPhase.work;
    _cue();
  }

  @override
  void skip() => _toNextGroup();

  @override
  void finish() {
    if (finished) return;
    _logGroup();
    _end();
  }
}

// ─── Intervallsatz & Supersatz ────────────────────────────────────────────

/// Feste Intervalle: alle [every] beginnt ein Satz (bzw. Supersatz), [rounds] pro Übung/Paar.
/// Nach dem Satz trägt man die geschafften Wiederholungen ein; der Rest des Intervalls ist Pause.
class IntervalTimer extends MethodTimer {
  IntervalTimer(super.workout, this.rounds, this.every) : left = every;

  final int rounds;
  final Duration every;
  Duration left;
  int round = 0;

  bool get isSuperset => workout.method == TrainingMethod.supersatz;

  @override
  Duration get clock => left;

  @override
  String get headline => switch (phase) {
        TimerPhase.finished => 'Geschafft',
        TimerPhase.rest when upNext != null => 'Pause – danach: ${MethodTimer.names(upNext!)}',
        TimerPhase.rest => 'Pause bis zum nächsten ${isSuperset ? 'Supersatz' : 'Satz'}',
        _ => '${isSuperset ? 'Supersatz' : 'Satz'} ${round + 1} von $rounds',
      };

  @override
  double get progress => _ratio(left, every);

  @override
  List<WorkoutExercise>? get upNext => phase == TimerPhase.rest && round >= rounds - 1 ? _nextGroup : null;

  /// Satz erledigt: Werte in der Reihenfolge von [current] (null = nicht eingetragen).
  void logRound(List<num?> values) {
    if (phase != TimerPhase.work) return;
    for (final (i, we) in current.indexed) {
      final v = i < values.length ? values[i] : null;
      if (v != null && v > 0) log.add(LoggedSet(we.exercise, round, v));
    }
    final last = groupIndex >= groups.length - 1 && round >= rounds - 1;
    if (last) return _end();
    phase = TimerPhase.rest;
    _cue();
  }

  void _advance() {
    round++;
    if (round >= rounds) {
      round = 0;
      if (groupIndex >= groups.length - 1) return _end();
      groupIndex++;
    }
    left = every;
    phase = TimerPhase.work;
    _cue();
  }

  @override
  void tick(Duration dt) {
    if (finished) return;
    left -= dt;
    if (left <= Duration.zero) _advance();
  }

  @override
  void skip() {
    if (finished) return;
    if (groupIndex >= groups.length - 1) return _end();
    groupIndex++;
    round = 0;
    left = every;
    phase = TimerPhase.work;
    _cue();
  }

  @override
  void finish() {
    if (!finished) _end();
  }
}

// ─── Zirkelintervall ──────────────────────────────────────────────────────

/// 20 Minuten: so viele Runden aller Übungen wie möglich.
class ZirkelTimer extends MethodTimer {
  ZirkelTimer(super.workout);

  Duration left = TrainingMethod.zirkelTotal;
  int rounds = 0;

  @override
  List<WorkoutExercise> get current => workout.exercises;

  @override
  Duration get clock => left;

  @override
  String get headline => finished ? 'Geschafft – $rounds Runden' : 'Runde ${rounds + 1} · $rounds geschafft';

  @override
  double get progress => _ratio(left, TrainingMethod.zirkelTotal);

  void roundDone() {
    if (finished) return;
    rounds++;
    _cue();
  }

  void _logAll() {
    if (rounds == 0) return;
    for (final we in workout.exercises) {
      final perRound = we.exercise.metric == ExerciseMetric.reps ? (we.reps ?? 10) : (we.durationSec ?? 30);
      log.add(LoggedSet(we.exercise, 0, perRound * rounds));
    }
  }

  @override
  void tick(Duration dt) {
    if (finished) return;
    left -= dt;
    if (left <= Duration.zero) finish();
  }

  @override
  void skip() => finish();

  @override
  void finish() {
    if (finished) return;
    _logAll();
    _end();
  }
}

// ─── Hochintensitätssatz ──────────────────────────────────────────────────

/// Pro Übung 8 Runden à 20 s Training / 10 s Pause, danach 60 s Wechsel zur nächsten Übung.
/// Es zählt nur das Tempo – Wiederholungen werden nicht erfasst, protokolliert wird die Zeit.
class HochTimer extends MethodTimer {
  HochTimer(super.workout);

  Duration left = TrainingMethod.hochWork;
  int round = 0;

  Duration get _phaseTotal => switch (phase) {
        TimerPhase.work => TrainingMethod.hochWork,
        TimerPhase.rest => TrainingMethod.hochRest,
        TimerPhase.change => TrainingMethod.hochSwitch,
        TimerPhase.finished => Duration.zero,
      };

  @override
  Duration get clock => left;

  @override
  String get headline => switch (phase) {
        TimerPhase.work => 'Runde ${round + 1} von ${TrainingMethod.hochRounds} – los!',
        TimerPhase.rest => 'Pause',
        TimerPhase.change => 'Wechsel – gleich: ${MethodTimer.names(upNext ?? const [])}',
        TimerPhase.finished => 'Geschafft',
      };

  @override
  double get progress => _ratio(left, _phaseTotal);

  @override
  List<WorkoutExercise>? get upNext => phase == TimerPhase.change ? _nextGroup : null;

  /// Nur die Belastungszeit wird festgehalten (bei Übungen, die in Zeit gemessen werden).
  void _logGroup() {
    for (final we in current) {
      if (we.exercise.metric != ExerciseMetric.time) continue;
      final value = round * TrainingMethod.hochWork.inSeconds;
      if (value > 0) log.add(LoggedSet(we.exercise, 0, value));
    }
  }

  void _startGroup(int index) {
    groupIndex = index;
    round = 0;
    phase = TimerPhase.work;
    left = TrainingMethod.hochWork;
  }

  void _transition() {
    switch (phase) {
      case TimerPhase.work:
        if (round >= TrainingMethod.hochRounds - 1) {
          round++;
          _logGroup();
          if (groupIndex >= groups.length - 1) return _end();
          phase = TimerPhase.change;
          left += TrainingMethod.hochSwitch;
        } else {
          phase = TimerPhase.rest;
          left += TrainingMethod.hochRest;
        }
      case TimerPhase.rest:
        round++;
        phase = TimerPhase.work;
        left += TrainingMethod.hochWork;
      case TimerPhase.change:
        final carry = left;
        _startGroup(groupIndex + 1);
        left += carry;
      case TimerPhase.finished:
        return;
    }
    _cue();
  }

  @override
  void tick(Duration dt) {
    if (finished) return;
    left -= dt;
    while (!finished && left <= Duration.zero) {
      _transition();
    }
  }

  @override
  void skip() {
    if (finished) return;
    if (phase != TimerPhase.change) _logGroup();
    if (groupIndex >= groups.length - 1) return _end();
    _startGroup(groupIndex + 1);
    _cue();
  }

  @override
  void finish() {
    if (finished) return;
    if (phase == TimerPhase.work || phase == TimerPhase.rest) _logGroup();
    _end();
  }
}
