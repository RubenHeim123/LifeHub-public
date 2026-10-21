import 'package:flutter_test/flutter_test.dart';

import 'package:frontend/core/models/repeat.dart';

void main() {
  test('weekly on Friday and every two weeks', () {
    final start = DateTime(2026, 10, 2); // Freitag
    const weekly = Repeat(RepeatFreq.weekly);
    expect(weekly.occurrencesBetween(start, DateTime(2026, 10, 1), DateTime(2026, 10, 31)),
        [DateTime(2026, 10, 2), DateTime(2026, 10, 9), DateTime(2026, 10, 16), DateTime(2026, 10, 23), DateTime(2026, 10, 30)]);
    expect(weekly.label(start), 'Wöchentlich (Fr)');

    const biweekly = Repeat(RepeatFreq.weekly, interval: 2);
    expect(biweekly.occurrencesBetween(start, start, DateTime(2026, 10, 31)),
        [DateTime(2026, 10, 2), DateTime(2026, 10, 16), DateTime(2026, 10, 30)]);
    expect(biweekly.nextAfter(start, DateTime(2026, 10, 2)), DateTime(2026, 10, 16));
    expect(biweekly.label(start), 'Alle 2 Wochen (Fr)');

    // Mehrere Wochentage: Di und Fr, Start an einem Dienstag
    const twice = Repeat(RepeatFreq.weekly, weekdays: {2, 5});
    expect(twice.occurrencesBetween(DateTime(2026, 10, 6), DateTime(2026, 10, 6), DateTime(2026, 10, 13)),
        [DateTime(2026, 10, 6), DateTime(2026, 10, 9), DateTime(2026, 10, 13)]);
  });

  test('daily, monthly at the month end, yearly on 29 February', () {
    expect(const Repeat(RepeatFreq.daily, interval: 3).nextAfter(DateTime(2026, 1, 1), DateTime(2026, 1, 1)), DateTime(2026, 1, 4));

    const monthly = Repeat(RepeatFreq.monthly);
    final end = DateTime(2026, 1, 31);
    expect(monthly.occurrencesBetween(end, end, DateTime(2026, 4, 30)),
        [DateTime(2026, 1, 31), DateTime(2026, 2, 28), DateTime(2026, 3, 31), DateTime(2026, 4, 30)]);

    final leap = DateTime(2000, 2, 29);
    expect(Repeat.yearly.occursOn(leap, DateTime(2026, 2, 28)), isTrue);
    expect(Repeat.yearly.occursOn(leap, DateTime(2028, 2, 29)), isTrue);
    expect(Repeat.yearly.nextOnOrAfter(leap, DateTime(2026, 3, 1)), DateTime(2027, 2, 28));
    expect(Repeat.yearly.occursOn(leap, DateTime(1999, 2, 28)), isFalse); // vor dem Start
  });

  test('no repeat occurs once; stored as JSON and read back', () {
    final start = DateTime(2026, 5, 4);
    expect(Repeat.none.occurrencesBetween(start, DateTime(2026, 1, 1), DateTime(2026, 12, 31)), [start]);
    expect(Repeat.none.nextAfter(start, start), isNull);
    expect(Repeat.none.toDb(), isNull);
    expect(Repeat.fromDb(null), Repeat.none);
    expect(Repeat.fromDb('kaputt'), Repeat.none);

    const r = Repeat(RepeatFreq.weekly, interval: 2, weekdays: {5, 1});
    expect(Repeat.fromDb(r.toDb()), r);
    expect(r.label(), 'Alle 2 Wochen (Mo, Fr)');
  });
}
