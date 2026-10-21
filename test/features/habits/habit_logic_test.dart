import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/features/habits/services/habit_actions.dart';
import 'package:frontend/features/habits/models/habit.dart';
import 'package:frontend/features/habits/repositories/habit_repository.dart';
import 'dart:convert';

int calculateCustomStreak(List<int> scheduledWeekdays, List<DateTime> completedDates, {DateTime? now}) =>
    HabitRepository.computeStreak(scheduledWeekdays, completedDates, now: now);

DateTime findPastScheduledDate(DateTime from, List<int> scheduledDays, int n) =>
    HabitActions.pastScheduledDate(from, scheduledDays, n);

DateTime findFutureScheduledDate(DateTime from, List<int> scheduledDays, int n) =>
    HabitActions.futureScheduledDate(from, scheduledDays, n);

void main() {
  // ─── Habit Model Tests ────────────────────────────────────────────────────
  group('Habit Model', () {
    test('toMap serializes selectedDays as JSON string', () {
      final habit = Habit(
        name: 'Test',
        userid: 1,
        selectedDays: [1, 3, 5],
      );
      final map = habit.toMap();

      expect(map['selectedDays'], isA<String>());
      expect(jsonDecode(map['selectedDays']), [1, 3, 5]);
    });

    test('fromMap deserializes selectedDays from JSON string', () {
      final map = {
        'id': 1,
        'name': 'Test',
        'frequency': 'custom',
        'userid': 1,
        'colorValue': 4280391411,
        'iconCodePoint': 58249,
        'iconFontFamily': 'MaterialIcons',
        'selectedDays': '[2,4,6]',
      };

      final habit = Habit.fromMap(map);

      expect(habit.selectedDays, [2, 4, 6]);
    });

    test('fromMap defaults to all days when selectedDays is null', () {
      final map = {
        'id': 1,
        'name': 'Test',
        'frequency': 'Täglich',
        'userid': 1,
      };

      final habit = Habit.fromMap(map);

      expect(habit.selectedDays, [1, 2, 3, 4, 5, 6, 7]);
    });

    test('fromMap handles invalid JSON gracefully', () {
      final map = {
        'id': 1,
        'name': 'Test',
        'frequency': 'custom',
        'userid': 1,
        'selectedDays': 'not-json',
      };

      final habit = Habit.fromMap(map);
      // Should fallback to default
      expect(habit.selectedDays, [1, 2, 3, 4, 5, 6, 7]);
    });
  });

  // ─── Streak Calculation Tests ─────────────────────────────────────────────
  group('Streak Calculation', () {
    test('returns 0 for no completed dates', () {
      final streak = calculateCustomStreak([1, 2, 3, 4, 5], []);
      expect(streak, 0);
    });

    test('returns 0 for empty scheduled weekdays', () {
      final streak = calculateCustomStreak([], [DateTime(2026, 3, 30)]);
      expect(streak, 0);
    });

    test('counts consecutive daily streak correctly', () {
      // 2026-03-31 is a Tuesday (weekday = 2)
      final now = DateTime(2026, 3, 31);

      // Daily habit, completed Mon + Tue (yesterday + today)
      final completed = [
        DateTime(2026, 3, 31), // Tue (today)
        DateTime(2026, 3, 30), // Mon
      ];

      final streak = calculateCustomStreak([1, 2, 3, 4, 5, 6, 7], completed, now: now);
      expect(streak, 2);
    });

    test('streak breaks on missed scheduled day', () {
      final now = DateTime(2026, 3, 31); // Tuesday

      // Completed today and 2 days ago, but missed yesterday
      final completed = [
        DateTime(2026, 3, 31), // today (Tue)
        DateTime(2026, 3, 29), // Sunday
      ];

      final streak = calculateCustomStreak([1, 2, 3, 4, 5, 6, 7], completed, now: now);
      // Today done = 1, yesterday (Mon) missed => break
      expect(streak, 1);
    });

    test('skips non-scheduled days when calculating streak', () {
      // Habit only on Mon(1) and Wed(3)
      // "now" is Wednesday 2026-04-01 (weekday 3)
      final now = DateTime(2026, 4, 1); // Wednesday

      final completed = [
        DateTime(2026, 4, 1),  // Wed (today)
        DateTime(2026, 3, 30), // Mon
        DateTime(2026, 3, 25), // Wed (previous week)
        DateTime(2026, 3, 23), // Mon (previous week)
      ];

      final streak = calculateCustomStreak([1, 3], completed, now: now);
      // Today (Wed) ✓, Mon 30 ✓, Wed 25 ✓, Mon 23 ✓ = 4
      expect(streak, 4);
    });

    test('today not completed, today is scheduled: streak only counts backwards', () {
      final now = DateTime(2026, 3, 31); // Tuesday

      // Completed yesterday (Mon-30) and day before (Sun-29), but NOT today
      final completed = [
        DateTime(2026, 3, 30), // Mon
        DateTime(2026, 3, 29), // Sun
      ];

      // Daily habit: today is Tue, not completed => today doesn't count.
      // Mon 30 ✓, Sun 29 ✓ => streak = 2? No!
      // The algorithm: today scheduled+not-done => streak += 0.
      // Then checks Mon 30 ✓ => streak 1, Sun 29 ✓ => streak 2... 
      // BUT today was scheduled and missed, which should arguably break the streak.
      // Current implementation: today not completed just doesn't add to streak,
      // but doesn't break it either. So backwards: Mon ✓ + Sun ✓ = 2.
      // Wait, re-reading the code: it only checks "isTodayScheduled && isTodayCompleted"
      // for adding 1. Then it goes backwards from yesterday. So streak = 0 + 2 = 2.
      // Actually let me re-check - the code goes: checkDate = today - 1 = Mon.
      // Mon is scheduled and completed => streak++. Then Sun, also scheduled/completed => streak++.
      // So result should be 2.
      final streak = calculateCustomStreak([1, 2, 3, 4, 5, 6, 7], completed, now: now);
      expect(streak, 2);
    });

    test('today not scheduled does not break streak', () {
      // Habit only on Mon (1) and Wed (3)
      // "now" is Tuesday 2026-03-31 (weekday 2) — not a scheduled day
      final now = DateTime(2026, 3, 31); // Tuesday

      final completed = [
        DateTime(2026, 3, 30), // Mon ✓
        DateTime(2026, 3, 25), // Wed ✓
        DateTime(2026, 3, 23), // Mon ✓
      ];

      final streak = calculateCustomStreak([1, 3], completed, now: now);
      // Today (Tue) not scheduled, so not counted.
      // Check Mon 30 ✓, then Tue/Sun/Sat/Fri/Thu skip, Wed 25 ✓, then Tue skip, Mon 23 ✓ = 3
      expect(streak, 3);
    });

    test('weekend-only habit', () {
      // Habit on Sat (6) and Sun (7)
      final now = DateTime(2026, 3, 29); // Sunday

      final completed = [
        DateTime(2026, 3, 29), // Sun (today) ✓
        DateTime(2026, 3, 28), // Sat ✓
        DateTime(2026, 3, 22), // Sun ✓
        DateTime(2026, 3, 21), // Sat ✓
      ];

      final streak = calculateCustomStreak([6, 7], completed, now: now);
      expect(streak, 4);
    });

    test('single day habit with consecutive weeks', () {
      // Habit only on Wednesday (3)
      final now = DateTime(2026, 4, 1); // Wed

      final completed = [
        DateTime(2026, 4, 1),  // Wed (today) ✓
        DateTime(2026, 3, 25), // Wed ✓
        DateTime(2026, 3, 18), // Wed ✓
      ];

      final streak = calculateCustomStreak([3], completed, now: now);
      expect(streak, 3);
    });

    test('single day habit with a missed week breaks streak', () {
      // Habit only on Wednesday (3)
      final now = DateTime(2026, 4, 1); // Wed

      final completed = [
        DateTime(2026, 4, 1),  // Wed (today) ✓
        // Missed Wed 2026-03-25
        DateTime(2026, 3, 18), // Wed ✓
      ];

      final streak = calculateCustomStreak([3], completed, now: now);
      // Today ✓, then checks Wed 03-25 — missed => break
      expect(streak, 1);
    });
  });

  // ─── Timeline Calculation Tests ───────────────────────────────────────────
  group('Timeline Helpers', () {
    test('findPastScheduledDate finds correct dates for daily habit', () {
      final today = DateTime(2026, 3, 31); // Tuesday
      final past1 = findPastScheduledDate(today, [1, 2, 3, 4, 5, 6, 7], 1);
      final past2 = findPastScheduledDate(today, [1, 2, 3, 4, 5, 6, 7], 2);
      final past3 = findPastScheduledDate(today, [1, 2, 3, 4, 5, 6, 7], 3);

      expect(past1, DateTime(2026, 3, 30)); // Mon
      expect(past2, DateTime(2026, 3, 29)); // Sun
      expect(past3, DateTime(2026, 3, 28)); // Sat
    });

    test('findPastScheduledDate skips unscheduled days', () {
      // Only Mon (1) and Wed (3)
      final today = DateTime(2026, 4, 1); // Wednesday
      final past1 = findPastScheduledDate(today, [1, 3], 1);
      final past2 = findPastScheduledDate(today, [1, 3], 2);
      final past3 = findPastScheduledDate(today, [1, 3], 3);

      expect(past1, DateTime(2026, 3, 30)); // Mon
      expect(past2, DateTime(2026, 3, 25)); // Wed
      expect(past3, DateTime(2026, 3, 23)); // Mon
    });

    test('findFutureScheduledDate finds correct dates', () {
      final today = DateTime(2026, 3, 31); // Tuesday
      // Only Mon (1) and Wed (3)
      final future1 = findFutureScheduledDate(today, [1, 3], 1);
      final future2 = findFutureScheduledDate(today, [1, 3], 2);
      final future3 = findFutureScheduledDate(today, [1, 3], 3);

      expect(future1, DateTime(2026, 4, 1));  // Wed
      expect(future2, DateTime(2026, 4, 6));  // Mon
      expect(future3, DateTime(2026, 4, 8));  // Wed
    });

    test('findFutureScheduledDate for daily habit', () {
      final today = DateTime(2026, 3, 31);
      final future1 = findFutureScheduledDate(today, [1, 2, 3, 4, 5, 6, 7], 1);
      expect(future1, DateTime(2026, 4, 1));
    });

    test('timeline produces 7 entries with today in center', () {
      // Simulate the timeline building logic from HabitTrackerScreen
      final today = DateTime(2026, 3, 31); // Tuesday
      final selectedDays = [1, 3]; // Mon & Wed

      List<DateTime> pastDates = [];
      for (int i = 3; i >= 1; i--) {
        pastDates.add(findPastScheduledDate(today, selectedDays, i));
      }

      List<DateTime> futureDates = [];
      for (int i = 1; i <= 3; i++) {
        futureDates.add(findFutureScheduledDate(today, selectedDays, i));
      }

      List<DateTime> timeline = [...pastDates, today, ...futureDates];

      expect(timeline.length, 7);
      expect(timeline[3], today); // Today is at index 3 (center)

      // Past dates should be Mon/Wed schedule
      expect(timeline[0], DateTime(2026, 3, 23)); // Mon (3rd past)
      expect(timeline[1], DateTime(2026, 3, 25)); // Wed (2nd past)
      expect(timeline[2], DateTime(2026, 3, 30)); // Mon (1st past)

      // Future dates
      expect(timeline[4], DateTime(2026, 4, 1));  // Wed (1st future)
      expect(timeline[5], DateTime(2026, 4, 6));  // Mon (2nd future)
      expect(timeline[6], DateTime(2026, 4, 8));  // Wed (3rd future)
    });
  });
}
