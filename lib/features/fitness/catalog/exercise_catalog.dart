import 'package:frontend/features/fitness/catalog/exercise_howto.dart';
import 'package:frontend/features/fitness/models/workout.dart';

/// Bereiche des Übungskatalogs.
enum CatalogCategory {
  push('Liegestütze'),
  triceps('Trizeps'),
  shoulders('Schultern'),
  pull('Rücken & Bizeps'),
  legs('Beine & Gesäß'),
  calves('Waden'),
  core('Core'),
  fullBody('Ganzkörper');

  const CatalogCategory(this.label);
  final String label;
}

/// Übung aus dem mitgelieferten Katalog. Beschreibungen sind kurz und in eigenen Worten
/// zusammengefasst; die Bewegung zeigt eine Strichfigur-Animation ([motion]).
class CatalogExercise {
  final String key;
  final String name;
  final CatalogCategory category;
  final String muscles;

  /// Schwierigkeitsstufe(n) 1 (Einsteiger) bis 4 (Spitzensportler), z. B. „2–4“.
  final String level;
  final String motion;
  final ExerciseMetric metric;
  final ExerciseType type;

  const CatalogExercise(
    this.key,
    this.name,
    this.category,
    this.muscles,
    this.level,
    this.motion, {
    this.metric = ExerciseMetric.reps,
    this.type = ExerciseType.strength,
  });

  /// Ausführung, leichtere und schwerere Variante – stehen getrennt in [exerciseHowTo]
  /// (die öffentliche Version des Projekts kommt ohne diese Texte aus).
  String get howTo => exerciseHowTo[key]?.$1 ?? '';
  String? get easier => exerciseHowTo[key]?.$2;
  String? get harder => exerciseHowTo[key]?.$3;

  /// Niedrigste Stufe (für Sortierung/Filter).
  int get minLevel => int.tryParse(level.substring(0, 1)) ?? 1;

  String get levelLabel => 'Stufe $level';
}

const _time = ExerciseMetric.time;
const _skill = ExerciseType.skill;

