import 'package:frontend/core/models/dates.dart';

/// Bewertung beim Lernen einer Karte.
enum Rating {
  again('Nochmal'),
  hard('Schwer'),
  good('Gut'),
  easy('Leicht');

  const Rating(this.label);
  final String label;
}

/// Ein Karteikarten-Stapel (z. B. „Spanisch“), mit Zählern für die Übersicht.
class Deck {
  final int? id;
  final int userid;
  final String name;
  final int? color;
  final int cardCount;
  final int dueCount;

  const Deck({this.id, required this.userid, required this.name, this.color, this.cardCount = 0, this.dueCount = 0});

  Map<String, dynamic> toMap() => {if (id != null) 'id': id, 'userid': userid, 'name': name.trim(), 'color': color};

  factory Deck.fromMap(Map<String, dynamic> m) => Deck(
        id: m['id'] as int?,
        userid: m['userid'] as int,
        name: m['name'] as String? ?? '',
        color: m['color'] as int?,
        cardCount: (m['cardCount'] as int?) ?? 0,
        dueCount: (m['dueCount'] as int?) ?? 0,
      );
}

/// Eine Karteikarte mit Wiederholungsplan (vereinfachtes SM-2). Neue Karten haben kein [due] und
/// sind sofort dran.
class FlashCard {
  final int? id;
  final int userid;
  final int deckId;
  final String front;
  final String back;
  final DateTime? due;
  final double intervalDays;
  final double ease;
  final int reps;
  final int lapses;

  const FlashCard({
    this.id,
    required this.userid,
    required this.deckId,
    required this.front,
    required this.back,
    this.due,
    this.intervalDays = 0,
    this.ease = 2.5,
    this.reps = 0,
    this.lapses = 0,
  });

  bool get isNew => due == null;
  bool isDue(DateTime now) => due == null || !due!.isAfter(now);

  FlashCard copyWith({String? front, String? back, int? deckId}) => FlashCard(
        id: id,
        userid: userid,
        deckId: deckId ?? this.deckId,
        front: front ?? this.front,
        back: back ?? this.back,
        due: due,
        intervalDays: intervalDays,
        ease: ease,
        reps: reps,
        lapses: lapses,
      );

  Map<String, dynamic> toMap() => {
        if (id != null) 'id': id,
        'userid': userid,
        'deckId': deckId,
        'front': front.trim(),
        'back': back.trim(),
        'due': due?.toIso8601String(),
        'intervalDays': intervalDays,
        'ease': ease,
        'reps': reps,
        'lapses': lapses,
      };

  factory FlashCard.fromMap(Map<String, dynamic> m) => FlashCard(
        id: m['id'] as int?,
        userid: m['userid'] as int,
        deckId: m['deckId'] as int,
        front: m['front'] as String? ?? '',
        back: m['back'] as String? ?? '',
        due: m['due'] == null ? null : DateTime.tryParse(m['due'] as String),
        intervalDays: (m['intervalDays'] as num?)?.toDouble() ?? 0,
        ease: (m['ease'] as num?)?.toDouble() ?? 2.5,
        reps: (m['reps'] as int?) ?? 0,
        lapses: (m['lapses'] as int?) ?? 0,
      );
}

/// Nächster Termin einer Karte nach der Bewertung [rating] (vereinfachtes SM-2):
/// - Nochmal: in 10 Minuten wieder, Reihe beginnt neu, Leichtigkeit −0,2
/// - Schwer: Abstand ×1,2 (mind. 1 Tag), Leichtigkeit −0,15
/// - Gut: 1 Tag, dann 3 Tage, dann Abstand × Leichtigkeit
/// - Leicht: wie „Gut“ ×1,3, Leichtigkeit +0,15
/// Die Leichtigkeit bleibt ≥ 1,3; Tagesabstände zählen in Kalendertagen (fällig ab Mitternacht).
FlashCard scheduleNext(FlashCard card, Rating rating, DateTime now) {
  double ease = card.ease;
  double interval;
  int reps = card.reps;
  int lapses = card.lapses;

  double goodInterval() => switch (card.reps) {
        0 => 1,
        1 => 3,
        _ => (card.intervalDays * card.ease).roundToDouble(),
      };

  switch (rating) {
    case Rating.again:
      return FlashCard(
        id: card.id,
        userid: card.userid,
        deckId: card.deckId,
        front: card.front,
        back: card.back,
        due: now.add(const Duration(minutes: 10)),
        intervalDays: 0,
        ease: (ease - 0.2).clamp(1.3, double.infinity),
        reps: 0,
        lapses: lapses + 1,
      );
    case Rating.hard:
      interval = card.reps == 0 ? 1 : (card.intervalDays * 1.2).roundToDouble().clamp(1, double.infinity).toDouble();
      ease = (ease - 0.15).clamp(1.3, double.infinity);
    case Rating.good:
      interval = goodInterval();
    case Rating.easy:
      interval = (goodInterval() * 1.3).roundToDouble().clamp(2, double.infinity).toDouble();
      ease = ease + 0.15;
  }
  reps++;
  return FlashCard(
    id: card.id,
    userid: card.userid,
    deckId: card.deckId,
    front: card.front,
    back: card.back,
    due: addDays(dateOnly(now), interval.round()),
    intervalDays: interval,
    ease: ease,
    reps: reps,
    lapses: lapses,
  );
}

/// Kurzer Text für den nächsten Termin auf dem Bewertungsknopf („10 Min“, „1 T“, „3 Wo“, „2 Mon“).
String nextDueLabel(FlashCard card, Rating rating, DateTime now) {
  final next = scheduleNext(card, rating, now);
  if (rating == Rating.again) return '10 Min';
  final days = next.intervalDays.round();
  if (days < 14) return '$days T';
  if (days < 60) return '${(days / 7).round()} Wo';
  if (days < 365) return '${(days / 30).round()} Mon';
  return '${(days / 365).toStringAsFixed(1).replaceAll('.', ',')} J';
}

/// Viele Karten auf einmal: je Zeile „Vorderseite – Rückseite“ (auch „;“, Tab, „=“ oder „ - “).
/// Zeilen ohne Trenner werden übersprungen.
List<(String, String)> parseCardLines(String text) {
  final out = <(String, String)>[];
  for (final raw in text.split('\n')) {
    final line = raw.trim();
    if (line.isEmpty) continue;
    final m = RegExp(r'\s+[–—-]\s+|\t|;|\s*=\s*').firstMatch(line);
    if (m == null) continue;
    final front = line.substring(0, m.start).trim();
    final back = line.substring(m.end).trim();
    if (front.isNotEmpty && back.isNotEmpty) out.add((front, back));
  }
  return out;
}
