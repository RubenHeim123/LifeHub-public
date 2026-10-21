import 'package:flutter/material.dart';

import 'package:frontend/core/ui/theme.dart';

/// Eine Körperhaltung der Strichfigur in einem Feld von 100 × 110 Einheiten
/// (x 0…100, y −10…100, Boden bei y = 92). Die Figur schaut nach rechts;
/// „nah“ = dem Betrachter zugewandte Gliedmaßen, „fern“ = abgewandte (heller gezeichnet).
///
/// Reihenfolge der 11 Punkte: Kopf, Schulter, Ellbogen nah, Hand nah, Ellbogen fern, Hand fern,
/// Hüfte, Knie nah, Fuß nah, Knie fern, Fuß fern.
class Pose {
  final List<Offset> points;
  const Pose._(this.points);

  factory Pose(List<double> v) {
    assert(v.length == 22, 'Pose braucht 11 Punkte');
    return Pose._([for (var i = 0; i < v.length; i += 2) Offset(v[i], v[i + 1])]);
  }

  Offset get head => points[0];
  Offset get shoulder => points[1];

  Pose shifted(double dx, double dy) => Pose._([for (final p in points) p.translate(dx, dy)]);

  static Pose lerp(Pose a, Pose b, double t) =>
      Pose._([for (var i = 0; i < a.points.length; i++) Offset.lerp(a.points[i], b.points[i], t)!]);
}

/// Einfache Hilfsmittel im Bild (Stuhl, Wand, Stange …): eine Linie oder ein Kasten.
class Prop {
  final Offset from;
  final Offset to;
  final bool isLine;
  const Prop.line(this.from, this.to) : isLine = true;
  const Prop._box(this.from, this.to) : isLine = false;

  static Prop bar(double y, {double from = 36, double to = 64}) => Prop.line(Offset(from, y), Offset(to, y));
  static Prop wall(double x) => Prop.line(Offset(x, 4), Offset(x, 92));
  static Prop block(double l, double t, double r, double b) => Prop._box(Offset(l, t), Offset(r, b));
}

/// Bewegungsablauf: Schlüsselhaltungen, zwischen denen weich überblendet wird.
class Motion {
  final List<Pose> frames;

  /// `true`: A → B → C → A …; sonst hin und zurück (A → B → A).
  final bool cycle;
  final List<Prop> props;
  final bool ground;
  final Duration period;

  const Motion(this.frames, {this.cycle = false, this.props = const [], this.ground = true, this.period = const Duration(milliseconds: 1600)});

  /// Haltung zum Zeitpunkt [t] (0…1 über eine Periode).
  Pose at(double t) {
    if (frames.length == 1) return frames.first;
    final seq = cycle ? [...frames, frames.first] : [...frames, ...frames.reversed.skip(1)];
    final segments = seq.length - 1;
    final pos = (t.clamp(0.0, 1.0)) * segments;
    final i = pos.floor().clamp(0, segments - 1);
    final local = Curves.easeInOut.transform(pos - i);
    return Pose.lerp(seq[i], seq[i + 1], local);
  }

  /// Aussagekräftigste Haltung für ein Standbild.
  Pose get keyPose => frames.length > 1 ? frames[1] : frames.first;
}

// ─── Haltungen ────────────────────────────────────────────────────────────

Pose _p(List<double> v) => Pose(v);

final _stand = _p([50, 17, 50, 26, 50, 40, 50, 53, 50, 40, 50, 53, 50, 52, 50, 72, 50, 92, 50, 72, 50, 92]);
final _standArmsForward = _p([50, 17, 50, 26, 64, 27, 77, 27, 64, 27, 77, 27, 50, 52, 50, 72, 50, 92, 50, 72, 50, 92]);
final _standHandsHead = _p([50, 17, 50, 26, 60, 20, 49, 16, 60, 20, 49, 16, 50, 52, 50, 72, 50, 92, 50, 72, 50, 92]);
final _front = _p([50, 17, 50, 26, 58, 38, 62, 50, 42, 38, 38, 50, 50, 52, 54, 72, 56, 92, 46, 72, 44, 92]);

