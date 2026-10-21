import 'package:frontend/core/models/repeat.dart';

class Appointment {
  static const int defaultDurationMinutes = 60;

  /// Standard-Vorlauf der Erinnerung für neue Termine.
  static const int defaultReminderMinutes = 15;

  /// Wählbare Vorlaufzeiten (null = keine Erinnerung).
  static const reminderOptions = <int?>[null, 0, 5, 10, 15, 30, 60, 120, 1440];

  /// Für ganztägige Einträge: am Tag, am Vortag oder eine Woche vorher (jeweils um [allDayReminderHour]).
  static const allDayReminderOptions = <int?>[null, 0, 1440, 10080];
  static const allDayReminderHour = 9;

  static String reminderLabel(int? minutes, {bool allDay = false}) => switch (minutes) {
        null => 'Keine',
        0 => allDay ? 'Am Tag ($allDayReminderHour Uhr)' : 'Zu Beginn',
        1440 => allDay ? 'Am Vortag' : '1 Tag vorher',
        10080 => '1 Woche vorher',
        final m when m >= 60 && m % 60 == 0 => '${m ~/ 60} h vorher',
        final m => '$m min vorher',
      };

  final int? id;
  final String title;
  final String? description;
  final DateTime date;
  final int durationMinutes;
  final int userid;

  /// Schritt eines Ziel-Plans, zu dem der Termin gehört (optional).
  final int? goalStepId;

  /// Erinnerung so viele Minuten vor Beginn; `null` = keine Erinnerung.
  final int? reminderMinutes;

  /// Ganztägig: nur eine Notiz für den Tag, ohne Uhrzeit (z. B. Geburtstag).
  final bool allDay;

  /// Wiederholung: täglich, wöchentlich (an Wochentagen), alle N Wochen, monatlich, jährlich …
  final Repeat repeat;

  /// Jährlich (z. B. Geburtstag) – dann zeigt die App das Alter bzw. die Jahre.
  bool get repeatYearly => repeat.freq == RepeatFreq.yearly;

  bool get repeats => !repeat.isNone;

  Appointment({
    this.id,
    required this.title,
    this.description,
    required this.date,
    this.durationMinutes = defaultDurationMinutes,
    required this.userid,
    this.goalStepId,
    this.reminderMinutes = defaultReminderMinutes,
    this.allDay = false,
    Repeat? repeat,
    bool repeatYearly = false,
  }) : repeat = repeat ?? (repeatYearly ? Repeat.yearly : Repeat.none);

  static DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);

  /// Vorkommen am Tag [d] mit der Uhrzeit des Termins.
  DateTime _at(DateTime d) => DateTime(d.year, d.month, d.day, date.hour, date.minute);

  /// Beginn des Termins an [day], falls er an diesem Tag stattfindet (bei Wiederholung in jedem
  /// passenden Zeitraum ab dem ersten), sonst `null`.
  DateTime? occurrenceOn(DateTime day) {
    if (!repeats) return _day(date) == _day(day) ? date : null;
    return repeat.occursOn(date, day) ? _at(day) : null;
  }

  /// Nächstes Vorkommen, das zu [from] noch nicht vorbei ist (ohne Wiederholung: der Termin selbst).
  DateTime nextOccurrence(DateTime from) {
    if (!repeats) return date;
    final first = repeat.nextOnOrAfter(date, from);
    if (first == null) return date;
    var occ = _at(first);
    if (_endOf(occ).isBefore(from)) {
      final next = repeat.nextAfter(date, occ);
      if (next != null) occ = _at(next);
    }
    return occ;
  }

  /// Vorkommen zwischen [from] und [to] (inklusive, tagesgenau).
  List<DateTime> occurrencesBetween(DateTime from, DateTime to) {
    if (!repeats) {
      return _day(date).isBefore(_day(from)) || _day(date).isAfter(_day(to)) ? const [] : [date];
    }
    return [for (final d in repeat.occurrencesBetween(date, from, to)) _at(d)];
  }

  /// Wie oft sich der Anlass beim Vorkommen [occurrence] jährt (z. B. Alter bei Geburtstagen).
  int? yearsAt(DateTime occurrence) {
    if (!repeatYearly) return null;
    final years = occurrence.year - date.year;
    return years > 0 ? years : null;
  }

  /// Ende des Vorkommens, das um [start] beginnt (ganztägig: Tagesende).
  DateTime endOf(DateTime start) => _endOf(start);

  DateTime _endOf(DateTime start) =>
      allDay ? DateTime(start.year, start.month, start.day, 23, 59, 59) : start.add(Duration(minutes: durationMinutes));

  /// Nächste Erinnerung ab [now]: das betroffene Vorkommen und der Zeitpunkt, oder `null`.
  /// Ist bei jährlichen Einträgen die Erinnerung für dieses Jahr schon vorbei, gilt das nächste Jahr.
  ({DateTime occurrence, DateTime at})? nextReminder(DateTime now) {
    final minutes = reminderMinutes;
    if (minutes == null) return null;
    DateTime at(DateTime o) => allDay
        ? DateTime(o.year, o.month, o.day, allDayReminderHour).subtract(Duration(minutes: minutes))
        : o.subtract(Duration(minutes: minutes));
    var occ = nextOccurrence(now);
    if (repeats && at(occ).isBefore(now)) {
      final next = repeat.nextAfter(date, occ);
      if (next != null) occ = _at(next);
    }
    return (occurrence: occ, at: at(occ));
  }

  /// Zeitpunkt der nächsten Erinnerung ab [now] oder `null`.
  DateTime? reminderFor(DateTime now) => nextReminder(now)?.at;

  /// Zeitpunkt der Erinnerung oder `null`.
  DateTime? get reminderAt => reminderFor(DateTime.now());

  DateTime get endDate => _endOf(date);

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'title': title,
      'description': description,
      'date': date.toIso8601String(),
      'durationMinutes': durationMinutes,
      'userid': userid,
      'goalStepId': goalStepId,
      'reminderMinutes': reminderMinutes,
      'allDay': allDay ? 1 : 0,
      'repeatYearly': repeatYearly ? 1 : 0,
      'repeat': repeat.toDb(),
    };
  }

  factory Appointment.fromMap(Map<String, dynamic> map) {
    return Appointment(
      id: map['id'],
      title: map['title'],
      description: map['description'],
      date: DateTime.parse(map['date']),
      durationMinutes: (map['durationMinutes'] as num?)?.toInt() ?? defaultDurationMinutes,
      userid: map['userid'],
      goalStepId: map['goalStepId'] as int?,
      reminderMinutes: map.containsKey('reminderMinutes') ? (map['reminderMinutes'] as num?)?.toInt() : defaultReminderMinutes,
      allDay: map['allDay'] == 1,
      repeat: map['repeat'] != null ? Repeat.fromDb(map['repeat']) : null,
      repeatYearly: map['repeatYearly'] == 1,
    );
  }
}
