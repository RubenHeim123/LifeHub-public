import 'package:flutter_test/flutter_test.dart';

import 'package:frontend/features/contacts/models/relative_date.dart';

void main() {
  final tue = DateTime(2026, 10, 20, 18); // Dienstag

  void expectParse(String text, DateTime? date, String rest, {DateTime? now}) {
    final r = parseRelativeDate(text, now ?? tue);
    expect((r.date, r.text), (date, rest), reason: text);
  }

  test('today, tomorrow, the day after tomorrow – words, not parts of words', () {
    expectParse('heute Zahnarzt', DateTime(2026, 10, 20), 'Zahnarzt');
    expectParse('Morgen Vorstellungsgespräch', DateTime(2026, 10, 21), 'Vorstellungsgespräch');
    expectParse('übermorgen Umzug', DateTime(2026, 10, 22), 'Umzug');
    expectParse('geht morgens joggen', null, 'geht morgens joggen');
  });

  test('weekdays: the next one after today, "nächste Woche" is the week after this one', () {
    expectParse('Freitag Geburtstagsfeier', DateTime(2026, 10, 23), 'Geburtstagsfeier');
    expectParse('am Mittwoch Klausur', DateTime(2026, 10, 21), 'Klausur');
    expectParse('Dienstag Training', DateTime(2026, 10, 27), 'Training'); // heute ist Dienstag
    expectParse('nächste Woche Mittwoch Arzttermin', DateTime(2026, 10, 28), 'Arzttermin');
    expectParse('hat nächste Woche Mittwoch einen Arzttermin', DateTime(2026, 10, 28), 'hat einen Arzttermin');
    expectParse('Arzttermin Mittwoch nächste Woche', DateTime(2026, 10, 28), 'Arzttermin');
    expectParse('kommenden Samstag Hochzeit', DateTime(2026, 10, 24), 'Hochzeit');
    expectParse('naechste Woche Mittwoch Arzttermin', DateTime(2026, 10, 28), 'Arzttermin'); // ohne Umlaute getippt
    expectParse('uebermorgen Umzug', DateTime(2026, 10, 22), 'Umzug');
    expectParse('naechsten Freitag Kino', DateTime(2026, 10, 23), 'Kino');
  });

  test('in N days or weeks', () {
    expectParse('in 3 Tagen Prüfung', DateTime(2026, 10, 23), 'Prüfung');
    expectParse('OP in 2 Wochen', DateTime(2026, 11, 3), 'OP');
  });

  test('dates: without a year the next such day, also across the new year', () {
    expectParse('am 24.10. Umzug', DateTime(2026, 10, 24), 'Umzug');
    expectParse('Prüfung am 3.1.', DateTime(2027, 1, 3), 'Prüfung');
    expectParse('15.11.2027: Hochzeit', DateTime(2027, 11, 15), 'Hochzeit');
    expectParse('Abgabe 1.2.27', DateTime(2027, 2, 1), 'Abgabe');
    expectParse('31.2. gibt es nicht', null, '31.2. gibt es nicht');
  });

  test('around the new year weekdays roll into the next year', () {
    final wed = DateTime(2026, 12, 30, 9);
    expectParse('nächste Woche Montag Reha', DateTime(2027, 1, 4), 'Reha', now: wed);
    expectParse('Freitag Neujahrsbrunch', DateTime(2027, 1, 1), 'Neujahrsbrunch', now: wed);
  });

  test('no date: the text stays as it is', () {
    expectParse('mag keine Oliven', null, 'mag keine Oliven');
    expectParse('Hochzeit von Tom morgen, aufregend', DateTime(2026, 10, 21), 'Hochzeit von Tom, aufregend');
    expectParse('  ', null, '');
  });
}