final _plankHigh = _p([77, 61, 69, 65, 69, 79, 69, 92, 69, 79, 69, 92, 45, 76, 27, 84, 8, 92, 27, 84, 8, 92]);
final _plankLow = _p([83, 82, 74, 84, 61, 80, 68, 92, 61, 80, 68, 92, 48, 87, 28, 89, 8, 92, 28, 89, 8, 92]);
final _pikeHigh = _p([61, 79, 55, 73, 64, 83, 74, 92, 64, 83, 74, 92, 37, 55, 30, 73, 23, 92, 30, 73, 23, 92]);
final _pikeLow = _p([67, 88, 60, 80, 70, 76, 74, 92, 70, 76, 74, 92, 42, 62, 32, 77, 23, 92, 32, 77, 23, 92]);
final _upDog = _p([79, 58, 73, 65, 73, 79, 74, 92, 73, 79, 74, 92, 52, 82, 33, 88, 14, 92, 33, 88, 14, 92]);
final _elbowPlank = _p([79, 73, 70, 78, 70, 90, 80, 90, 70, 90, 80, 90, 45, 82, 25, 87, 6, 92, 25, 87, 6, 92]);

final _prone = _p([80, 86, 71, 89, 84, 90, 97, 90, 84, 90, 97, 90, 45, 90, 25, 90, 5, 90, 25, 90, 5, 90]);
final _quadruped = _p([76, 62, 68, 66, 68, 79, 68, 92, 68, 79, 68, 92, 42, 72, 42, 92, 22, 92, 42, 92, 22, 92]);

final _crouch = _p([62, 40, 58, 48, 46, 58, 40, 68, 46, 58, 40, 68, 44, 70, 60, 78, 52, 92, 60, 78, 52, 92]);
final _deepSquat = _p([54, 46, 50, 54, 64, 54, 77, 54, 64, 54, 77, 54, 38, 78, 57, 72, 52, 92, 57, 72, 52, 92]);
final _lunge = _p([50, 37, 50, 46, 60, 40, 49, 36, 60, 40, 49, 36, 50, 72, 68, 70, 68, 92, 44, 90, 28, 92]);
final _lungeSwap = _p([50, 37, 50, 46, 60, 40, 49, 36, 60, 40, 49, 36, 50, 72, 44, 90, 28, 92, 68, 70, 68, 92]);
final _airborne = _p([50, 5, 50, 14, 58, 4, 66, -6, 58, 4, 66, -6, 50, 40, 50, 60, 52, 79, 50, 60, 52, 79]);

// ─── Bewegungen ───────────────────────────────────────────────────────────

