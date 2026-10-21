import 'dart:convert';

import 'package:intl/intl.dart';

import 'package:frontend/core/models/dates.dart';

/// Stimmung eines Tages (1 = schlecht … 5 = super).
enum Mood {
  bad(1, '😞', 'Schlecht'),
  meh(2, '🙁', 'Mäßig'),
  okay(3, '😐', 'Okay'),
  good(4, '🙂', 'Gut'),
  great(5, '😄', 'Super');

  const Mood(this.value, this.emoji, this.label);
  final int value;
  final String emoji;
  final String label;

  static Mood? fromValue(int? v) => Mood.values.where((m) => m.value == v).firstOrNull;
}

/// Ein Journal-Eintrag: höchstens einer pro Tag.
class JournalEntry {
  /// Impulse für den Tag – optional, jede Antwort ist ein eigenes Feld.
  static const prompts = [
    'Wofür bin ich heute dankbar?',
    'Was lief heute gut?',
    'Was nehme ich mir für morgen vor?',
  ];

  final int? id;
  final int userid;
  final DateTime date;
  final Mood? mood;
  final String text;

  /// Antworten je Leitfrage (Frage → Antwort), leere Antworten fehlen.
  final Map<String, String> answers;

  JournalEntry({
    this.id,
    required this.userid,
    required DateTime date,
    this.mood,
    this.text = '',
    Map<String, String> answers = const {},
  })  : date = dateOnly(date),
        answers = {
          for (final e in answers.entries)
            if (e.value.trim().isNotEmpty) e.key: e.value.trim(),
        };

  static final _day = DateFormat('yyyy-MM-dd');
  static String dayKey(DateTime d) => _day.format(d);

  bool get isEmpty => mood == null && text.trim().isEmpty && answers.isEmpty;

  /// Alles Geschriebene in Lesereihenfolge (für Vorschau und Suche).
  String get preview => [...answers.values, text.trim()].where((s) => s.isNotEmpty).join(' · ');

  Map<String, dynamic> toMap() => {
        if (id != null) 'id': id,
        'userid': userid,
        'date': dayKey(date),
        'mood': mood?.value,
        'text': text.trim(),
        'answers': jsonEncode(answers),
      };

  factory JournalEntry.fromMap(Map<String, dynamic> m) {
    var answers = <String, String>{};
    try {
      answers = Map<String, String>.from(jsonDecode(m['answers'] as String? ?? '{}') as Map);
    } catch (_) {} // kaputte Zeile: Text und Stimmung trotzdem zeigen
    return JournalEntry(
      id: m['id'] as int?,
      userid: m['userid'] as int,
      date: DateTime.parse(m['date'] as String),
      mood: Mood.fromValue(m['mood'] as int?),
      text: m['text'] as String? ?? '',
      answers: answers,
    );
  }
}
