import 'package:frontend/core/models/decimals.dart';

/// Aus einer fotografierten Nährwerttabelle gelesene Werte pro 100 g (fehlende sind `null`).
class LabelValues {
  final double? kcal, protein, carbs, fat;

  /// Portionsgröße aus „pro Portion (40 g)“, falls angegeben.
  final double? servingGrams;

  const LabelValues({this.kcal, this.protein, this.carbs, this.fat, this.servingGrams});

  bool get complete => kcal != null && protein != null && carbs != null && fat != null;
}

double _num(String s) => double.parse(s.replaceAll(',', '.'));

final _amount = RegExp(r'(\d+(?:[.,]\d+)?)\s*g\b', caseSensitive: false);

/// Erste Grammangabe der Zeile – die Spalte „pro 100 g“ steht vor „pro Portion“.
double? _firstGrams(String line) {
  final m = _amount.firstMatch(line);
  return m == null ? null : _num(m.group(1)!);
}

/// Liest kcal, Fett, Kohlenhydrate und Eiweiß pro 100 g aus den Zeilen einer Nährwerttabelle
/// (deutsch oder englisch, wie die Texterkennung sie liefert). `null`, wenn nichts davon erkannt wurde.
LabelValues? parseNutritionLabel(List<String> rawLines) {
  final lines = [for (final l in rawLines) joinSplitDecimals(l, decimals: '1,2')]..removeWhere((l) => l.isEmpty);
  double? kcal, kj, protein, carbs, fat, serving;

  for (var i = 0; i < lines.length; i++) {
    final line = lines[i];
    final l = line.toLowerCase();

    serving ??= () {
      final m = RegExp(r'portion\D{0,12}?(\d+(?:[.,]\d+)?)\s*g', caseSensitive: false).firstMatch(line) ??
          RegExp(r'serving\D{0,12}?(\d+(?:[.,]\d+)?)\s*g', caseSensitive: false).firstMatch(line);
      return m == null ? null : _num(m.group(1)!);
    }();

    // Energie: kcal bevorzugt, auch in der Folgezeile („418 kJ“ / „100 kcal“)
    final kcalMatch = RegExp(r'(\d+(?:[.,]\d+)?)\s*kcal', caseSensitive: false).firstMatch(line);
    final kjMatch = RegExp(r'(\d+(?:[.,]\d+)?)\s*kj', caseSensitive: false).firstMatch(line);
    if (kcal == null && kcalMatch != null && (l.contains('energ') || l.contains('brennwert') || RegExp(r'^\s*\d').hasMatch(line))) {
      kcal = _num(kcalMatch.group(1)!);
    }
    if (kj == null && kjMatch != null) kj = _num(kjMatch.group(1)!);

    // Wortende per Vorausschau prüfen – eine Wortgrenze greift nach „ß“ nicht.
    // Unterzeilen („davon Zucker“, „of which saturates“) zählen nicht
    if (l.contains('davon') || l.contains('of which') || l.contains('gesättigt') || l.contains('saturates')) continue;
    if (fat == null && RegExp(r'^\s*(fett|fat)(?![a-zäöüß])').hasMatch(l)) fat = _firstGrams(line);
    if (carbs == null && RegExp(r'^\s*(kohlenhydrate|carbohydrates?)(?![a-zäöüß])').hasMatch(l)) carbs = _firstGrams(line);
    if (protein == null && RegExp(r'^\s*(eiwei(ß|ss)|protein)(?![a-zäöüß])').hasMatch(l)) protein = _firstGrams(line);
  }

  // kJ der 100-g-Spalte stehen vorn und sind verlässlicher: Laufen Spalten in der Texterkennung
  // zusammen, gehört die erste kcal-Zahl evtl. zur Portion – dann aus den kJ rechnen.
  final fromKj = kj == null ? null : (kj / 4.184 * 10).round() / 10;
  if (fromKj != null && (kcal == null || (kcal - fromKj).abs() > fromKj * 0.05)) kcal = fromKj;
  if (kcal == null && protein == null && carbs == null && fat == null) return null;
  return LabelValues(kcal: kcal, protein: protein, carbs: carbs, fat: fat, servingGrams: serving);
}
