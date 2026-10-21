import 'package:flutter_test/flutter_test.dart';

import 'package:frontend/features/learning/models/flash_card.dart';

void main() {
  final now = DateTime(2026, 10, 20, 18, 30);
  const fresh = FlashCard(userid: 1, deckId: 1, front: 'el perro', back: 'der Hund');

  test('a new card: again in 10 min, hard/good tomorrow, easy in 2 days', () {
    final again = scheduleNext(fresh, Rating.again, now);
    expect((again.due, again.lapses, again.reps), (DateTime(2026, 10, 20, 18, 40), 1, 0));
    expect(again.ease, closeTo(2.3, 1e-9));

    expect(scheduleNext(fresh, Rating.hard, now).due, DateTime(2026, 10, 21));
    final good = scheduleNext(fresh, Rating.good, now);
    expect((good.due, good.reps, good.intervalDays), (DateTime(2026, 10, 21), 1, 1.0));
    expect(scheduleNext(fresh, Rating.easy, now).due, DateTime(2026, 10, 22));
  });

  test('good, good, good: 1 day, 3 days, then interval × ease', () {
    var c = scheduleNext(fresh, Rating.good, now);
    c = scheduleNext(c, Rating.good, DateTime(2026, 10, 21, 9));
    expect((c.intervalDays, c.due), (3.0, DateTime(2026, 10, 24)));
    c = scheduleNext(c, Rating.good, DateTime(2026, 10, 24, 9));
    expect(c.intervalDays, 8); // 3 × 2,5 gerundet
    expect(c.due, DateTime(2026, 11, 1)); // über die Zeitumstellung: genau Mitternacht
  });

  test('ease never drops below 1.3 and "again" restarts the series', () {
    var c = fresh;
    for (var i = 0; i < 10; i++) {
      c = scheduleNext(c, Rating.again, now);
    }
    expect(c.ease, 1.3);
    expect((c.lapses, c.reps), (10, 0));
    expect(scheduleNext(c, Rating.good, now).intervalDays, 1); // wieder von vorn
  });

  test('due: new cards are due at once, scheduled ones from their day', () {
    expect(fresh.isDue(now), isTrue);
    final c = scheduleNext(fresh, Rating.good, now);
    expect(c.isDue(now), isFalse);
    expect(c.isDue(DateTime(2026, 10, 21)), isTrue);
  });

  test('button labels show the next interval', () {
    expect(nextDueLabel(fresh, Rating.again, now), '10 Min');
    expect(nextDueLabel(fresh, Rating.good, now), '1 T');
    const mature = FlashCard(userid: 1, deckId: 1, front: 'a', back: 'b', due: null, intervalDays: 30, ease: 2.5, reps: 5);
    expect(nextDueLabel(mature, Rating.good, now), '3 Mon'); // 75 Tage
  });

  test('importing lines: dash, semicolon, tab and equals; lines without a separator are skipped', () {
    expect(parseCardLines('el perro – der Hund\nla casa; das Haus\nel gato\tdie Katze\nhola = hallo\nnur eine Seite\n\n'), [
      ('el perro', 'der Hund'),
      ('la casa', 'das Haus'),
      ('el gato', 'die Katze'),
      ('hola', 'hallo'),
    ]);
    expect(parseCardLines('Wasser-Kreislauf - Verdunstung, Regen'), [('Wasser-Kreislauf', 'Verdunstung, Regen')]);
  });
}