const List<CatalogExercise> exerciseCatalog = [
  // ─── Liegestütze ──────────────────────────────────────────────────────
  CatalogExercise('schaukelstuhl', 'Schaukelstuhl', CatalogCategory.push, 'Brust, Trizeps, Schultern, Core', '1', 'planche_lean'),
  CatalogExercise('baerengang', 'Bärengang', CatalogCategory.push, 'Schultern, Brust, Trizeps, Trapez, Core', '1', 'crawl'),
  CatalogExercise('liegestuetz', 'Liegestütz', CatalogCategory.push, 'Brust, Trizeps, Schultern, Core', '1–4', 'pushup'),
  CatalogExercise('breiter_liegestuetz', 'Breiter Liegestütz', CatalogCategory.push, 'Brust, Schultern, Trizeps, Core', '2–3', 'pushup'),
  CatalogExercise('liegestuetz_abgesenkte_schulter', 'Liegestütz mit abgesenkter Schulter', CatalogCategory.push, 'Brust, Trizeps, Schultern, Core',
      '2–3', 'pushup'),
  CatalogExercise('tiefer_liegestuetz', 'Tiefer Liegestütz', CatalogCategory.push, 'Brust, Trizeps, Schultern, Core', '2–3', 'pushup'),
  CatalogExercise(
      'liegestuetz_versetzt', 'Liegestütz mit versetzten Händen', CatalogCategory.push, 'Brust, Schultern, Trizeps, Core', '1–3', 'pushup'),
  CatalogExercise('liegestuetz_abstossen', 'Liegestütz mit Abstoßen', CatalogCategory.push, 'Brust, Schultern, Trizeps', '1–4', 'pushup'),
  CatalogExercise('federnder_liegestuetz', 'Federnder Liegestütz', CatalogCategory.push, 'Brust, Trizeps, Schultern, Core', '3', 'pushup'),
  CatalogExercise('bergsteiger', 'Bergsteiger', CatalogCategory.push, 'Schultern, Core, Hüftbeuger', '2', 'mountain_climber'),
  CatalogExercise('liegestuetz_ball', 'Liegestütz mit Ball', CatalogCategory.push, 'Core, Brust, Schultern', '3', 'pushup'),
  CatalogExercise('kriechender_liegestuetz', 'Kriechender Liegestütz', CatalogCategory.push, 'Schultern, Core, Brust, Trizeps', '3', 'crawl'),
  CatalogExercise('halber_sturzflug', 'Halber Sturzflug', CatalogCategory.push, 'Schultern, Trizeps, Brust, Trapez', '3–4', 'pike_push'),
  CatalogExercise('sturzflug', 'Sturzflug', CatalogCategory.push, 'Brust, Trizeps, Schultern, Core', '3–4', 'dive_bomber'),
  CatalogExercise(
      'halber_fliegender_liegestuetz', 'Halber fliegender Liegestütz', CatalogCategory.push, 'Brust, Schultern, Trizeps, Core', '4', 'planche_lean',
      type: _skill),
  CatalogExercise(
      'fliegender_liegestuetz', 'Fliegender Liegestütz', CatalogCategory.push, 'Ganzer Körper, Brust, Schultern, Core', '4', 'planche_lean',
      type: _skill),
  CatalogExercise(
      'einarmiger_liegestuetz', 'Einarmiger Liegestütz', CatalogCategory.push, 'Ganzer Körper, Schultern, Trizeps, Brust, Bauch', '4', 'pushup'),
  CatalogExercise('gleitender_liegestuetz', 'Gleitender Liegestütz', CatalogCategory.push, 'Brust, Core, Schultern', '4', 'pushup'),

  // ─── Trizeps ──────────────────────────────────────────────────────────
  CatalogExercise('trizepsdip_stuhl', 'Trizepsdip mit Stuhl', CatalogCategory.triceps, 'Trizeps, Schultern', '1–3', 'dip_bench'),
  CatalogExercise(
      'seitlicher_trizepsstrecker', 'Seitlicher Trizepsstrecker', CatalogCategory.triceps, 'Trizeps, schräge Bauchmuskeln', '3', 'plank_hip'),
  CatalogExercise('krebsgang', 'Krebsgang', CatalogCategory.triceps, 'Körperrückseite, Trizeps, Schultern', '1', 'crawl'),
  CatalogExercise('hueftheber', 'Hüftheber', CatalogCategory.triceps, 'Trizeps, Schultern, Gesäß, Beinrückseite', '2', 'reverse_tabletop'),
  CatalogExercise('unterbauchtrainer', 'Unterbauchtrainer', CatalogCategory.triceps, 'Unterer Bauch, Trizeps', '3–4', 'leg_raise'),
  CatalogExercise('enger_liegestuetz', 'Enger Liegestütz', CatalogCategory.triceps, 'Trizeps, Brust, Schultern, Core', '2–4', 'pushup'),
  CatalogExercise('chinesischer_liegestuetz', 'Chinesischer Liegestütz', CatalogCategory.triceps, 'Trizeps, Schultern', '2–4', 'pike_push'),
  CatalogExercise('liegestuetz_linie', 'Liegestütz auf einer Linie', CatalogCategory.triceps, 'Trizeps, Core, Schultern, Brust', '3–4', 'pushup'),
  CatalogExercise('erhoehter_trizepsstrecker', 'Erhöhter Trizepsstrecker', CatalogCategory.triceps, 'Trizeps, Core', '3–4', 'pushup'),
  CatalogExercise('trizepsdip', 'Trizepsdip', CatalogCategory.triceps, 'Trizeps, Brust, Schultern', '2–4', 'dip'),
  CatalogExercise('umgekehrter_liegestuetz', 'Umgekehrter Liegestütz', CatalogCategory.triceps, 'Trizeps, Trapez, Schultern, Gesäß, unterer Rücken',
      '3–4', 'bridge'),

  // ─── Schultern ────────────────────────────────────────────────────────
  CatalogExercise('armrotation', 'Armrotation', CatalogCategory.shoulders, 'Schultern', '1', 'arm_circles', metric: _time),
  CatalogExercise('military_press', 'Military Press', CatalogCategory.shoulders, 'Schultern, Trizeps', '2–4', 'pike_push'),
  CatalogExercise('dach_brennt', 'Das Dach brennt', CatalogCategory.shoulders, 'Schultern, Trizeps, Brust', '3–4', 'overhead_press'),
  CatalogExercise('ueberkopfpresse', 'Überkopfpresse', CatalogCategory.shoulders, 'Schultern, Trapez, Trizeps', '1–4', 'overhead_press'),
  CatalogExercise('daumen_hoch', 'Daumen hoch', CatalogCategory.shoulders, 'Hintere Schulter, unterer Rücken', '2–3', 'prone_lift'),
  CatalogExercise('seitliches_schulterheben', 'Seitliches Schulterheben', CatalogCategory.shoulders, 'Seitliche Schulter', '1–4', 'lateral_raise'),
  CatalogExercise('vorgebeugtes_schulterheben', 'Vorgebeugtes seitliches Schulterheben', CatalogCategory.shoulders, 'Hintere Schulter, Rücken', '1–4',
      'bent_raise'),
  CatalogExercise('frontales_schulterheben', 'Frontales Schulterheben', CatalogCategory.shoulders, 'Vordere Schulter', '1–4', 'front_raise'),
  CatalogExercise('schulterzucken', 'Schulterzucken', CatalogCategory.shoulders, 'Trapez, seitliche Schulter', '1–4', 'shrug'),
  CatalogExercise('handstandliegestuetz', 'Handstandliegestütz', CatalogCategory.shoulders, 'Schultern, Trizeps, Core', '4', 'handstand_push',
      type: _skill),
  CatalogExercise('handstand_wand', 'Handstand an der Wand', CatalogCategory.shoulders, 'Schultern, Trizeps, Trapez, Core', '3–4', 'handstand',
      metric: _time, type: _skill),
  CatalogExercise('freier_handstand', 'Freier Handstand', CatalogCategory.shoulders, 'Schultern, Balance, Core', '4', 'handstand',
      metric: _time, type: _skill),

  // ─── Rücken & Bizeps ──────────────────────────────────────────────────
  CatalogExercise('tuerziehen', 'Türziehen', CatalogCategory.pull, 'Latissimus, Bizeps, Unterarme, hintere Schulter', '1–4', 'row'),
  CatalogExercise('umgekehrtes_bankdruecken', 'Umgekehrtes Bankdrücken', CatalogCategory.pull, 'Latissimus, Bizeps, Unterarme, hintere Schulter',
      '2–4', 'inverted_row'),
  CatalogExercise('klimmzug', 'Klimmzug', CatalogCategory.pull, 'Latissimus, Bizeps, Unterarme', '2–4', 'pullup'),
  CatalogExercise('tuerklimmzug', 'Türklimmzug (negativ)', CatalogCategory.pull, 'Latissimus, Bizeps, Unterarme', '2–4', 'pullup'),
  CatalogExercise('curl_handtuch', 'Curl mit Handtuch', CatalogCategory.pull, 'Bizeps, Unterarme', '2–4', 'towel_curl'),
  CatalogExercise('curl_widerstand', 'Curl mit Widerstand', CatalogCategory.pull, 'Bizeps, Unterarme', '2–4', 'curl'),
  CatalogExercise('bizeps_curl', 'Bizeps-Curl', CatalogCategory.pull, 'Bizeps, Unterarme', '2–4', 'curl'),
  CatalogExercise('isometrischer_curl', 'Isometrischer Curl', CatalogCategory.pull, 'Unterarme, Bizeps', '2', 'curl', metric: _time),
  CatalogExercise('unterarm_curl', 'Unterarm-Curl', CatalogCategory.pull, 'Unterarme', '1–4', 'curl'),
  CatalogExercise('greifer', 'Greifer', CatalogCategory.pull, 'Hände, Unterarme', '1', 'grip'),

  // ─── Beine & Gesäß ────────────────────────────────────────────────────
  CatalogExercise('good_morning', 'Good Morning', CatalogCategory.legs, 'Gesäß, Beinrückseite, unterer Rücken', '1', 'good_morning'),
  CatalogExercise('dirty_dog', 'Dirty Dog', CatalogCategory.legs, 'Gesäß, unterer Rücken, Hüftbeuger', '1', 'fire_hydrant'),
  CatalogExercise('maultiertritt', 'Maultiertritt', CatalogCategory.legs, 'Beinrückseite, Gesäß, unterer Rücken', '1', 'donkey_kick'),
  CatalogExercise('seitliches_beinheben', 'Seitliches Beinheben im Stehen', CatalogCategory.legs, 'Gesäß, Hüftbeuger', '1', 'side_leg_raise'),
  CatalogExercise('bein_curl_stehen', 'Bein-Curl im Stehen', CatalogCategory.legs, 'Gesäß, Beinrückseite', '1', 'standing_leg_curl'),
  CatalogExercise('rumaenisches_kreuzheben', 'Rumänisches Kreuzheben auf einem Bein', CatalogCategory.legs, 'Beinrückseite, unterer Rücken, Balance',
      '2', 'single_leg_rdl'),
  CatalogExercise('hueftstrecker', 'Hüftstrecker', CatalogCategory.legs, 'Gesäß, Beinrückseite, unterer Rücken', '2–3', 'glute_bridge'),
  CatalogExercise('koenig_der_trottel', 'König der Trottel', CatalogCategory.legs, 'Waden, Beine, Balance', '1–4', 'balance', metric: _time),
  CatalogExercise('fliegende_graetsche', 'Fliegende Grätsche', CatalogCategory.legs, 'Gesäß', '2', 'reverse_hyper'),
  CatalogExercise('fallender_liegestuetz', 'Fallender Liegestütz', CatalogCategory.legs, 'Beinrückseite, Brust, Schultern', '4', 'nordic_curl'),
  CatalogExercise('kniebeuge', 'Kniebeuge', CatalogCategory.legs, 'Quadrizeps, Beinrückseite, Gesäß, unterer Rücken', '1–4', 'squat'),
  CatalogExercise('unsichtbarer_stuhl', 'Unsichtbarer Stuhl', CatalogCategory.legs, 'Quadrizeps, Beinrückseite, Gesäß', '1', 'wall_squat',
      metric: _time),
  CatalogExercise('kniebeuge_wand', 'Kniebeuge an der Wand', CatalogCategory.legs, 'Quadrizeps, Beinrückseite, Gesäß', '1', 'wall_squat'),
  CatalogExercise('beat_your_boots', 'Beat Your Boots', CatalogCategory.legs, 'Beinrückseite, Quadrizeps', '2', 'beat_boots'),
  CatalogExercise('sumo_kniebeuge', 'Sumo-Kniebeuge', CatalogCategory.legs, 'Beinrückseite, Quadrizeps, Gesäß', '1', 'sumo_squat'),
  CatalogExercise('sumo_kniebeuge_fortgeschritten', 'Sumo-Kniebeuge für Fortgeschrittene', CatalogCategory.legs, 'Beinrückseite, Quadrizeps, Gesäß',
      '2–4', 'sumo_squat'),
  CatalogExercise('ausfallschritt', 'Ausfallschritt', CatalogCategory.legs, 'Quadrizeps, Gesäß, Beinrückseite, Hüftbeuger', '1–4', 'lunge'),
  CatalogExercise('ausfallschritt_hinten', 'Ausfallschritt nach hinten', CatalogCategory.legs, 'Quadrizeps, Gesäß, Beinrückseite', '1–4', 'lunge'),
  CatalogExercise('seitlicher_ausfallschritt', 'Seitlicher Ausfallschritt', CatalogCategory.legs, 'Quadrizeps, Gesäß, Hüftbeuger, Beinrückseite',
      '2–4', 'side_lunge'),
  CatalogExercise('iron_mike', 'Iron Mike', CatalogCategory.legs, 'Quadrizeps, Gesäß, Hüftbeuger, Balance', '3', 'jump_lunge'),
  CatalogExercise('gesprungene_kniebeuge', 'Gesprungene Kniebeuge', CatalogCategory.legs, 'Quadrizeps, Gesäß, Waden', '1', 'jump_squat'),
  CatalogExercise('sternsprung', 'Sternsprung', CatalogCategory.legs, 'Quadrizeps, Gesäß, Hüftbeuger, Waden', '2', 'star_jump'),
  CatalogExercise('seitsprung', 'Seitsprung', CatalogCategory.legs, 'Beine, Waden, Explosivkraft', '2–4', 'lateral_jump'),
  CatalogExercise('kistensprung', 'Kistensprung', CatalogCategory.legs, 'Beine, Gesäß, unterer Rücken, Waden', '1–4', 'box_jump'),
  CatalogExercise('sprung_volle_kniebeuge', 'Sprung aus der vollen Kniebeuge', CatalogCategory.legs, 'Beine, Explosivkraft', '3', 'jump_squat'),
  CatalogExercise('sprung_halbe_kniebeuge', 'Sprung aus der halben Kniebeuge', CatalogCategory.legs, 'Beine, Explosivkraft', '2', 'jump_squat'),
  CatalogExercise('sprung_viertel_kniebeuge', 'Sprung aus der viertel Kniebeuge', CatalogCategory.legs, 'Beine, Explosivkraft', '1', 'jump_squat'),
  CatalogExercise('tiefensprung', 'Tiefensprung', CatalogCategory.legs, 'Beine, Explosivkraft', '4', 'box_jump'),
  CatalogExercise('einbeinige_kniebeuge_sprung', 'Einbeinige Kniebeuge mit Sprung', CatalogCategory.legs, 'Beine, Explosivkraft', '4', 'pistol'),
  CatalogExercise('rdl_sprung', 'Rumänisches Kreuzheben mit Sprung', CatalogCategory.legs, 'Beinrückseite, Balance', '3', 'single_leg_rdl'),
  CatalogExercise('ueberkopfkniebeuge', 'Überkopfkniebeuge', CatalogCategory.legs, 'Beine, Gesäß, Rücken, Schultern', '3', 'overhead_squat'),
  CatalogExercise(
      'gestreckte_kniebeuge', 'Gestreckte Kniebeuge', CatalogCategory.legs, 'Beine, Gesäß, Rücken, Schultern, Trizeps', '3', 'squat_press'),
  CatalogExercise(
      'kniebeuge_ausfallschritt', 'Kniebeuge im Ausfallschritt', CatalogCategory.legs, 'Quadrizeps, Beinrückseite, Gesäß', '2–4', 'split_squat'),
  CatalogExercise(
      'einbeinige_kniebeuge', 'Einbeinige Kniebeuge', CatalogCategory.legs, 'Quadrizeps, Beinrückseite, Gesäß, Hüftbeuger', '4', 'pistol'),
  CatalogExercise('pistole', 'Pistole', CatalogCategory.legs, 'Quadrizeps, Gesäß, Beinrückseite, Balance', '4', 'pistol', type: _skill),
  CatalogExercise('sissy_kniebeuge', 'Sissy-Kniebeuge', CatalogCategory.legs, 'Quadrizeps, Beinrückseite, Gesäß', '3–4', 'sissy_squat'),

  // ─── Waden ────────────────────────────────────────────────────────────
  CatalogExercise('wadenheben', 'Wadenheben', CatalogCategory.calves, 'Waden', '1–4', 'calf_raise'),
  CatalogExercise('cliffhanger', 'Cliffhanger', CatalogCategory.calves, 'Waden, Balance', '4', 'calf_balance', metric: _time),
  CatalogExercise('pogo_sprung', 'Pogo-Sprung', CatalogCategory.calves, 'Waden', '2', 'pogo'),
  CatalogExercise('huepfen', 'Hüpfen', CatalogCategory.calves, 'Waden', '3', 'pogo'),
  CatalogExercise('schienbeinmuskeltrainer', 'Schienbeinmuskeltrainer', CatalogCategory.calves, 'Schienbeinmuskeln', '1–4', 'calf_raise'),

  // ─── Core ─────────────────────────────────────────────────────────────
  CatalogExercise('knieheben_stehen', 'Knieheben im Stehen', CatalogCategory.core, 'Hüftbeuger, gerader Bauch', '1', 'knee_raise'),
  CatalogExercise('strandschere', 'Strandschere', CatalogCategory.core, 'Abduktoren, schräge Bauchmuskeln', '1–3', 'side_leg_lift'),
  CatalogExercise('russischer_twist', 'Russischer Twist', CatalogCategory.core, 'Gerader Bauch, schräge Bauchmuskeln', '1', 'russian_twist'),
  CatalogExercise('seitliches_hueftheben', 'Seitliches Hüftheben', CatalogCategory.core, 'Schräge Bauchmuskeln, ganzer Körper', '3', 'plank_hip'),
  CatalogExercise('crunch_it_up', 'Crunch It Up', CatalogCategory.core, 'Gerader Bauch (oben)', '1–2', 'situp'),
  CatalogExercise('crunch', 'Crunch', CatalogCategory.core, 'Gerader Bauch (oben)', '1', 'crunch'),
  CatalogExercise('beinheber', 'Beinheber', CatalogCategory.core, 'Gerader Bauch (unten), Hüftbeuger', '1–2', 'leg_raise'),
  CatalogExercise('beinscheren_crunch', 'Beinscheren-Crunch', CatalogCategory.core, 'Gerader Bauch (unten), Hüftbeuger', '2', 'flutter_kick'),
  CatalogExercise('gegraetschter_beinscheren_crunch', 'Gegrätschter Beinscheren-Crunch', CatalogCategory.core, 'Gerader Bauch (unten), Hüftbeuger',
      '2', 'flutter_kick'),
  CatalogExercise('fahrradfahren', 'Fahrradfahren', CatalogCategory.core, 'Gerader und schräger Bauch', '2', 'bicycle'),
  CatalogExercise('v_up', 'V-Up', CatalogCategory.core, 'Gerader Bauch, Hüftbeuger', '2', 'v_up'),
  CatalogExercise('schraeger_v_up', 'Schräger V-Up', CatalogCategory.core, 'Schräge Bauchmuskeln', '3', 'side_leg_lift'),
  CatalogExercise('beintwist', 'Beintwist', CatalogCategory.core, 'Gerader und schräger Bauch', '3', 'leg_twist'),
  CatalogExercise('klappmesser', 'Klappmesser', CatalogCategory.core, 'Gerader Bauch, Hüftbeuger', '3', 'jackknife'),
  CatalogExercise(
      'haengendes_beinheben', 'Hängendes Beinheben', CatalogCategory.core, 'Gerader Bauch, Hüftbeuger, Unterarme', '3–4', 'hanging_leg_raise'),
  CatalogExercise('fahne', 'Fahne', CatalogCategory.core, 'Gerader und schräger Bauch, Trizeps, Unterarme', '4', 'dragon_flag', type: _skill),
  CatalogExercise('schwimmer', 'Schwimmer', CatalogCategory.core, 'Gesäß, unterer Rücken', '2', 'swimmer'),
  CatalogExercise('superman', 'Superman', CatalogCategory.core, 'Gesäß, unterer Rücken', '3', 'prone_lift'),
  CatalogExercise('rueckenheber', 'Rückenheber', CatalogCategory.core, 'Gesäß, unterer Rücken, Rückenstrecker', '3', 'back_extension'),
  CatalogExercise('planke', 'Planke', CatalogCategory.core, 'Core, Schultern, Gesäß', '2', 'plank', metric: _time),
  CatalogExercise('planke_arm_bein', 'Planke mit Arm und Bein', CatalogCategory.core, 'Core, Brust, Trizeps, Schultern', '3', 'plank', metric: _time),
  CatalogExercise('nacken', 'Nackentraining', CatalogCategory.core, 'Nacken', '2', 'neck'),

  // ─── Ganzkörper ───────────────────────────────────────────────────────
  CatalogExercise(
      'liegestuetzsprung', 'Einfacher Liegestützsprung', CatalogCategory.fullBody, 'Brust, Trizeps, Schultern, Core, Beine', '3', 'burpee'),
  CatalogExercise('burpee', 'Doppelter Liegestützsprung (Burpee)', CatalogCategory.fullBody, 'Ganzer Körper', '3', 'burpee'),
  CatalogExercise('liegestuetzsprung_graetsche', 'Liegestützsprung mit Grätsche', CatalogCategory.fullBody, 'Ganzer Körper', '3', 'burpee'),
  CatalogExercise('spiderman', 'Spiderman', CatalogCategory.fullBody, 'Core, Rücken, Brust', '4', 'fingertip_plank', metric: _time, type: _skill),
  CatalogExercise('bauerngang', 'Bauerngang', CatalogCategory.fullBody, 'Ganzer Körper, Griffkraft', '4', 'walk', metric: _time),
  CatalogExercise('pferdestaerke', 'Pferdestärke', CatalogCategory.fullBody, 'Ganzer Körper', '4', 'push_forward', metric: _time),
];

final Map<String, CatalogExercise> catalogByKey = {for (final e in exerciseCatalog) e.key: e};