/// Alle Bewegungsabläufe, über einen Schlüssel aus dem Übungskatalog erreichbar.
final Map<String, Motion> motions = {
  'pushup': Motion([_plankHigh, _plankLow]),
  'planche_lean': Motion([_plankHigh, _plankHigh.shifted(8, 1)]),
  'pike_push': Motion([_pikeHigh, _pikeLow]),
  'dive_bomber': Motion([_pikeHigh, _pikeLow, _upDog], cycle: true, period: const Duration(milliseconds: 2400)),
  'plank': Motion([_elbowPlank, _elbowPlank.shifted(0, -1.5)], period: const Duration(milliseconds: 2400)),
  'plank_hip': Motion([_elbowPlank.shifted(0, 3), _elbowPlank.shifted(0, -5)]),
  'mountain_climber': Motion([
    _p([77, 61, 69, 65, 69, 79, 69, 92, 69, 79, 69, 92, 45, 76, 60, 84, 42, 90, 27, 84, 8, 92]),
    _p([77, 61, 69, 65, 69, 79, 69, 92, 69, 79, 69, 92, 45, 76, 27, 84, 8, 92, 60, 84, 42, 90]),
  ], period: const Duration(milliseconds: 900)),
  'crawl': Motion([
    _p([74, 62, 66, 66, 70, 79, 72, 92, 64, 79, 62, 92, 45, 62, 52, 78, 40, 92, 40, 78, 30, 92]),
    _p([74, 62, 66, 66, 64, 79, 62, 92, 70, 79, 72, 92, 45, 62, 40, 78, 30, 92, 52, 78, 40, 92]),
  ], period: const Duration(milliseconds: 1100)),
  'fingertip_plank': Motion([_plankHigh.shifted(0, 6), _plankHigh.shifted(0, 2)], period: const Duration(milliseconds: 2200)),
  'dip_bench': Motion([
    _p([41, 26, 40, 35, 40, 48, 40, 62, 40, 48, 40, 62, 44, 61, 58, 76, 72, 92, 58, 76, 72, 92]),
    _p([43, 40, 42, 49, 29, 52, 40, 62, 29, 52, 40, 62, 44, 74, 60, 78, 72, 92, 60, 78, 72, 92]),
  ], props: [Prop.block(16, 62, 42, 92)]),
  'dip': Motion([
    _p([50, 20, 50, 29, 50, 43, 50, 56, 50, 43, 50, 56, 50, 55, 50, 73, 36, 80, 50, 73, 36, 80]),
    _p([51, 35, 50, 44, 37, 46, 50, 56, 37, 46, 50, 56, 50, 70, 50, 86, 36, 90, 50, 86, 36, 90]),
  ], props: [Prop.bar(56)]),
  'bridge': Motion([
    _p([86, 85, 78, 88, 75, 78, 80, 92, 75, 78, 80, 92, 46, 88, 40, 72, 30, 90, 40, 72, 30, 90]),
    _p([80, 80, 74, 72, 78, 82, 80, 92, 78, 82, 80, 92, 52, 58, 38, 70, 30, 92, 38, 70, 30, 92]),
  ]),
  'reverse_tabletop': Motion([
    _p([44, 54, 40, 63, 34, 77, 30, 90, 34, 77, 30, 90, 44, 88, 58, 72, 70, 92, 58, 72, 70, 92]),
    _p([21, 56, 28, 60, 29, 74, 30, 88, 29, 74, 30, 88, 52, 63, 68, 70, 68, 92, 68, 70, 68, 92]),
  ]),
  'front_raise': Motion([
    _stand,
    _p([50, 17, 50, 26, 60, 36, 69, 45, 60, 36, 69, 45, 50, 52, 50, 72, 50, 92, 50, 72, 50, 92]),
    _standArmsForward,
  ]),
  'lateral_raise': Motion([
    _front,
    _p([50, 17, 50, 26, 61, 35, 70, 44, 39, 35, 30, 44, 50, 52, 54, 72, 56, 92, 46, 72, 44, 92]),
    _p([50, 17, 50, 26, 64, 27, 77, 28, 36, 27, 23, 28, 50, 52, 54, 72, 56, 92, 46, 72, 44, 92]),
  ]),
  'arm_circles': Motion([
    _p([50, 17, 50, 26, 64, 25, 77, 23, 36, 25, 23, 23, 50, 52, 54, 72, 56, 92, 46, 72, 44, 92]),
    _p([50, 17, 50, 26, 64, 28, 77, 32, 36, 28, 23, 32, 50, 52, 54, 72, 56, 92, 46, 72, 44, 92]),
  ], period: const Duration(milliseconds: 700)),
  'shrug': Motion([
    _front,
    _p([50, 17, 50, 22, 58, 34, 62, 46, 42, 34, 38, 46, 50, 52, 54, 72, 56, 92, 46, 72, 44, 92]),
  ]),
  'overhead_press': Motion([
    _p([50, 17, 50, 26, 62, 36, 62, 24, 38, 36, 38, 24, 50, 52, 54, 72, 56, 92, 46, 72, 44, 92]),
    _p([50, 17, 50, 26, 56, 13, 58, 0, 44, 13, 42, 0, 50, 52, 54, 72, 56, 92, 46, 72, 44, 92]),
  ]),
  'bent_raise': Motion([
    _p([72, 38, 66, 44, 66, 58, 66, 70, 66, 58, 66, 70, 48, 58, 50, 76, 50, 92, 50, 76, 50, 92]),
    _p([72, 38, 66, 44, 68, 32, 70, 20, 68, 32, 70, 20, 48, 58, 50, 76, 50, 92, 50, 76, 50, 92]),
  ]),
  'curl': Motion([
    _stand,
    _p([50, 17, 50, 26, 50, 40, 60, 30, 50, 40, 60, 30, 50, 52, 50, 72, 50, 92, 50, 72, 50, 92]),
  ]),
  'towel_curl': Motion([
    _stand,
    _p([50, 17, 50, 26, 50, 40, 60, 30, 50, 40, 60, 30, 50, 52, 66, 57, 64, 76, 50, 72, 50, 92]),
  ], props: [Prop.wall(44)]),
  'grip': Motion([_standArmsForward, _standArmsForward.shifted(0, 0.01)], period: const Duration(milliseconds: 500)),
  'prone_lift': Motion([
    _prone,
    _p([80, 80, 71, 85, 84, 82, 96, 78, 84, 82, 96, 78, 45, 90, 25, 87, 6, 82, 25, 87, 6, 82]),
  ]),
  'swimmer': Motion([
    _p([80, 82, 71, 87, 84, 82, 96, 78, 84, 90, 97, 90, 45, 90, 25, 90, 5, 90, 25, 87, 6, 82]),
    _p([80, 82, 71, 87, 84, 90, 97, 90, 84, 82, 96, 78, 45, 90, 25, 87, 6, 82, 25, 90, 5, 90]),
  ]),
  'back_extension': Motion([
    _p([80, 86, 71, 89, 72, 80, 80, 84, 72, 80, 80, 84, 45, 90, 25, 90, 5, 90, 25, 90, 5, 90]),
    _p([78, 70, 70, 78, 70, 68, 78, 70, 70, 68, 78, 70, 45, 90, 25, 90, 5, 90, 25, 90, 5, 90]),
  ]),
  'handstand': Motion([
    _p([52, 74, 50, 65, 50, 78, 50, 92, 50, 78, 50, 92, 49, 39, 49, 19, 50, 0, 49, 19, 50, 0]),
    _p([52, 74, 50, 65, 50, 78, 50, 92, 50, 78, 50, 92, 51, 39, 51, 19, 52, 0, 51, 19, 52, 0]),
  ], props: [Prop.wall(58)], period: const Duration(milliseconds: 2400)),
  'handstand_push': Motion([
    _p([52, 74, 50, 65, 50, 78, 50, 92, 50, 78, 50, 92, 50, 39, 51, 19, 52, 0, 51, 19, 52, 0]),
    _p([51, 88, 50, 79, 60, 83, 50, 92, 60, 83, 50, 92, 50, 53, 51, 33, 52, 14, 51, 33, 52, 14]),
  ], props: [Prop.wall(58)]),
  'row': Motion([
    _p([40, 44, 48, 51, 61, 53, 74, 55, 61, 53, 74, 55, 36, 72, 50, 79, 60, 92, 50, 79, 60, 92]),
    _p([66, 40, 60, 48, 54, 60, 74, 55, 54, 60, 74, 55, 46, 70, 53, 80, 60, 92, 53, 80, 60, 92]),
  ], props: [Prop.wall(76)]),
  'inverted_row': Motion([
    _p([78, 62, 70, 66, 70, 52, 70, 40, 70, 52, 70, 40, 45, 74, 26, 83, 7, 90, 26, 83, 7, 90]),
    _p([78, 45, 70, 50, 60, 48, 70, 40, 60, 48, 70, 40, 45, 62, 26, 76, 7, 90, 26, 76, 7, 90]),
  ], props: [Prop.bar(40, from: 58, to: 90)]),
  'pullup': Motion([
    _p([53, 24, 50, 32, 50, 19, 50, 6, 50, 19, 50, 6, 50, 58, 50, 76, 38, 86, 50, 76, 38, 86]),
    _p([53, 5, 50, 14, 59, 18, 50, 6, 59, 18, 50, 6, 50, 40, 50, 58, 38, 68, 50, 58, 38, 68]),
  ], props: [Prop.bar(6)], ground: false),
  'hanging_leg_raise': Motion([
    _p([53, 24, 50, 32, 50, 19, 50, 6, 50, 19, 50, 6, 50, 58, 50, 76, 48, 94, 50, 76, 48, 94]),
    _p([53, 24, 50, 32, 50, 19, 50, 6, 50, 19, 50, 6, 50, 58, 64, 50, 66, 70, 64, 50, 66, 70]),
  ], props: [Prop.bar(6)], ground: false),
  'good_morning': Motion([
    _standHandsHead,
    _p([80, 48, 71, 48, 76, 40, 78, 45, 76, 40, 78, 45, 46, 52, 50, 72, 50, 92, 50, 72, 50, 92]),
  ]),
  'single_leg_rdl': Motion([
    _stand,
    _p([80, 50, 71, 50, 70, 64, 68, 77, 72, 63, 72, 76, 47, 52, 28, 50, 9, 48, 50, 72, 50, 92]),
  ]),
  'donkey_kick': Motion([
    _quadruped,
    _p([76, 62, 68, 66, 68, 79, 68, 92, 68, 79, 68, 92, 42, 72, 24, 66, 5, 60, 42, 92, 22, 92]),
  ]),
  'fire_hydrant': Motion([
    _quadruped,
    _p([76, 62, 68, 66, 68, 79, 68, 92, 68, 79, 68, 92, 42, 72, 44, 58, 26, 58, 42, 92, 22, 92]),
  ]),
  'side_leg_raise': Motion([
    _front,
    _p([50, 17, 50, 26, 58, 38, 62, 50, 42, 38, 38, 50, 50, 52, 64, 66, 78, 80, 46, 72, 44, 92]),
  ], props: [Prop.block(20, 60, 30, 92)]),
  'standing_leg_curl': Motion([
    _stand,
    _p([50, 17, 50, 26, 58, 38, 64, 48, 58, 38, 64, 48, 50, 52, 44, 71, 32, 56, 50, 72, 50, 92]),
  ]),
  'knee_raise': Motion([
    _standArmsForward,
    _p([50, 17, 50, 26, 64, 27, 77, 27, 64, 27, 77, 27, 50, 52, 70, 53, 70, 73, 50, 72, 50, 92]),
  ]),
  'glute_bridge': Motion([
    _p([88, 87, 80, 89, 66, 90, 54, 90, 66, 90, 54, 90, 54, 90, 42, 74, 28, 64, 42, 74, 28, 64]),
    _p([88, 87, 80, 89, 66, 90, 54, 90, 66, 90, 54, 90, 58, 72, 40, 66, 26, 62, 40, 66, 26, 62]),
  ], props: [Prop.block(14, 64, 34, 92)]),
  'balance': Motion([
    _p([50, 17, 50, 26, 58, 38, 62, 50, 42, 38, 38, 50, 50, 52, 50, 72, 50, 92, 52, 72, 40, 80]),
    _p([48, 17, 49, 26, 57, 38, 61, 50, 41, 38, 37, 50, 50, 52, 50, 72, 50, 92, 52, 72, 40, 80]),
  ], period: const Duration(milliseconds: 2600)),
  'reverse_hyper': Motion([
    _p([84, 55, 76, 58, 86, 64, 92, 62, 86, 64, 92, 62, 50, 58, 46, 78, 44, 92, 46, 78, 44, 92]),
    _p([84, 55, 76, 58, 86, 64, 92, 62, 86, 64, 92, 62, 50, 58, 30, 56, 10, 54, 30, 56, 10, 54]),
  ], props: [Prop.block(48, 60, 100, 92)], ground: false),
  'nordic_curl': Motion([
    _p([40, 37, 40, 46, 46, 56, 52, 48, 46, 56, 52, 48, 40, 72, 40, 92, 22, 92, 40, 92, 22, 92]),
    _p([78, 54, 72, 60, 80, 68, 86, 60, 80, 68, 86, 60, 54, 78, 40, 92, 22, 92, 40, 92, 22, 92]),
    _p([92, 78, 84, 82, 86, 88, 90, 92, 86, 88, 90, 92, 58, 85, 40, 92, 22, 92, 40, 92, 22, 92]),
  ], period: const Duration(milliseconds: 2400)),
  'squat': Motion([_standArmsForward, _deepSquat]),
  'wall_squat': Motion([
    _p([40, 17, 40, 26, 48, 36, 44, 30, 48, 36, 44, 30, 40, 52, 44, 72, 46, 92, 44, 72, 46, 92]),
    _p([40, 37, 40, 46, 48, 56, 44, 50, 48, 56, 44, 50, 40, 72, 60, 72, 60, 92, 60, 72, 60, 92]),
  ], props: [Prop.wall(36)]),
  'sumo_squat': Motion([
    _p([50, 17, 50, 26, 58, 38, 62, 50, 42, 38, 38, 50, 50, 52, 58, 72, 64, 92, 42, 72, 36, 92]),
    _p([50, 35, 50, 44, 60, 46, 70, 44, 40, 46, 30, 44, 50, 70, 68, 70, 68, 92, 32, 70, 32, 92]),
  ]),
  'overhead_squat': Motion([
    _p([50, 17, 50, 26, 60, 14, 68, 4, 40, 14, 32, 4, 50, 52, 58, 72, 64, 92, 42, 72, 36, 92]),
    _p([50, 35, 50, 44, 60, 32, 68, 22, 40, 32, 32, 22, 50, 70, 68, 70, 68, 92, 32, 70, 32, 92]),
  ]),
  'squat_press': Motion([
    _p([54, 46, 50, 54, 58, 62, 62, 52, 58, 62, 62, 52, 38, 78, 57, 72, 52, 92, 57, 72, 52, 92]),
    _p([50, 17, 50, 26, 52, 13, 54, 0, 52, 13, 54, 0, 50, 52, 50, 72, 50, 92, 50, 72, 50, 92]),
  ]),
  'beat_boots': Motion([
    _p([72, 78, 68, 70, 62, 80, 53, 88, 62, 80, 53, 88, 50, 52, 50, 72, 50, 92, 50, 72, 50, 92]),
    _p([68, 57, 62, 64, 60, 76, 53, 88, 60, 76, 53, 88, 44, 84, 60, 74, 52, 92, 60, 74, 52, 92]),
  ]),
  'lunge': Motion([_standHandsHead, _lunge]),
  'side_lunge': Motion([
    _p([50, 17, 50, 26, 58, 38, 60, 50, 42, 38, 40, 50, 50, 52, 54, 72, 56, 92, 46, 72, 44, 92]),
    _p([60, 33, 60, 42, 66, 52, 66, 62, 56, 52, 56, 62, 62, 68, 72, 74, 72, 92, 42, 80, 24, 92]),
  ]),
  'split_squat': Motion([
    _p([52, 17, 52, 26, 52, 40, 52, 53, 52, 40, 52, 53, 50, 52, 54, 72, 56, 92, 36, 62, 24, 66]),
    _p([48, 35, 48, 44, 50, 58, 52, 70, 50, 58, 52, 70, 46, 70, 64, 72, 62, 92, 38, 86, 24, 66]),
  ], props: [Prop.block(8, 68, 28, 92)]),
  'jump_lunge': Motion([_lunge, _lunge.shifted(0, -14), _lungeSwap, _lungeSwap.shifted(0, -14)], cycle: true, period: const Duration(milliseconds: 1600)),
  'jump_squat': Motion([_crouch, _airborne], period: const Duration(milliseconds: 1100)),
  'star_jump': Motion([
    _p([50, 43, 50, 52, 54, 66, 54, 88, 46, 66, 46, 88, 50, 78, 64, 70, 66, 92, 36, 70, 34, 92]),
    _p([50, 9, 50, 18, 60, 6, 70, -4, 40, 6, 30, -4, 50, 44, 60, 62, 70, 80, 40, 62, 30, 80]),
  ], period: const Duration(milliseconds: 1100)),
  'box_jump': Motion([_crouch.shifted(-16, 0), _airborne.shifted(4, -2), _stand.shifted(22, -16)], period: const Duration(milliseconds: 1800), props: [Prop.block(58, 76, 88, 92)]),
  'lateral_jump': Motion([_stand.shifted(-14, 0), _stand.shifted(0, -10), _stand.shifted(14, 0)], props: [Prop.block(46, 86, 54, 92)], period: const Duration(milliseconds: 1000)),
  'pogo': Motion([_stand, _stand.shifted(0, -8)], period: const Duration(milliseconds: 600)),
  'pistol': Motion([
    _p([50, 17, 50, 26, 64, 27, 77, 27, 64, 27, 77, 27, 50, 52, 64, 64, 72, 80, 50, 72, 50, 92]),
    _p([63, 51, 58, 58, 72, 58, 85, 58, 72, 58, 85, 58, 40, 80, 60, 82, 80, 84, 56, 74, 52, 92]),
  ]),
  'sissy_squat': Motion([
    _p([50, 17, 50, 26, 60, 36, 68, 44, 60, 36, 68, 44, 50, 52, 50, 72, 50, 92, 50, 72, 50, 92]),
    _p([27, 41, 33, 48, 46, 52, 58, 56, 46, 52, 58, 56, 52, 66, 66, 80, 50, 92, 66, 80, 50, 92]),
  ], props: [Prop.line(Offset(70, 20), Offset(70, 92))]),
  'calf_raise': Motion([_stand.shifted(0, -6), _stand.shifted(0, -12)], props: [Prop.block(40, 86, 62, 92)]),
  'calf_balance': Motion([_stand.shifted(-1, -12), _stand.shifted(1, -12)], props: [Prop.block(40, 86, 62, 92)], period: const Duration(milliseconds: 2400)),
  'crunch': Motion([
    _p([86, 85, 78, 88, 84, 80, 88, 86, 84, 80, 88, 86, 52, 90, 52, 70, 32, 70, 52, 70, 32, 70]),
    _p([80, 74, 74, 80, 80, 72, 84, 78, 80, 72, 84, 78, 52, 90, 52, 70, 32, 70, 52, 70, 32, 70]),
  ]),
  'situp': Motion([
    _p([86, 85, 78, 88, 72, 82, 66, 84, 72, 82, 66, 84, 52, 90, 40, 74, 28, 90, 40, 74, 28, 90]),
    _p([60, 55, 58, 64, 66, 72, 62, 72, 66, 72, 62, 72, 52, 90, 40, 74, 28, 90, 40, 74, 28, 90]),
  ], props: [Prop.block(16, 84, 30, 92)]),
  'v_up': Motion([
    _p([86, 82, 78, 86, 64, 86, 52, 86, 64, 86, 52, 86, 52, 90, 32, 86, 12, 82, 32, 86, 12, 82]),
    _p([66, 58, 62, 66, 72, 72, 84, 74, 72, 72, 84, 74, 52, 90, 56, 72, 40, 80, 56, 72, 40, 80]),
  ]),
  'jackknife': Motion([
    _p([86, 82, 78, 86, 80, 72, 82, 60, 80, 72, 82, 60, 52, 90, 32, 86, 12, 82, 32, 86, 12, 82]),
    _p([67, 59, 64, 67, 54, 60, 42, 55, 54, 60, 42, 55, 52, 90, 42, 73, 34, 56, 42, 73, 34, 56]),
  ]),
  'leg_raise': Motion([
    _p([86, 84, 78, 88, 62, 90, 54, 91, 62, 90, 54, 91, 52, 90, 32, 87, 12, 84, 32, 87, 12, 84]),
    _p([86, 84, 78, 88, 62, 90, 54, 91, 62, 90, 54, 91, 52, 90, 38, 76, 24, 62, 38, 76, 24, 62]),
  ]),
  'flutter_kick': Motion([
    _p([86, 84, 78, 88, 62, 90, 54, 91, 62, 90, 54, 91, 52, 90, 38, 76, 24, 62, 32, 87, 12, 84]),
    _p([86, 84, 78, 88, 62, 90, 54, 91, 62, 90, 54, 91, 52, 90, 32, 87, 12, 84, 38, 76, 24, 62]),
  ], period: const Duration(milliseconds: 1100)),
  'leg_twist': Motion([
    _p([86, 85, 78, 88, 90, 88, 99, 88, 66, 88, 57, 88, 52, 90, 52, 70, 52, 50, 52, 70, 52, 50]),
    _p([86, 85, 78, 88, 90, 88, 99, 88, 66, 88, 57, 88, 52, 90, 42, 80, 32, 72, 42, 80, 32, 72]),
  ]),
  'bicycle': Motion([
    _p([82, 76, 76, 82, 84, 76, 86, 82, 84, 76, 86, 82, 52, 90, 62, 74, 44, 76, 32, 86, 12, 84]),
    _p([82, 76, 76, 82, 84, 76, 86, 82, 84, 76, 86, 82, 52, 90, 32, 86, 12, 84, 62, 74, 44, 76]),
  ], period: const Duration(milliseconds: 1400)),
  'russian_twist': Motion([
    _p([63, 56, 60, 65, 70, 70, 72, 66, 70, 70, 72, 66, 52, 90, 66, 74, 80, 80, 66, 74, 80, 80]),
    _p([63, 56, 60, 65, 56, 74, 50, 70, 56, 74, 50, 70, 52, 90, 66, 74, 80, 80, 66, 74, 80, 80]),
  ], period: const Duration(milliseconds: 1200)),
  'side_leg_lift': Motion([
    _p([86, 80, 78, 86, 84, 76, 88, 78, 68, 90, 60, 90, 52, 90, 32, 90, 12, 90, 32, 90, 12, 90]),
    _p([86, 80, 78, 86, 84, 76, 88, 78, 68, 90, 60, 90, 52, 90, 34, 80, 16, 68, 32, 90, 12, 90]),
  ]),
  'dragon_flag': Motion([
    _p([86, 85, 78, 88, 88, 82, 94, 86, 88, 82, 94, 86, 52, 90, 32, 90, 12, 90, 32, 90, 12, 90]),
    _p([86, 85, 78, 88, 88, 82, 94, 86, 88, 82, 94, 86, 58, 66, 44, 52, 30, 38, 44, 52, 30, 38]),
  ], props: [Prop.block(92, 78, 100, 92)]),
  'burpee': Motion([
    _stand,
    _p([68, 52, 62, 56, 66, 74, 68, 92, 66, 74, 68, 92, 46, 76, 60, 70, 54, 92, 60, 70, 54, 92]),
    _plankHigh,
    _p([68, 52, 62, 56, 66, 74, 68, 92, 66, 74, 68, 92, 46, 76, 60, 70, 54, 92, 60, 70, 54, 92]),
    _airborne,
  ], cycle: true, period: const Duration(milliseconds: 2600)),
  'walk': Motion([
    _p([50, 17, 50, 26, 50, 40, 50, 53, 50, 40, 50, 53, 50, 52, 56, 72, 60, 92, 44, 72, 40, 92]),
    _p([50, 17, 50, 26, 50, 40, 50, 53, 50, 40, 50, 53, 50, 52, 44, 72, 40, 92, 56, 72, 60, 92]),
  ], period: const Duration(milliseconds: 1000)),
  'push_forward': Motion([
    _p([72, 30, 66, 36, 78, 40, 88, 42, 78, 40, 88, 42, 46, 56, 56, 72, 58, 92, 38, 74, 26, 92]),
    _p([72, 30, 66, 36, 78, 40, 88, 42, 78, 40, 88, 42, 46, 56, 38, 74, 26, 92, 56, 72, 58, 92]),
  ], props: [Prop.block(90, 30, 100, 92)], period: const Duration(milliseconds: 1400)),
  'neck': Motion([
    _p([84, 72, 76, 78, 68, 76, 62, 78, 68, 76, 62, 78, 50, 78, 36, 80, 34, 92, 36, 80, 34, 92]),
    _p([85, 86, 76, 78, 68, 76, 62, 78, 68, 76, 62, 78, 50, 78, 36, 80, 34, 92, 36, 80, 34, 92]),
  ], props: [Prop.block(40, 80, 80, 92)]),
};

