/// Rechnen mit Kalendertagen.
///
/// `add(Duration(days: n))` rechnet in 24-Stunden-Schritten – an der Zeitumstellung (23 bzw. 25 Stunden)
/// landet man dann auf 23:00 des Vortags bzw. 01:00. Diese Helfer zählen echte Kalendertage.
library;

/// Der Tag ohne Uhrzeit (Mitternacht, lokal).
DateTime dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

/// [d] plus [n] Kalendertage, um Mitternacht.
DateTime addDays(DateTime d, int n) => DateTime(d.year, d.month, d.day + n);

/// Kalendertage von [a] nach [b] (negativ, wenn [b] vor [a] liegt), unabhängig von Uhrzeit und Zeitumstellung.
int daysBetween(DateTime a, DateTime b) =>
    DateTime.utc(b.year, b.month, b.day).difference(DateTime.utc(a.year, a.month, a.day)).inDays;

/// Montag der Woche von [d], um Mitternacht.
DateTime weekStart(DateTime d) => DateTime(d.year, d.month, d.day - (d.weekday - 1));
