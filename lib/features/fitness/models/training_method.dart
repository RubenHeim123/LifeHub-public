/// Trainingsform eines Workouts. Bei allen Formen außer „frei“ bestimmt der Timer den
/// Ablauf – Sätze und Wiederholungen ergeben sich aus der Form, nicht aus einer Vorgabe.
enum TrainingMethod {
  stufen('stufen', 'Stufenintervalle',
      '1 Wdh., Pause, 2 Wdh., Pause … bis kurz vor dem Muskelversagen, dann rückwärts zählen. Pause so lang wie das vorige Intervall. 7,5 Minuten pro Übung.'),
  intervall('intervall', 'Intervallsätze',
      '3 Sätze pro Übung mit 6–12 Wiederholungen. Alle 3 Minuten beginnt ein Satz; einer der Sätze bis zum Muskelversagen.'),
  supersatz('supersatz', 'Supersätze',
      'Übungspaare: 1–5 Wdh. der ersten Übung (langsam, kontrolliert), direkt danach 6–12 Wdh. der zweiten (schnell). Alle 4 Minuten ein Supersatz, 2 pro Paar.'),
  zirkel('zirkel', 'Zirkelintervalle', 'So viele Runden der Übungen wie möglich in 20 Minuten, Pausen nur so kurz wie nötig.'),
  hochintensiv('hochintensiv', 'Hochintensitätssätze', '8 Runden: 20 Sekunden Training, 10 Sekunden Pause (4 Minuten pro Übung).');

  const TrainingMethod(this.dbValue, this.label, this.description);
  final String dbValue;
  final String label;
  final String description;

  /// Kurzform für Listen.
  String get short => switch (this) {
        stufen => '7:30 min pro Übung, Stufen hoch und runter',
        intervall => '3 Sätze, alle 3 min',
        supersatz => 'Übungspaare, 2 Supersätze alle 4 min',
        zirkel => '20 min so viele Runden wie möglich',
        hochintensiv => '8 × 20 s Training / 10 s Pause',
      };

  static TrainingMethod? fromDb(Object? v) => values.where((m) => m.dbValue == v).firstOrNull;

  // ─── Zeiten ───────────────────────────────────────────────────────────
  static const stufenBlock = Duration(seconds: 450);
  static const intervallSets = 3;
  static const intervallEvery = Duration(minutes: 3);
  static const supersatzRounds = 2;
  static const supersatzEvery = Duration(minutes: 4);
  static const zirkelTotal = Duration(minutes: 20);
  static const hochRounds = 8;
  static const hochWork = Duration(seconds: 20);
  static const hochRest = Duration(seconds: 10);
  static const hochSwitch = Duration(seconds: 60);
}