/// Fällt auf eine neutrale Standhaltung zurück, falls ein Schlüssel fehlt.
Motion motionFor(String key) => motions[key] ?? Motion([_stand]);

// ─── Darstellung ──────────────────────────────────────────────────────────

/// Kleine Strichfigur-Animation einer Übung. Mit [animate] = false wird die
/// Schlüsselhaltung als Standbild gezeigt (günstig für Listen).
class ExerciseAnimation extends StatefulWidget {
  final String motion;
  final double size;
  final bool animate;
  const ExerciseAnimation({super.key, required this.motion, this.size = 120, this.animate = true});

  @override
  State<ExerciseAnimation> createState() => _ExerciseAnimationState();
}

class _ExerciseAnimationState extends State<ExerciseAnimation> with SingleTickerProviderStateMixin {
  AnimationController? _controller;

  Motion get _motion => motionFor(widget.motion);

  @override
  void initState() {
    super.initState();
    if (widget.animate) _controller = AnimationController(vsync: this, duration: _motion.period)..repeat();
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final motion = _motion;
    final controller = _controller;
    Widget paint(Pose pose) => CustomPaint(
          size: Size.square(widget.size),
          painter: _FigurePainter(pose, motion, near: c.accent, far: c.muted, prop: c.line),
        );
    return Semantics(
      label: 'Animation der Übung',
      child: SizedBox.square(
        dimension: widget.size,
        child: controller == null
            ? paint(motion.keyPose)
            : AnimatedBuilder(animation: controller, builder: (_, __) => paint(motion.at(controller.value))),
      ),
    );
  }
}

