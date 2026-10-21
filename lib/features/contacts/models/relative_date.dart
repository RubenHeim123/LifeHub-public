import 'package:frontend/core/models/dates.dart';

const _weekdays = {
  'montag': 1,
  'dienstag': 2,
  'mittwoch': 3,
  'donnerstag': 4,
  'freitag': 5,
  'samstag': 6,
  'sonnabend': 6,
  'sonntag': 7,
};

// Ganze Wörter auch mit Umlauten (\b kennt nur ASCII).
const _l = r'(?<![\p{L}\d])';
const _r = r'(?![\p{L}\d])';
const _day = '(montag|dienstag|mittwoch|donnerstag|freitag|samstag|sonnabend|sonntag)';
const _next = '(?:nächste|naechste)'; // auch ohne Umlaute getippt

/// Erkennt eine einfache Zeitangabe in einer Notiz („morgen“, „Freitag“, „nächste Woche Mittwoch“,
/// „in 3 Tagen“, „am 24.10.“) und liefert das Datum plus den Text ohne diese Angabe.
/// Wochentage meinen den nächsten nach heute; Daten ohne Jahr den nächsten solchen Tag.
({DateTime? date, String text}) parseRelativeDate(String input, DateTime now) {
  final today = dateOnly(now);
  final nextMonday = addDays(weekStart(today), 7);

  final rules = <(RegExp, DateTime? Function(RegExpMatch))>[
    (_re('(?:am\\s+)?(\\d{1,2})\\.(\\d{1,2})\\.(\\d{2}(?:\\d{2})?)?'), (m) => _date(m, today)),
    (_re('in\\s+(\\d{1,3})\\s+(tag|tagen|woche|wochen)'), (m) {
      final n = int.parse(m.group(1)!);
      return addDays(today, m.group(2)!.toLowerCase().startsWith('tag') ? n : n * 7);
    }),
    (_re('(?:übermorgen|uebermorgen)'), (_) => addDays(today, 2)),
    (_re('morgen'), (_) => addDays(today, 1)),
    (_re('heute'), (_) => today),
    (_re('(?:am\\s+)?$_next\\s+woche\\s+(?:am\\s+)?$_day'), (m) => addDays(nextMonday, _weekdays[m.group(1)!.toLowerCase()]! - 1)),
    (_re('(?:am\\s+)?$_day\\s+$_next\\s+woche'), (m) => addDays(nextMonday, _weekdays[m.group(1)!.toLowerCase()]! - 1)),
    (_re('(?:(?:am|kommenden|nächsten|naechsten)\\s+)?$_day'), (m) {
      final wd = _weekdays[m.group(1)!.toLowerCase()]!;
      final ahead = (wd - today.weekday + 7) % 7;
      return addDays(today, ahead == 0 ? 7 : ahead);
    }),
  ];

  for (final (re, toDate) in rules) {
    final m = re.firstMatch(input);
    if (m == null) continue;
    final date = toDate(m);
    if (date == null) continue;
    final rest = '${input.substring(0, m.start)} ${input.substring(m.end)}'
        .replaceAll(RegExp(r'\s+'), ' ')
        .replaceAll(RegExp(r'^[\s,:;–-]+|[\s,:;–-]+$'), '')
        .replaceAllMapped(RegExp(r'\s+([,.:;])'), (m) => m.group(1)!);
    return (date: date, text: rest);
  }
  return (date: null, text: input.trim());
}

RegExp _re(String pattern) => RegExp('$_l$pattern$_r', caseSensitive: false, unicode: true);

DateTime? _date(RegExpMatch m, DateTime today) {
  final day = int.parse(m.group(1)!);
  final month = int.parse(m.group(2)!);
  final y = m.group(3);
  DateTime? make(int year) {
    final d = DateTime(year, month, day);
    return d.month == month && d.day == day ? d : null; // 31.2. gibt es nicht
  }

  if (month < 1 || month > 12 || day < 1) return null;
  if (y != null) return make(y.length == 2 ? 2000 + int.parse(y) : int.parse(y));
  final thisYear = make(today.year);
  if (thisYear == null) return make(today.year + 1);
  return thisYear.isBefore(today) ? make(today.year + 1) : thisYear;
}
