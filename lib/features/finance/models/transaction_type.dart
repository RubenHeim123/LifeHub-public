import 'package:flutter/foundation.dart';

/// Art einer Buchung. [label] ist zugleich der in der Datenbank gespeicherte Wert,
/// damit bestehende Daten ohne Migration lesbar bleiben.
enum TransactionType {
  income('Einnahme'),
  expense('Ausgabe');

  const TransactionType(this.label);
  final String label;

  String get dbValue => label;

  bool get isIncome => this == income;
  bool get isExpense => this == expense;

  /// Vorzeichen für Kontostände: Einnahmen erhöhen, Ausgaben verringern.
  double get sign => isIncome ? 1 : -1;

  /// Liest auch englische bzw. klein geschriebene Werte (Importe, Sync). Ein unbekannter Wert
  /// darf nicht ganze Bildschirme lahmlegen – er wird als Ausgabe gelesen und protokolliert.
  static TransactionType fromDb(Object? value) {
    switch ('${value ?? ''}'.trim().toLowerCase()) {
      case 'einnahme' || 'income' || 'einnahmen':
        return income;
      case 'ausgabe' || 'expense' || 'ausgaben':
        return expense;
      default:
        debugPrint('Unbekannter Transaktionstyp „$value“ – als Ausgabe gelesen');
        return expense;
    }
  }
}

/// Kategorie, unter der Umbuchungen zwischen eigenen Konten gespeichert werden.
/// Umbuchungen bestehen aus einer Ausgabe und einer Einnahme und zählen nicht als Umsatz.
const String kTransferCategory = 'Umbuchung';
