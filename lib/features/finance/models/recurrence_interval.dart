/// Intervall einer wiederkehrenden Transaktion.
///
/// Termine werden immer vom Startdatum aus berechnet ([occurrence]), nie vom
/// vorherigen Termin. So wird aus dem 31.01. monatlich 28./29.02., 31.03., 30.04. …
/// statt dauerhaft auf den 28. abzurutschen.
enum RecurrenceInterval {
  daily('Täglich', days: 1),
  weekly('Wöchentlich', days: 7),
  monthly('Monatlich', months: 1),
  quarterly('Vierteljährlich', months: 3),
  halfYearly('Halbjährlich', months: 6),
  yearly('Jährlich', months: 12);

  const RecurrenceInterval(this.label, {this.days = 0, this.months = 0});

  final String label;
  final int days;
  final int months;

  String get dbValue => label;

  /// Liest auch ältere Schreibweisen ("Vierteljaehrlich", "monthly" …).
  static RecurrenceInterval fromDb(String value) {
    final v = value.trim().toLowerCase().replaceAll('ae', 'ä');
    for (final i in values) {
      if (i.label.toLowerCase() == v || i.name.toLowerCase() == v) return i;
    }
    throw ArgumentError.value(value, 'interval', 'Unbekanntes Intervall');
  }

  /// Wie [fromDb], aber ohne Ausnahme: unbekannte Werte aus der Datenbank gelten als monatlich.
  static RecurrenceInterval fromDbOrMonthly(Object? value) {
    try {
      return fromDb('${value ?? ''}');
    } catch (_) {
      return monthly;
    }
  }

  /// Der [n]-te Termin ab [start] (n = 0 ist [start] selbst). Uhrzeit bleibt erhalten.
  DateTime occurrence(DateTime start, int n) {
    if (months == 0) {
      return DateTime(start.year, start.month, start.day + n * days, start.hour, start.minute, start.second);
    }
    final targetMonth = start.month + n * months;
    final lastDay = DateTime(start.year, targetMonth + 1, 0).day;
    final day = start.day > lastDay ? lastDay : start.day;
    return DateTime(start.year, targetMonth, day, start.hour, start.minute, start.second);
  }

  /// Betrag auf einen Monat umgerechnet (für Übersichten).
  double monthlyEquivalent(double amount) =>
      months == 0 ? amount * (365 / 12) / days : amount / months;
}
