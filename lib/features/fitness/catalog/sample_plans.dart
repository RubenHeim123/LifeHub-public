/// Beispiel-Trainingspläne: 10-Wochen-Programme mit dem eigenen Körpergewicht.
/// Jeder Plan besteht aus Blöcken (z. B. „Woche 1–2“) mit Trainingstagen.
library;

import 'package:frontend/features/fitness/models/training_method.dart';

export 'package:frontend/features/fitness/models/training_method.dart';

/// Eine Übung im Plan, optional mit Variante (z. B. „Hände erhöht“) oder fester Anzahl (Zirkel).
class PlanItem {
  final String key;
  final String? note;
  final int? reps;
  const PlanItem(this.key, [this.note, this.reps]);
}

class PlanDay {
  final String title;
  final TrainingMethod method;

  /// Gruppen von Übungen; bei Supersätzen je ein Übungspaar, sonst eine Übung pro Gruppe.
  final List<List<PlanItem>> groups;
  const PlanDay(this.title, this.method, this.groups);

  Iterable<PlanItem> get items => groups.expand((g) => g);
}

class PlanBlock {
  final String title;
  final String focus;
  final List<PlanDay> days;
  const PlanBlock(this.title, this.focus, this.days);
}

class SamplePlan {
  final String key;
  final String name;
  final String audience;
  final String description;

  /// Einstiegstest (was man schaffen sollte, bevor man mit dem Plan startet).
  final String? requirements;
  final List<PlanBlock> blocks;
  const SamplePlan(this.key, this.name, this.audience, this.description, this.blocks, {this.requirements});
}

// ─── Kurzschreibweisen ────────────────────────────────────────────────────

PlanItem _i(String key, [String? note, int? reps]) => PlanItem(key, note, reps);

PlanDay _d(String title, TrainingMethod m, List<PlanItem> items) => PlanDay(title, m, [for (final i in items) [i]]);

PlanDay _s(String title, List<List<PlanItem>> pairs) => PlanDay(title, TrainingMethod.supersatz, pairs);

const _st = TrainingMethod.stufen;
const _iv = TrainingMethod.intervall;
const _hi = TrainingMethod.hochintensiv;
const _zi = TrainingMethod.zirkel;

const _h13 = '1–3 s Haltezeit am tiefsten Punkt';
const _h46 = '4–6 s Haltezeit am tiefsten Punkt';
const _h46top = '4–6 s Haltezeit am höchsten Punkt';
const _neg = 'Füße auf Stuhl oder hochspringen, langsam absenken';

/// Zirkel am 5. Tag der Wechselblöcke.
PlanDay _zirkelBasis() => _d('Zirkel', _zi, [
      _i('ausfallschritt_hinten', 'im Wechsel', 10),
      _i('tuerziehen', null, 8),
      _i('liegestuetz', null, 6),
    ]);
PlanDay _zirkelFirst() => _d('Zirkel', _zi, [
      _i('umgekehrtes_bankdruecken', 'Knie gebeugt', 6),
      _i('seitlicher_ausfallschritt', 'im Wechsel', 12),
      _i('liegestuetz', null, 8),
    ]);
PlanDay _zirkelMaster() => _d('Zirkel', _zi, [
      _i('einbeinige_kniebeuge', 'im Wechsel, mit Stuhl – oder Kistensprünge', 12),
      _i('sturzflug', null, 6),
      _i('umgekehrtes_bankdruecken', null, 8),
    ]);
PlanDay _zirkelChief() => _d('Zirkel', _zi, [
      _i('pistole', 'im Wechsel (6 pro Seite) – oder 24 Iron Mikes', 12),
      _i('handstandliegestuetz', null, 6),
      _i('tuerklimmzug', null, 8),
    ]);

