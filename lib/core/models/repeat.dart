import 'dart:convert';

/// Wie oft sich etwas wiederholt.
enum RepeatFreq {
  none('none'),
  daily('daily'),
  weekly('weekly'),
  monthly('monthly'),
  yearly('yearly');

  const RepeatFreq(this.dbValue);
  final String dbValue;

  static RepeatFreq fromDb(Object? v) => values.firstWhere((f) => f.dbValue == v, orElse: () => none);
}

const _weekdayShort = ['Mo', 'Di', 'Mi', 'Do', 'Fr', 'Sa', 'So'];

/// Wiederholungsregel für To-Dos und Termine, z. B. „jeden Freitag“, „alle 2 Wochen“
/// oder „jährlich“ (Geburtstage). Alle Berechnungen arbeiten mit Kalendertagen;
/// der erste Termin ist das Startdatum.
class Repeat {
  final RepeatFreq freq;

  /// Alle [interval] Tage/Wochen/Monate/Jahre (mindestens 1).
  final int interval;

  /// Nur bei [RepeatFreq.weekly]: Wochentage 1 (Mo) … 7 (So). Leer = Wochentag des Starts.
  final Set<int> weekdays;

  const Repeat(this.freq, {this.interval = 1, this.weekdays = const {}});

  static const none = Repeat(RepeatFreq.none);
  static const yearly = Repeat(RepeatFreq.yearly);

  bool get isNone => freq == RepeatFreq.none;

  static DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);
  static int _daysInMonth(int year, int month) => DateTime(year, month + 1, 0).day;
  static int _daysBetween(DateTime a, DateTime b) =>
      DateTime.utc(b.year, b.month, b.day).difference(DateTime.utc(a.year, a.month, a.day)).inDays;

  Set<int> _weekdaysFor(DateTime start) => weekdays.isEmpty ? {start.weekday} : weekdays;

  /// Fällt ein Vorkommen der Serie mit Start [start] auf den Tag [day]?
  bool occursOn(DateTime start, DateTime day) {
    final s = _day(start), d = _day(day);
    if (d.isBefore(s)) return false;
    final step = interval < 1 ? 1 : interval;
    switch (freq) {
      case RepeatFreq.none:
        return d == s;
      case RepeatFreq.daily:
        return _daysBetween(s, d) % step == 0;
      case RepeatFreq.weekly:
        if (!_weekdaysFor(s).contains(d.weekday)) return false;
        final weekStart = s.subtract(Duration(days: s.weekday - 1));
        return (_daysBetween(weekStart, d) ~/ 7) % step == 0;
      case RepeatFreq.monthly:
        final months = (d.year - s.year) * 12 + d.month - s.month;
        return months % step == 0 && d.day == _clampDay(s.day, d.year, d.month);
      case RepeatFreq.yearly:
        final years = d.year - s.year;
        // 29. Februar fällt in anderen Jahren auf den 28.
        return years % step == 0 && d.month == s.month && d.day == _clampDay(s.day, d.year, d.month);
    }
  }

  static int _clampDay(int day, int year, int month) {
    final max = _daysInMonth(year, month);
    return day > max ? max : day;
  }

  /// Erstes Vorkommen am oder nach [from] (`null`, wenn es keines mehr gibt).
  DateTime? nextOnOrAfter(DateTime start, DateTime from) {
    final s = _day(start);
    var d = _day(from).isBefore(s) ? s : _day(from);
    if (isNone) return d == s ? s : null;
    // Längster Abstand: Jahre × Intervall (+ Schaltjahr-Puffer)
    final limit = 400 * (interval < 1 ? 1 : interval) + 8;
    for (var i = 0; i < limit; i++) {
      if (occursOn(s, d)) return d;
      d = DateTime(d.year, d.month, d.day + 1);
    }
    return null;
  }

  /// Erstes Vorkommen echt nach [after].
  DateTime? nextAfter(DateTime start, DateTime after) {
    final a = _day(after);
    return nextOnOrAfter(start, DateTime(a.year, a.month, a.day + 1));
  }

  /// Alle Vorkommen von [from] bis einschließlich [to].
  List<DateTime> occurrencesBetween(DateTime start, DateTime from, DateTime to) {
    final result = <DateTime>[];
    var next = nextOnOrAfter(start, from);
    final end = _day(to);
    while (next != null && !next.isAfter(end)) {
      result.add(next);
      next = isNone ? null : nextAfter(start, next);
    }
    return result;
  }

  /// „Täglich“, „Alle 2 Wochen (Fr)“, „Jährlich“ …
  String label([DateTime? start]) {
    final n = interval < 1 ? 1 : interval;
    String days() {
      final set = start == null ? weekdays : _weekdaysFor(start);
      if (set.isEmpty) return '';
      return ' (${(set.toList()..sort()).map((d) => _weekdayShort[d - 1]).join(', ')})';
    }

    return switch (freq) {
      RepeatFreq.none => 'Einmalig',
      RepeatFreq.daily => n == 1 ? 'Täglich' : 'Alle $n Tage',
      RepeatFreq.weekly => (n == 1 ? 'Wöchentlich' : 'Alle $n Wochen') + days(),
      RepeatFreq.monthly => n == 1 ? 'Monatlich' : 'Alle $n Monate',
      RepeatFreq.yearly => n == 1 ? 'Jährlich' : 'Alle $n Jahre',
    };
  }

  String? toDb() => isNone
      ? null
      : jsonEncode({'freq': freq.dbValue, 'interval': interval, if (weekdays.isNotEmpty) 'weekdays': (weekdays.toList()..sort())});

  static Repeat fromDb(Object? value) {
    if (value is! String || value.isEmpty) return none;
    try {
      final m = jsonDecode(value) as Map<String, dynamic>;
      return Repeat(
        RepeatFreq.fromDb(m['freq']),
        interval: (m['interval'] as num?)?.toInt() ?? 1,
        weekdays: {for (final d in (m['weekdays'] as List? ?? const [])) (d as num).toInt()},
      );
    } catch (_) {
      return none;
    }
  }

  @override
  bool operator ==(Object other) =>
      other is Repeat &&
      other.freq == freq &&
      other.interval == interval &&
      other.weekdays.length == weekdays.length &&
      other.weekdays.containsAll(weekdays);

  @override
  int get hashCode => Object.hash(freq, interval, Object.hashAllUnordered(weekdays));

  @override
  String toString() => label();
}
