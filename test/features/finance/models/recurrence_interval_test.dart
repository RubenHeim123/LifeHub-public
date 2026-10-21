import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/features/finance/models/recurrence_interval.dart';

void main() {
  group('RecurrenceInterval.occurrence', () {
    test('monthly from the 31st clamps per month without drifting', () {
      final start = DateTime(2026, 1, 31);
      final dates = [for (var n = 0; n < 5; n++) RecurrenceInterval.monthly.occurrence(start, n)];
      expect(dates, [
        DateTime(2026, 1, 31),
        DateTime(2026, 2, 28),
        DateTime(2026, 3, 31),
        DateTime(2026, 4, 30),
        DateTime(2026, 5, 31),
      ]);
    });

    test('quarterly and half-yearly cross the year boundary', () {
      final start = DateTime(2026, 11, 30);
      expect(RecurrenceInterval.quarterly.occurrence(start, 1), DateTime(2027, 2, 28));
      expect(RecurrenceInterval.halfYearly.occurrence(start, 1), DateTime(2027, 5, 30));
    });

    test('yearly from Feb 29 falls back to Feb 28', () {
      expect(RecurrenceInterval.yearly.occurrence(DateTime(2028, 2, 29), 1), DateTime(2029, 2, 28));
      expect(RecurrenceInterval.yearly.occurrence(DateTime(2028, 2, 29), 4), DateTime(2032, 2, 29));
    });

    test('daily and weekly keep the time of day', () {
      final start = DateTime(2026, 3, 28, 9, 30);
      expect(RecurrenceInterval.daily.occurrence(start, 2), DateTime(2026, 3, 30, 9, 30));
      expect(RecurrenceInterval.weekly.occurrence(start, 1), DateTime(2026, 4, 4, 9, 30));
    });
  });

  group('RecurrenceInterval.fromDb', () {
    test('reads current and legacy spellings', () {
      expect(RecurrenceInterval.fromDb('Monatlich'), RecurrenceInterval.monthly);
      expect(RecurrenceInterval.fromDb('Vierteljaehrlich'), RecurrenceInterval.quarterly);
      expect(RecurrenceInterval.fromDb('Jaehrlich'), RecurrenceInterval.yearly);
      expect(RecurrenceInterval.fromDb('wöchentlich'), RecurrenceInterval.weekly);
      expect(RecurrenceInterval.fromDb('monthly'), RecurrenceInterval.monthly);
    });

    test('rejects unknown values instead of silently booking daily', () {
      expect(() => RecurrenceInterval.fromDb('alle zwei Tage'), throwsArgumentError);
    });
  });

  test('monthlyEquivalent', () {
    expect(RecurrenceInterval.monthly.monthlyEquivalent(100), 100);
    expect(RecurrenceInterval.quarterly.monthlyEquivalent(300), 100);
    expect(RecurrenceInterval.yearly.monthlyEquivalent(1200), 100);
  });
}