class _FigurePainter extends CustomPainter {
  final Pose pose;
  final Motion motion;
  final Color near, far, prop;
  _FigurePainter(this.pose, this.motion, {required this.near, required this.far, required this.prop});

  @override
  void paint(Canvas canvas, Size size) {
    final scale = size.shortestSide / 110;
    final dx = (size.width - 100 * scale) / 2;
    Offset map(Offset p) => Offset(dx + p.dx * scale, (p.dy + 10) * scale);

    final propPaint = Paint()
      ..color = prop
      ..strokeWidth = 2.2 * scale
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    if (motion.ground) canvas.drawLine(map(const Offset(2, 93)), map(const Offset(98, 93)), propPaint);
    for (final pr in motion.props) {
      if (pr.isLine) {
        canvas.drawLine(map(pr.from), map(pr.to), propPaint);
      } else {
        canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromPoints(map(pr.from), map(pr.to)), Radius.circular(1.5 * scale)), propPaint);
      }
    }

    Paint limb(Color color, double width) => Paint()
      ..color = color
      ..strokeWidth = width * scale
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;

    final p = pose.points.map(map).toList();
    final farPaint = limb(far, 3.6);
    final nearPaint = limb(near, 4.2);

    void chain(List<int> idx, Paint paint) {
      final path = Path()..moveTo(p[idx.first].dx, p[idx.first].dy);
      for (final i in idx.skip(1)) {
        path.lineTo(p[i].dx, p[i].dy);
      }
      canvas.drawPath(path, paint);
    }

    // fern: Arm, Bein
    chain([1, 4, 5], farPaint);
    chain([6, 9, 10], farPaint);
    // Rumpf + nah
    chain([1, 6], nearPaint);
    chain([6, 7, 8], nearPaint);
    chain([1, 2, 3], nearPaint);
    // Hals + Kopf
    final neck = Offset.lerp(p[1], p[0], 0.35)!;
    canvas.drawLine(p[1], neck, nearPaint);
    canvas.drawCircle(p[0], 5.6 * scale, Paint()..color = near);
  }

  @override
  bool shouldRepaint(_FigurePainter old) => old.pose != pose || old.near != near;
}