final List<SamplePlan> samplePlans = [
  // ─── Basisprogramm ─────────────────────────────────────────────────────
  SamplePlan(
    'basis',
    'Basisprogramm',
    'Einsteiger',
    '10-Wochen-Programm für den Einstieg: erst Ausdauer, dann Kraft, dann Power – 4 Trainingstage pro Woche, ab Woche 9 fünf.',
    [
      PlanBlock('Woche 1–2', 'Muskuläre Ausdauer', [
        _d('Drücken/Ziehen', _st, [_i('liegestuetz', 'Hände erhöht'), _i('tuerziehen'), _i('trizepsdip_stuhl', 'Füße auf dem Boden'), _i('umgekehrtes_bankdruecken', 'Knie gebeugt')]),
        _d('Beine/Core', _st, [_i('ausfallschritt_hinten', 'im Wechsel'), _i('rumaenisches_kreuzheben', 'im Wechsel'), _i('kniebeuge'), _i('schwimmer')]),
        _d('Drücken/Ziehen', _st, [_i('liegestuetz', 'Hände erhöht'), _i('tuerziehen'), _i('trizepsdip_stuhl', 'Füße auf dem Boden'), _i('umgekehrtes_bankdruecken', 'Knie gebeugt')]),
        _d('Beine/Core', _st, [_i('seitlicher_ausfallschritt'), _i('rumaenisches_kreuzheben', 'im Wechsel'), _i('kniebeuge', _h13), _i('crunch', 'schräg')]),
      ]),
      PlanBlock('Woche 3–4', 'Kraft', [
        _d('Drücken', _iv, [_i('liegestuetz'), _i('military_press', 'Hände erhöht'), _i('enger_liegestuetz', 'Hände erhöht'), _i('trizepsdip_stuhl')]),
        _d('Beine', _iv, [_i('kniebeuge_ausfallschritt'), _i('seitlicher_ausfallschritt'), _i('kniebeuge', _h13), _i('rumaenisches_kreuzheben', 'auf einem Kissen')]),
        _d('Ziehen', _iv, [_i('tuerziehen'), _i('umgekehrtes_bankdruecken', 'Knie gebeugt'), _i('tuerziehen', 'Untergriff'), _i('curl_handtuch')]),
        _d('Core', _iv, [_i('beinheber'), _i('superman', 'Strecken: Hände unter dem Kinn'), _i('russischer_twist'), _i('schwimmer')]),
      ]),
      PlanBlock('Woche 5–6', 'Power-Block', [
        _s('Drücken', [
          [_i('liegestuetz', 'Füße erhöht'), _i('liegestuetz_abstossen')],
          [_i('military_press'), _i('daumen_hoch')],
          [_i('enger_liegestuetz'), _i('trizepsdip_stuhl')],
        ]),
        _s('Beine', [
          [_i('ausfallschritt_hinten', 'im Wechsel, $_h46'), _i('gesprungene_kniebeuge')],
          [_i('ausfallschritt', 'im Wechsel, $_h46'), _i('seitlicher_ausfallschritt')],
          [_i('rumaenisches_kreuzheben', 'auf einem Kissen'), _i('kniebeuge', _h13)],
        ]),
        _s('Ziehen', [
          [_i('tuerklimmzug', _neg), _i('tuerziehen')],
          [_i('tuerziehen', _h46top), _i('curl_handtuch')],
          [_i('umgekehrtes_bankdruecken', 'Untergriff, Beine gestreckt'), _i('tuerziehen', 'Untergriff')],
        ]),
        _s('Core', [
          [_i('v_up'), _i('russischer_twist')],
          [_i('superman'), _i('schwimmer')],
          [_i('haengendes_beinheben', 'Knie gebeugt'), _i('beinheber')],
        ]),
      ]),
      PlanBlock('Woche 9', 'Wechselblock', [
        _d('Drücken', _iv, [_i('liegestuetz'), _i('military_press', 'Hände erhöht'), _i('enger_liegestuetz', 'Hände erhöht')]),
        _d('Beine', _hi, [_i('beat_your_boots'), _i('ausfallschritt'), _i('good_morning')]),
        _d('Ziehen', _st, [_i('umgekehrtes_bankdruecken', 'Knie gebeugt'), _i('tuerziehen'), _i('umgekehrtes_bankdruecken', 'Untergriff, Knie gebeugt'), _i('tuerziehen', 'Untergriff')]),
        _s('Core', [
          [_i('v_up'), _i('russischer_twist')],
          [_i('superman'), _i('schwimmer')],
          [_i('fahrradfahren'), _i('beinheber')],
        ]),
        _zirkelBasis(),
      ]),
      PlanBlock('Woche 10', 'Wechselblock', [
        _s('Drücken', [
          [_i('liegestuetz', 'Füße erhöht'), _i('liegestuetz_abstossen')],
          [_i('military_press'), _i('daumen_hoch')],
          [_i('enger_liegestuetz'), _i('trizepsdip_stuhl', 'Füße auf dem Boden')],
        ]),
        _d('Beine', _iv, [_i('kniebeuge_ausfallschritt'), _i('seitlicher_ausfallschritt'), _i('kniebeuge', _h46), _i('rumaenisches_kreuzheben', 'auf einem Kissen')]),
        _d('Ziehen', _hi, [_i('tuerziehen', 'Füße hinter den Händen'), _i('fliegende_graetsche'), _i('curl_handtuch')]),
        _d('Core', _st, [_i('crunch_it_up'), _i('superman', 'Strecken: Arme eng am Körper'), _i('beinheber'), _i('superman', 'Strecken: nur Unterkörper')]),
        _zirkelBasis(),
      ]),
    ],
    requirements: 'Für alle, die gesund genug für hartes Training sind. Woche 7–8 fehlen in den Fotos.',
  ),

  // ─── First Class ───────────────────────────────────────────────────────
  SamplePlan(
    'first_class',
    'First Class',
    'Trainingserfahrene',
    '10 Wochen für Trainingserfahrene: Ausdauer, Kraft, Power und ab Woche 7 ein Wechselblock mit 5 Tagen.',
    [
      PlanBlock('Woche 1–2', 'Muskuläre Ausdauer', [
        _d('Drücken/Ziehen', _st, [_i('liegestuetz'), _i('umgekehrtes_bankdruecken'), _i('military_press'), _i('tuerziehen')]),
        _d('Beine/Core', _st, [_i('ausfallschritt_hinten', 'im Wechsel, $_h13'), _i('rumaenisches_kreuzheben', 'im Wechsel'), _i('gesprungene_kniebeuge', _h13), _i('superman', 'Strecken: Arme eng am Körper')]),
        _d('Drücken/Ziehen', _st, [_i('liegestuetz'), _i('umgekehrtes_bankdruecken'), _i('military_press'), _i('tuerziehen')]),
        _d('Beine/Core', _st, [_i('seitlicher_ausfallschritt', 'im Wechsel, $_h13'), _i('rumaenisches_kreuzheben', 'im Wechsel'), _i('gesprungene_kniebeuge', _h13), _i('russischer_twist')]),
      ]),
      PlanBlock('Woche 3–4', 'Kraft', [
        _d('Drücken', _iv, [_i('liegestuetz', 'Füße erhöht'), _i('military_press'), _i('enger_liegestuetz'), _i('trizepsdip_stuhl', 'Füße auf einem Stuhl')]),
        _d('Beine', _iv, [_i('kniebeuge_ausfallschritt', _h13), _i('seitlicher_ausfallschritt', _h46), _i('gesprungene_kniebeuge', _h46), _i('rumaenisches_kreuzheben', 'auf einem Kissen')]),
        _d('Ziehen', _iv, [_i('tuerklimmzug', _neg), _i('umgekehrtes_bankdruecken'), _i('tuerziehen'), _i('curl_handtuch')]),
        _d('Core', _iv, [_i('beinheber', 'Arme gekreuzt auf der Brust'), _i('superman'), _i('fahrradfahren'), _i('superman', 'Strecken: Hände unter dem Kinn')]),
      ]),
      PlanBlock('Woche 5–6', 'Power-Block', [
        _s('Drücken', [
          [_i('liegestuetz', 'Füße erhöht, $_h13'), _i('liegestuetz_abstossen')],
          [_i('military_press', 'Füße erhöht'), _i('daumen_hoch')],
          [_i('enger_liegestuetz', 'Füße erhöht'), _i('trizepsdip')],
        ]),
        _s('Beine', [
          [_i('einbeinige_kniebeuge', 'im Wechsel, beide Hände an einer Stuhllehne'), _i('gesprungene_kniebeuge', _h46)],
          [_i('seitlicher_ausfallschritt', 'im Wechsel, $_h46'), _i('ausfallschritt_hinten', 'im Wechsel, $_h13')],
          [_i('rumaenisches_kreuzheben', 'auf einem Kissen, $_h13'), _i('kistensprung')],
        ]),
        _s('Ziehen', [
          [_i('tuerklimmzug'), _i('tuerziehen')],
          [_i('tuerziehen', _h46top), _i('umgekehrtes_bankdruecken')],
          [_i('umgekehrtes_bankdruecken', 'Untergriff, Füße erhöht'), _i('tuerziehen', 'Untergriff')],
        ]),
        _s('Core', [
          [_i('haengendes_beinheben', 'Knie gebeugt'), _i('beintwist', 'Knie gebeugt')],
          [_i('hueftstrecker', 'einbeinig im Wechsel'), _i('superman')],
          [_i('v_up'), _i('russischer_twist')],
        ]),
      ]),
      PlanBlock('Woche 7', 'Wechselblock', [
        _d('Drücken', _st, [_i('chinesischer_liegestuetz'), _i('liegestuetz'), _i('enger_liegestuetz'), _i('trizepsdip_stuhl')]),
        _s('Beine', [
          [_i('einbeinige_kniebeuge', 'im Wechsel, an zwei Stühlen'), _i('gesprungene_kniebeuge', _h46)],
          [_i('seitlicher_ausfallschritt', 'im Wechsel, $_h46'), _i('ausfallschritt_hinten', 'im Wechsel, $_h13')],
          [_i('rumaenisches_kreuzheben', 'im Wechsel auf einem Kissen, 1–3 s Pause'), _i('kistensprung')],
        ]),
        _d('Ziehen', _iv, [_i('tuerklimmzug', _neg), _i('umgekehrtes_bankdruecken'), _i('tuerziehen'), _i('curl_handtuch')]),
        _d('Core', _hi, [_i('russischer_twist'), _i('beinscheren_crunch'), _i('kniebeuge')]),
        _zirkelFirst(),
      ]),
      PlanBlock('Woche 8', 'Wechselblock', [
        _d('Drücken', _hi, [_i('liegestuetz', 'Hände erhöht'), _i('trizepsdip_stuhl', 'Füße auf dem Boden'), _i('kniebeuge')]),
        _d('Beine', _st, [_i('ausfallschritt_hinten', 'im Wechsel, $_h13'), _i('seitlicher_ausfallschritt'), _i('gesprungene_kniebeuge', _h13), _i('rumaenisches_kreuzheben', 'im Wechsel')]),
        _s('Ziehen', [
          [_i('tuerklimmzug'), _i('tuerziehen')],
          [_i('tuerziehen', _h46top), _i('umgekehrtes_bankdruecken')],
          [_i('umgekehrtes_bankdruecken', 'Untergriff, Füße erhöht'), _i('tuerziehen', 'Untergriff')],
        ]),
        _d('Core', _iv, [_i('beinheber', 'Arme gekreuzt auf der Brust'), _i('superman'), _i('fahrradfahren'), _i('superman', 'Strecken: Hände unter dem Kinn')]),
        _zirkelFirst(),
      ]),
      PlanBlock('Woche 9', 'Wechselblock', [
        _d('Drücken', _iv, [_i('liegestuetz', 'Füße erhöht'), _i('chinesischer_liegestuetz', 'Hände erhöht'), _i('enger_liegestuetz', 'Hände erhöht'), _i('trizepsdip_stuhl')]),
        _d('Beine', _hi, [_i('iron_mike'), _i('seitsprung'), _i('kniebeuge')]),
        _d('Ziehen', _st, [_i('umgekehrtes_bankdruecken'), _i('tuerziehen'), _i('umgekehrtes_bankdruecken', 'Untergriff'), _i('tuerziehen', 'Untergriff')]),
        _s('Core', [
          [_i('haengendes_beinheben', 'Knie gebeugt'), _i('beintwist')],
          [_i('hueftstrecker', 'einbeinig im Wechsel'), _i('superman')],
          [_i('v_up'), _i('russischer_twist')],
        ]),
        _zirkelFirst(),
      ]),
      PlanBlock('Woche 10', 'Wechselblock', [
        _s('Drücken', [
          [_i('liegestuetz', 'Füße erhöht, $_h13'), _i('liegestuetz_abstossen')],
          [_i('military_press', 'Füße erhöht'), _i('ueberkopfpresse')],
          [_i('enger_liegestuetz', 'Füße erhöht'), _i('trizepsdip_stuhl')],
        ]),
        _d('Beine', _iv, [_i('kniebeuge_ausfallschritt', _h13), _i('seitlicher_ausfallschritt', _h46), _i('gesprungene_kniebeuge', _h46), _i('rumaenisches_kreuzheben', 'auf einem Kissen')]),
        _d('Ziehen', _hi, [_i('umgekehrtes_bankdruecken'), _i('tuerziehen'), _i('kniebeuge')]),
        _d('Core', _st, [_i('fahrradfahren'), _i('superman', 'Strecken: Hände unter dem Kinn'), _i('gegraetschter_beinscheren_crunch'), _i('schwimmer')]),
        _zirkelFirst(),
      ]),
    ],
    requirements: '10 Liegestütze (je 2 s halten oben und unten) · 10× umgekehrtes Bankdrücken mit gestreckten Beinen · '
        '15 Ausfallschritte nach hinten pro Bein (3 s halten) · 1 Minute Liegestützposition halten.',
  ),

  // ─── Master Class ──────────────────────────────────────────────────────
  SamplePlan(
    'master_class',
    'Master Class',
    'Fortgeschrittene',
    '10 Wochen für Fortgeschrittene mit einarmigen Liegestützen, einbeinigen Kniebeugen und Klimmzügen.',
    [
      PlanBlock('Woche 1–2', 'Muskuläre Ausdauer', [
        _d('Drücken/Ziehen', _st, [_i('einarmiger_liegestuetz', 'im Wechsel, Hand erhöht'), _i('tuerklimmzug', _neg), _i('military_press', 'Füße erhöht'), _i('umgekehrtes_bankdruecken')]),
        _d('Beine/Core', _st, [_i('einbeinige_kniebeuge', 'im Wechsel, an Stuhllehne oder von erhöhter Fläche'), _i('ausfallschritt_hinten', _h46), _i('hueftstrecker'), _i('superman')]),
        _d('Drücken/Ziehen', _st, [_i('einarmiger_liegestuetz', 'im Wechsel, Hand erhöht'), _i('tuerklimmzug', _neg), _i('military_press'), _i('tuerziehen')]),
        _d('Beine/Core', _st, [_i('einbeinige_kniebeuge', 'im Wechsel, an Stuhllehne oder von erhöhter Fläche'), _i('seitlicher_ausfallschritt', 'im Wechsel, $_h13'), _i('rumaenisches_kreuzheben', 'im Wechsel auf einem Kissen'), _i('beintwist', 'Knie gebeugt')]),
      ]),
      PlanBlock('Woche 3–4', 'Kraft', [
        _d('Drücken', _iv, [_i('einarmiger_liegestuetz', 'Hand erhöht'), _i('sturzflug'), _i('military_press', 'Füße erhöht'), _i('trizepsdip')]),
        _d('Beine', _iv, [_i('einbeinige_kniebeuge', 'an Stuhllehne oder von erhöhter Fläche'), _i('kniebeuge_ausfallschritt', _h46), _i('seitlicher_ausfallschritt', _h46), _i('hueftstrecker', 'einbeinig')]),
        _d('Ziehen', _iv, [_i('tuerklimmzug'), _i('tuerziehen', '1–3 s Haltezeit am höchsten Punkt'), _i('umgekehrtes_bankdruecken'), _i('umgekehrtes_bankdruecken', 'Untergriff')]),
        _d('Core', _iv, [_i('haengendes_beinheben', 'Beine parallel zum Boden'), _i('rueckenheber'), _i('v_up'), _i('superman')]),
      ]),
      PlanBlock('Woche 5–6', 'Power-Block', [
        _s('Drücken', [
          [_i('einarmiger_liegestuetz'), _i('federnder_liegestuetz')],
          [_i('military_press', 'Füße erhöht'), _i('sturzflug')],
          [_i('erhoehter_trizepsstrecker'), _i('liegestuetz_abstossen')],
        ]),
        _s('Beine', [
          [_i('pistole'), _i('kistensprung')],
          [_i('sissy_kniebeuge'), _i('iron_mike')],
          [_i('fallender_liegestuetz'), _i('seitsprung')],
        ]),
        _s('Ziehen', [
          [_i('tuerklimmzug'), _i('tuerziehen')],
          [_i('tuerziehen', 'einarmig'), _i('umgekehrtes_bankdruecken', 'Untergriff')],
          [_i('tuerziehen', 'Untergriff, $_h46top'), _i('curl_handtuch')],
        ]),
        _s('Core', [
          [_i('haengendes_beinheben'), _i('fahrradfahren')],
          [_i('rueckenheber'), _i('superman')],
          [_i('v_up'), _i('beintwist', 'Knie gebeugt')],
        ]),
      ]),
      PlanBlock('Woche 7', 'Wechselblock', [
        _d('Drücken', _st, [_i('einarmiger_liegestuetz', 'Hände kniehoch erhöht'), _i('sturzflug'), _i('trizepsdip'), _i('trizepsdip_stuhl')]),
        _s('Beine', [
          [_i('pistole'), _i('sissy_kniebeuge')],
          [_i('kistensprung'), _i('iron_mike')],
          [_i('fallender_liegestuetz'), _i('seitsprung')],
        ]),
        _d('Ziehen', _iv, [_i('tuerklimmzug'), _i('tuerziehen', '1–3 s Haltezeit am höchsten Punkt'), _i('umgekehrtes_bankdruecken'), _i('umgekehrtes_bankdruecken', 'Untergriff')]),
        _d('Core', _hi, [_i('schraeger_v_up', '4 Sätze pro Seite'), _i('beinscheren_crunch', 'Arme gekreuzt auf der Brust'), _i('kniebeuge')]),
        _zirkelMaster(),
      ]),
      PlanBlock('Woche 8', 'Wechselblock', [
        _d('Drücken', _hi, [_i('liegestuetz'), _i('liegestuetz_abstossen'), _i('kniebeuge')]),
        _d('Beine', _st, [_i('einbeinige_kniebeuge', 'mit Stuhl'), _i('sissy_kniebeuge'), _i('seitlicher_ausfallschritt', _h13), _i('hueftstrecker')]),
        _s('Ziehen', [
          [_i('tuerklimmzug'), _i('umgekehrtes_bankdruecken')],
          [_i('tuerziehen', 'einarmig'), _i('umgekehrtes_bankdruecken', 'Untergriff, Füße erhöht')],
          [_i('tuerziehen', 'Untergriff'), _i('curl_handtuch')],
        ]),
        _d('Core', _iv, [_i('haengendes_beinheben', 'Beine gestreckt bis parallel zum Boden'), _i('rueckenheber'), _i('v_up'), _i('superman')]),
        _zirkelMaster(),
      ]),
      PlanBlock('Woche 9', 'Wechselblock', [
        _d('Drücken', _iv, [_i('einarmiger_liegestuetz', 'Hände erhöht'), _i('sturzflug'), _i('military_press', 'Füße erhöht'), _i('trizepsdip')]),
        _d('Beine', _hi, [_i('iron_mike'), _i('seitsprung'), _i('kniebeuge')]),
        _d('Ziehen', _st, [_i('tuerklimmzug', 'mit Stuhl'), _i('umgekehrtes_bankdruecken'), _i('umgekehrtes_bankdruecken', 'Untergriff'), _i('tuerziehen')]),
        _s('Core', [
          [_i('haengendes_beinheben'), _i('fahrradfahren')],
          [_i('rueckenheber'), _i('superman')],
          [_i('v_up'), _i('beintwist', 'Knie gebeugt')],
        ]),
        _zirkelMaster(),
      ]),
      PlanBlock('Woche 10', 'Wechselblock', [
        _s('Drücken', [
          [_i('einarmiger_liegestuetz'), _i('federnder_liegestuetz')],
          [_i('military_press', 'Füße erhöht'), _i('sturzflug')],
          [_i('erhoehter_trizepsstrecker'), _i('liegestuetz_abstossen')],
        ]),
        _d('Beine', _iv, [_i('einbeinige_kniebeuge', 'mit Stuhl oder von erhöhter Fläche'), _i('kniebeuge_ausfallschritt', _h46), _i('seitlicher_ausfallschritt', _h46), _i('hueftstrecker', 'einbeinig')]),
        _d('Ziehen', _hi, [_i('umgekehrtes_bankdruecken'), _i('tuerziehen'), _i('kniebeuge')]),
        _d('Core', _st, [_i('schraeger_v_up', 'Knie gebeugt'), _i('fliegende_graetsche'), _i('beinheber', 'Arme gekreuzt auf der Brust'), _i('superman', 'Strecken: Hände unter dem Kinn')]),
        _zirkelMaster(),
      ]),
    ],
    requirements: '16 einarmige Liegestütze (Hand auf mittelhoher Fläche, Seite im Wechsel) · 4 Klimmzüge (je 2 s halten) · '
        '24 einbeinige Kniebeugen im Wechsel (Gesäß darf kurz absetzen) · 3 Minuten Liegestützposition halten.',
  ),

  // ─── Chief Class ───────────────────────────────────────────────────────
  SamplePlan(
    'chief_class',
    'Chief Class',
    'Spitzensportler',
    'Die härteste Stufe: Handstandliegestütze, Pistolen, einarmiges Türziehen und Klappmesser.',
    [
      PlanBlock('Woche 1–2', 'Muskuläre Ausdauer', [
        _d('Drücken/Ziehen', _st, [_i('einarmiger_liegestuetz', 'im Wechsel, Hand erhöht'), _i('tuerklimmzug'), _i('sturzflug'), _i('umgekehrtes_bankdruecken', 'Füße erhöht')]),
        _d('Beine/Core', _st, [_i('pistole', 'im Wechsel'), _i('iron_mike'), _i('hueftstrecker', 'einbeinig im Wechsel'), _i('rueckenheber')]),
        _d('Drücken/Ziehen', _st, [_i('einarmiger_liegestuetz', 'im Wechsel, Hand erhöht'), _i('tuerklimmzug'), _i('military_press', 'Füße erhöht'), _i('tuerziehen', 'einarmig im Wechsel')]),
        _d('Beine/Core', _st, [_i('einbeinige_kniebeuge', 'im Wechsel'), _i('kistensprung'), _i('sissy_kniebeuge'), _i('beintwist')]),
      ]),
      PlanBlock('Woche 3–4', 'Kraft', [
        _d('Drücken', _iv, [_i('einarmiger_liegestuetz'), _i('handstandliegestuetz'), _i('sturzflug'), _i('erhoehter_trizepsstrecker', 'etwa hüfthoch')]),
        _d('Beine', _iv, [_i('pistole'), _i('kniebeuge_ausfallschritt', _h46), _i('sissy_kniebeuge'), _i('iron_mike')]),
        _d('Ziehen', _iv, [_i('tuerklimmzug', '1–3 s Haltezeit am höchsten Punkt'), _i('tuerziehen', 'einarmig'), _i('umgekehrtes_bankdruecken', 'Untergriff, Füße erhöht'), _i('tuerziehen', _h46top)]),
        _d('Core', _iv, [_i('haengendes_beinheben', 'bis ganz nach oben'), _i('rueckenheber'), _i('klappmesser'), _i('superman')]),
      ]),
      PlanBlock('Woche 5–6', 'Power-Block', [
        _s('Drücken', [
          [_i('einarmiger_liegestuetz', 'Füße erhöht'), _i('federnder_liegestuetz')],
          [_i('handstandliegestuetz', _h13), _i('sturzflug')],
          [_i('erhoehter_trizepsstrecker', 'etwa hüfthoch'), _i('liegestuetz_abstossen')],
        ]),
        _s('Beine', [
          [_i('pistole', 'im Wechsel, $_h13'), _i('kistensprung')],
          [_i('sissy_kniebeuge', _h13), _i('iron_mike')],
          [_i('fallender_liegestuetz'), _i('seitsprung')],
        ]),
        _s('Ziehen', [
          [_i('tuerklimmzug', _h46top), _i('umgekehrtes_bankdruecken', 'Füße erhöht')],
          [_i('tuerziehen', 'einarmig, 1–3 s Haltezeit am höchsten Punkt'), _i('umgekehrtes_bankdruecken', 'Untergriff, Füße erhöht')],
          [_i('klimmzug', 'bis zum Brustbein'), _i('tuerziehen', 'Untergriff, $_h46top')],
        ]),
        _s('Core', [
          [_i('haengendes_beinheben', '$_h46top (Füße bis zu den Händen)'), _i('fahrradfahren', 'langsam, 2 s pro Knie')],
          [_i('rueckenheber'), _i('superman')],
          [_i('klappmesser'), _i('beintwist')],
        ]),
      ]),
      PlanBlock('Woche 7', 'Wechselblock', [
        _d('Drücken', _st, [_i('einarmiger_liegestuetz'), _i('handstandliegestuetz'), _i('sturzflug'), _i('trizepsdip', _h13)]),
        _s('Beine', [
          [_i('pistole', 'im Wechsel, $_h13'), _i('kistensprung')],
          [_i('sissy_kniebeuge', _h13), _i('iron_mike')],
          [_i('fallender_liegestuetz', 'ohne Zuhilfenahme der Hände'), _i('seitsprung')],
        ]),
        _d('Ziehen', _iv, [_i('tuerklimmzug', '1–3 s Haltezeit am höchsten Punkt'), _i('tuerziehen', 'einarmig'), _i('umgekehrtes_bankdruecken', 'Untergriff, Füße erhöht'), _i('tuerziehen', 'Untergriff, $_h46top')]),
        _d('Core', _hi, [_i('v_up'), _i('schraeger_v_up', 'Seitenwechsel nach jedem Satz, 4 Sätze'), _i('bergsteiger'), _i('kniebeuge')]),
        _zirkelChief(),
      ]),
      PlanBlock('Woche 8', 'Wechselblock', [
        _d('Drücken', _hi, [_i('liegestuetz'), _i('liegestuetz_abstossen'), _i('bergsteiger'), _i('burpee')]),
        _d('Beine', _st, [_i('einbeinige_kniebeuge'), _i('sissy_kniebeuge'), _i('iron_mike'), _i('hueftstrecker', 'einbeinig')]),
        _s('Ziehen', [
          [_i('tuerklimmzug', _h46top), _i('umgekehrtes_bankdruecken', 'Füße erhöht')],
          [_i('tuerziehen', 'einarmig, 1–3 s Haltezeit am höchsten Punkt'), _i('umgekehrtes_bankdruecken', 'Untergriff, Füße erhöht')],
          [_i('klimmzug', 'bis zum Brustbein'), _i('tuerziehen', 'Untergriff, $_h46top')],
        ]),
        _d('Core', _iv, [_i('haengendes_beinheben', 'bis ganz nach oben'), _i('rueckenheber'), _i('klappmesser'), _i('superman')]),
        _zirkelChief(),
      ]),
      PlanBlock('Woche 9', 'Wechselblock', [
        _d('Drücken', _iv, [_i('einarmiger_liegestuetz'), _i('handstandliegestuetz'), _i('sturzflug'), _i('erhoehter_trizepsstrecker', 'etwa hüfthoch')]),
        _d('Beine', _hi, [_i('iron_mike'), _i('seitsprung'), _i('gestreckte_kniebeuge'), _i('kniebeuge')]),
        _d('Ziehen', _st, [_i('tuerklimmzug'), _i('umgekehrtes_bankdruecken'), _i('umgekehrtes_bankdruecken', 'Untergriff'), _i('tuerziehen', 'einarmig im Wechsel')]),
        _s('Core', [
          [_i('haengendes_beinheben', 'Füße bis zu den Händen, $_h46top'), _i('fahrradfahren', '12× langsam pro Seite')],
          [_i('rueckenheber'), _i('superman')],
          [_i('klappmesser'), _i('beintwist', '6× langsam pro Seite')],
        ]),
        _zirkelChief(),
      ]),
      PlanBlock('Woche 10', 'Wechselblock', [
        _s('Drücken', [
          [_i('einarmiger_liegestuetz', 'Füße erhöht'), _i('federnder_liegestuetz')],
          [_i('handstandliegestuetz'), _i('sturzflug', 'Haltezeit, wenn die Brust zwischen den Händen ist')],
          [_i('erhoehter_trizepsstrecker', 'kniehoch'), _i('liegestuetz_abstossen')],
        ]),
        _d('Beine', _iv, [_i('einbeinige_kniebeuge'), _i('kniebeuge_ausfallschritt', 'am tiefsten Punkt Rucksack über den Kopf stemmen'), _i('iron_mike'), _i('fallender_liegestuetz')]),
        _d('Ziehen', _hi, [_i('tuerklimmzug', _neg), _i('umgekehrtes_bankdruecken'), _i('tuerziehen'), _i('bergsteiger')]),
        _d('Core', _st, [_i('klappmesser'), _i('rueckenheber'), _i('schraeger_v_up', 'im Wechsel mit gestreckten Beinen'), _i('superman')]),
        _zirkelChief(),
      ]),
    ],
    requirements: '16 einarmige Liegestütze (8 pro Seite) · 12 Klimmzüge (je 1 s halten) · 24 Pistolen im Wechsel · '
        '5 Minuten Liegestützposition halten.',
  ),
];

SamplePlan? samplePlanByKey(String key) => samplePlans.where((p) => p.key == key).firstOrNull;
