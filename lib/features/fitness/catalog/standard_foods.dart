import 'package:frontend/features/fitness/models/nutrition.dart';

/// Kennzeichen der mitgelieferten Standardprodukte (Feld „Marke“).
const standardFoodBrand = 'Standardprodukt';

/// Ein vorab angelegtes Grundnahrungsmittel mit typischen Durchschnittswerten pro 100 g
/// (keine exakten Herstellerangaben). Ausgerichtet auf vollwertige, pflanzliche Ernährung
/// (WFPB) und das übliche Discounter-Sortiment.
class StandardFood {
  final String name;
  final String group;
  final double kcal, protein, carbs, fat;
  final double? serving;
  const StandardFood(this.name, this.group, this.kcal, this.protein, this.carbs, this.fat, [this.serving]);

  Food toFood(int userid) => Food(
        userid: userid,
        name: name,
        brand: standardFoodBrand,
        per100: Macros(kcal: kcal, protein: protein, carbs: carbs, fat: fat),
        servingGrams: serving,
        packSizes: standardPackSizes[name] ?? const [],
      );
}

/// Übliche Packungsgrößen im Discounter (g bzw. ml) – Vorschlag, im Lebensmittel änderbar.
const standardPackSizes = <String, List<double>>{
  'Haferflocken': [500, 1000],
  'Haferkleie': [500],
  'Naturreis (roh)': [500, 1000],
  'Vollkornnudeln (roh)': [500],
  'Quinoa (roh)': [400, 500],
  'Hirse (roh)': [500],
  'Buchweizen (roh)': [500],
  'Bulgur (roh)': [500, 1000],
  'Vollkorn-Couscous (roh)': [500],
  'Rote-Linsen-Nudeln (roh)': [250],
  'Kichererbsen-Nudeln (roh)': [250],
  'Kartoffeln': [1500, 2500],
  'Süßkartoffeln': [1000],
  'Vollkornbrot': [500, 750],
  'Roggenvollkornbrot': [500],
  'Vollkorn-Tortilla': [370],
  'Rote Linsen (trocken)': [500],
  'Linsen (Dose, abgetropft)': [265],
  'Kichererbsen (Dose, abgetropft)': [240, 265],
  'Kidneybohnen (Dose, abgetropft)': [250],
  'Schwarze Bohnen (Dose, abgetropft)': [250],
  'Weiße Bohnen (Dose, abgetropft)': [250],
  'Erbsen (TK)': [750, 1000],
  'Edamame (TK)': [400],
  'Tofu natur': [200, 400],
  'Räuchertofu': [200],
  'Tempeh': [200],
  'Sojagranulat (trocken)': [200, 300],
  'Sojadrink ungesüßt': [1000],
  'Haferdrink': [1000],
  'Sojajoghurt natur': [400, 500],
  'Hummus': [175, 200],
  'Brokkoli': [500],
  'Blumenkohl': [800],
  'Spinat (TK)': [450, 750],
  'Grünkohl': [450],
  'Karotten': [1000, 2000],
  'Paprika rot': [500],
  'Tomaten': [500],
  'Tomaten passiert': [500, 700],
  'Gurke': [400],
  'Zucchini': [500],
  'Aubergine': [300],
  'Zwiebeln': [1000, 2000],
  'Frühlingszwiebeln': [100],
  'Lauch': [500],
  'Knoblauch': [100, 250],
  'Champignons': [250, 400],
  'Rotkohl': [1000],
  'Feldsalat': [125],
  'Rucola': [125],
  'Rote Bete (vorgegart)': [500],
  'Sauerkraut': [520],
  'Mais (Dose, abgetropft)': [285],
  'Gemüsemischung (TK)': [750, 1000],
  'Banane': [1000],
  'Apfel': [1000, 2000],
  'Birne': [1000],
  'Orange': [1500, 2000],
  'Kiwi': [500],
  'Weintrauben': [500],
  'Avocado': [400],
  'Beerenmischung (TK)': [300, 500],
  'Heidelbeeren': [125, 250],
  'Erdbeeren': [500],
  'Mango (TK)': [400],
  'Datteln (getrocknet)': [200],
  'Rosinen': [250],
  'Walnüsse': [200],
  'Mandeln': [200],
  'Cashewkerne': [200],
  'Erdnüsse (ungesalzen)': [500],
  'Erdnussmus': [350],
  'Leinsamen (geschrotet)': [500],
  'Chiasamen': [200, 400],
  'Sonnenblumenkerne': [250],
  'Kürbiskerne': [200],
  'Hanfsamen (geschält)': [200],
  'Tahin (Sesammus)': [250],
  'Wasser': [1500],
  'Mineralwasser': [1500],
  'Apfelschorle': [1500],
  'Orangensaft': [1000],
  'Hefeflocken': [150],
};

