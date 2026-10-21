import 'package:flutter_test/flutter_test.dart';

import 'package:frontend/core/models/dates.dart';

void main() {
  // Lokal (Europa/Berlin) hat der 25.10.2026 25 Stunden, der 29.03.2026 nur 23.
  test('addDays counts calendar days across the clock change', () {
    expect(addDays(DateTime(2026, 10, 24), 2), DateTime(2026, 10, 26));
    expect(addDays(DateTime(2026, 3, 30), -7), DateTime(2026, 3, 23));
    expect(addDays(DateTime(2026, 12, 31, 18, 30), 1), DateTime(2027, 1, 1));
  });

  test('daysBetween ignores the time of day and the clock change', () {
    expect(daysBetween(DateTime(2026, 10, 24), DateTime(2026, 10, 26)), 2);
    expect(daysBetween(DateTime(2026, 3, 28, 23), DateTime(2026, 3, 30, 1)), 2);
    expect(daysBetween(DateTime(2026, 10, 10), DateTime(2026, 10, 9)), -1);
  });

  test('weekStart is always the Monday at midnight', () {
    expect(weekStart(DateTime(2026, 10, 25, 22)), DateTime(2026, 10, 19));
    expect(weekStart(DateTime(2026, 3, 30)), DateTime(2026, 3, 30));
    expect(weekStart(DateTime(2026, 3, 29, 12)), DateTime(2026, 3, 23));
  });
}
