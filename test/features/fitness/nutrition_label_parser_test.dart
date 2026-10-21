import 'package:flutter_test/flutter_test.dart';

import 'package:frontend/features/fitness/services/nutrition_label_parser.dart';

void main() {
  test('German table: kJ/kcal in one row, per-100 g column first, portion size from the header', () {
    final v = parseNutritionLabel(const [
      'Nährwerte pro 100 g pro Portion (40 g)',
      'Brennwert 1550 kJ / 370 kcal 620 kJ / 148 kcal',
      'Fett 7,0 g 2,8 g',
      'davon gesättigte Fettsäuren 1,2 g 0,5 g',
      'Kohlenhydrate 59 g 24 g',
      'davon Zucker 1,0 g 0,4 g',
      'Ballaststoffe 10 g 4,0 g',
      'Eiweiß 13 g 5,2 g',
      'Salz 0,02 g 0,01 g',
    ])!;
    expect((v.kcal, v.fat, v.carbs, v.protein, v.servingGrams), (370.0, 7.0, 59.0, 13.0, 40.0));
  });

  test('kJ and kcal on separate rows, OCR splits decimals at the comma, "Eiweiss" spelling', () {
    final v = parseNutritionLabel(const [
      'Durchschnittliche Nährwerte je 100 g',
      'Energie 418 kJ',
      '100 kcal',
      'Fett 3, 5 g',
      'Kohlenhydrate 4 , 7 g',
      'Eiweiss 9,8 g',
    ])!;
    expect((v.kcal, v.fat, v.carbs, v.protein), (100.0, 3.5, 4.7, 9.8));
    expect(v.servingGrams, isNull);
  });

  test('only kJ given: kcal is calculated; English labels work too', () {
    final v = parseNutritionLabel(const [
      'Nutrition per 100 g',
      'Energy 2092 kJ',
      'Fat 30 g',
      'of which saturates 4 g',
      'Carbohydrate 50 g',
      'Protein 10 g',
    ])!;
    expect(v.kcal, closeTo(500, 0.5));
    expect((v.fat, v.carbs, v.protein), (30.0, 50.0, 10.0));
  });

  test('a text without nutrition values gives null; a partial table keeps what was found', () {
    expect(parseNutritionLabel(const ['REWE', 'Summe 4,20']), isNull);
    final v = parseNutritionLabel(const ['Brennwert 1200 kJ / 287 kcal', 'Eiweiß 20 g'])!;
    expect((v.kcal, v.protein, v.fat, v.carbs), (287.0, 20.0, null, null));
    expect(v.complete, isFalse);
  });

  test('columns run together in the OCR: kcal is taken from the per-100 g kJ when the kcal does not fit', () {
    // So kam die Zeile auf dem Emulator aus der echten Texterkennung: „370 kcal“ und „620 kJ“ verschmolzen
    final v = parseNutritionLabel(const ['Brennwert 1550 kJ / 370620kJ / 148 kcal', 'Eiweiß 13 g 5,2 g'])!;
    expect(v.kcal, closeTo(370.5, 0.1));
    // passt die kcal-Zahl zu den kJ, bleibt sie (Rundung auf der Packung)
    expect(parseNutritionLabel(const ['Brennwert 1550 kJ / 370 kcal'])!.kcal, 370);
  });
}