const _grain = 'Getreide & Beilagen';
const _legume = 'Hülsenfrüchte & Soja';
const _veg = 'Gemüse';
const _fruit = 'Obst';
const _nut = 'Nüsse & Samen';
const _other = 'Sonstiges';
const _drink = 'Getränke';

const List<StandardFood> standardFoods = [
  // ─── Getreide & Beilagen (Trockengewicht, sofern nicht anders angegeben) ─
  StandardFood('Haferflocken', _grain, 372, 13.5, 58.7, 7.0, 50),
  StandardFood('Haferkleie', _grain, 360, 17, 50, 7, 20),
  StandardFood('Naturreis (roh)', _grain, 350, 7.5, 74, 2.2, 75),
  StandardFood('Vollkornnudeln (roh)', _grain, 350, 13, 64, 2.5, 90),
  StandardFood('Quinoa (roh)', _grain, 368, 14, 64, 6, 75),
  StandardFood('Hirse (roh)', _grain, 360, 10.6, 69, 4, 75),
  StandardFood('Buchweizen (roh)', _grain, 343, 13, 68, 3.4, 75),
  StandardFood('Bulgur (roh)', _grain, 342, 12, 68, 1.3, 75),
  StandardFood('Vollkorn-Couscous (roh)', _grain, 355, 12, 70, 2, 75),
  StandardFood('Rote-Linsen-Nudeln (roh)', _grain, 340, 25, 50, 2, 90),
  StandardFood('Kichererbsen-Nudeln (roh)', _grain, 350, 21, 50, 6, 90),
  StandardFood('Kartoffeln', _grain, 77, 2, 17, 0.1, 250),
  StandardFood('Süßkartoffeln', _grain, 86, 1.6, 20, 0.1, 250),
  StandardFood('Vollkornbrot', _grain, 215, 7.5, 38, 1.5, 50),
  StandardFood('Roggenvollkornbrot', _grain, 200, 6, 38, 1.2, 50),
  StandardFood('Vollkorn-Tortilla', _grain, 300, 9, 48, 6, 60),

  // ─── Hülsenfrüchte & Soja ─────────────────────────────────────────────
  StandardFood('Rote Linsen (trocken)', _legume, 340, 24, 50, 1.5, 60),
  StandardFood('Linsen (Dose, abgetropft)', _legume, 90, 7, 13, 0.5, 130),
  StandardFood('Kichererbsen (Dose, abgetropft)', _legume, 120, 7, 16, 2.5, 130),
  StandardFood('Kidneybohnen (Dose, abgetropft)', _legume, 100, 7.5, 14, 0.6, 130),
  StandardFood('Schwarze Bohnen (Dose, abgetropft)', _legume, 95, 7, 13, 0.5, 130),
  StandardFood('Weiße Bohnen (Dose, abgetropft)', _legume, 95, 7, 13, 0.4, 130),
  StandardFood('Erbsen (TK)', _legume, 75, 5.5, 10, 0.5, 150),
  StandardFood('Edamame (TK)', _legume, 121, 12, 9, 5, 150),
  StandardFood('Tofu natur', _legume, 120, 13, 1.5, 7, 100),
  StandardFood('Räuchertofu', _legume, 160, 17, 2, 9, 100),
  StandardFood('Tempeh', _legume, 192, 20, 8, 11, 100),
  StandardFood('Sojagranulat (trocken)', _legume, 330, 50, 17, 1.5, 50),
  StandardFood('Sojadrink ungesüßt', _legume, 33, 3.3, 0.2, 1.8, 250),
  StandardFood('Haferdrink', _legume, 45, 0.5, 7, 1.4, 250),
  StandardFood('Sojajoghurt natur', _legume, 45, 4, 2, 2.2, 150),
  StandardFood('Hummus', _legume, 280, 7, 12, 22, 50),

  // ─── Gemüse ───────────────────────────────────────────────────────────
  StandardFood('Brokkoli', _veg, 34, 3, 2.7, 0.4, 200),
  StandardFood('Blumenkohl', _veg, 25, 2, 2.5, 0.3, 200),
  StandardFood('Spinat (TK)', _veg, 23, 2.5, 1.5, 0.3, 150),
  StandardFood('Grünkohl', _veg, 45, 4.3, 2.5, 0.9, 150),
  StandardFood('Karotten', _veg, 36, 0.9, 7, 0.2, 120),
  StandardFood('Paprika rot', _veg, 31, 1, 6, 0.3, 150),
  StandardFood('Tomaten', _veg, 18, 0.9, 3, 0.2, 120),
  StandardFood('Tomaten passiert', _veg, 30, 1.4, 5, 0.2, 200),
  StandardFood('Gurke', _veg, 12, 0.6, 1.8, 0.1, 150),
  StandardFood('Zucchini', _veg, 19, 1.6, 2.1, 0.4, 200),
  StandardFood('Aubergine', _veg, 20, 1.2, 2.5, 0.2, 200),
  StandardFood('Zwiebeln', _veg, 36, 1.2, 7, 0.1, 80),
  StandardFood('Frühlingszwiebeln', _veg, 30, 1.8, 4.7, 0.2, 30),
  StandardFood('Lauch', _veg, 26, 2, 3.3, 0.3, 150),
  StandardFood('Knoblauch', _veg, 140, 6, 28, 0.1, 5),
  StandardFood('Champignons', _veg, 22, 3, 0.6, 0.3, 150),
  StandardFood('Rotkohl', _veg, 28, 1.5, 4, 0.2, 150),
  StandardFood('Feldsalat', _veg, 20, 1.8, 0.7, 0.4, 50),
  StandardFood('Rucola', _veg, 25, 2.6, 2, 0.7, 50),
  StandardFood('Rote Bete (vorgegart)', _veg, 45, 1.5, 8.5, 0.1, 150),
  StandardFood('Sauerkraut', _veg, 20, 1.5, 1, 0.3, 150),
  StandardFood('Mais (Dose, abgetropft)', _veg, 80, 2.5, 14, 1.2, 100),
  StandardFood('Gemüsemischung (TK)', _veg, 40, 2.5, 5.5, 0.4, 200),

  // ─── Obst ─────────────────────────────────────────────────────────────
  StandardFood('Banane', _fruit, 93, 1.1, 21, 0.2, 120),
  StandardFood('Apfel', _fruit, 54, 0.3, 12, 0.2, 150),
  StandardFood('Birne', _fruit, 55, 0.5, 12, 0.3, 150),
  StandardFood('Orange', _fruit, 47, 1, 9, 0.2, 150),
  StandardFood('Kiwi', _fruit, 50, 1, 9, 0.6, 75),
  StandardFood('Weintrauben', _fruit, 70, 0.7, 16, 0.3, 125),
  StandardFood('Avocado', _fruit, 160, 2, 1.9, 15, 70),
  StandardFood('Beerenmischung (TK)', _fruit, 45, 1, 8, 0.4, 125),
  StandardFood('Heidelbeeren', _fruit, 42, 0.6, 7.4, 0.6, 125),
  StandardFood('Erdbeeren', _fruit, 32, 0.8, 5.5, 0.4, 150),
  StandardFood('Mango (TK)', _fruit, 60, 0.8, 13, 0.4, 125),
  StandardFood('Datteln (getrocknet)', _fruit, 280, 2.5, 65, 0.5, 30),
  StandardFood('Rosinen', _fruit, 300, 2.5, 68, 0.5, 30),

  // ─── Nüsse & Samen ────────────────────────────────────────────────────
  StandardFood('Walnüsse', _nut, 654, 15, 7, 65, 30),
  StandardFood('Mandeln', _nut, 590, 22, 6, 52, 30),
  StandardFood('Cashewkerne', _nut, 575, 20, 27, 44, 30),
  StandardFood('Erdnüsse (ungesalzen)', _nut, 580, 25, 12, 48, 30),
  StandardFood('Erdnussmus', _nut, 620, 26, 12, 50, 20),
  StandardFood('Leinsamen (geschrotet)', _nut, 500, 22, 2, 39, 15),
  StandardFood('Chiasamen', _nut, 480, 21, 5, 31, 15),
  StandardFood('Sonnenblumenkerne', _nut, 590, 24, 12, 50, 20),
  StandardFood('Kürbiskerne', _nut, 590, 35, 5, 49, 20),
  StandardFood('Hanfsamen (geschält)', _nut, 590, 32, 5, 48, 20),
  StandardFood('Tahin (Sesammus)', _nut, 620, 23, 3, 55, 15),

  // ─── Getränke (pro 100 ml) ────────────────────────────────────────────
  StandardFood('Wasser', _drink, 0, 0, 0, 0, 250),
  StandardFood('Mineralwasser', _drink, 0, 0, 0, 0, 500),
  StandardFood('Kaffee (schwarz)', _drink, 2, 0.2, 0.3, 0, 200),
  StandardFood('Tee (ungesüßt)', _drink, 1, 0, 0.2, 0, 250),
  StandardFood('Apfelschorle', _drink, 24, 0, 5.5, 0, 330),
  StandardFood('Orangensaft', _drink, 45, 0.7, 10, 0.2, 200),

  // ─── Sonstiges ────────────────────────────────────────────────────────
  StandardFood('Hefeflocken', _other, 360, 45, 20, 4, 10),
];
