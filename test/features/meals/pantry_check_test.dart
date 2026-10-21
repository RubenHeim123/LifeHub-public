import 'package:flutter_test/flutter_test.dart';

import 'package:frontend/features/fitness/models/nutrition.dart';
import 'package:frontend/features/inventory/models/inventory_item.dart';
import 'package:frontend/features/meals/models/meal_plan.dart';
import 'package:frontend/features/meals/services/pantry_check.dart';

void main() {
  const dal = Recipe(
    name: 'Rote-Linsen-Dal',
    meals: {Meal.lunch},
    servings: 3,
    ingredients: [
      Ingredient('Rote Linsen', 200, 'g'),
      Ingredient('Kokosmilch', 1, 'Dose'),
      Ingredient('Gehackte Tomaten', 1, 'Dose'),
      Ingredient('Salz', 1, 'TL'),
      Ingredient('Zwiebel', 1),
    ],
  );

  InventoryItem item(int id, String name, double qty, [String? unit]) =>
      InventoryItem(id: id, userid: 1, kind: InventoryKind.food, name: name, quantity: qty, unit: unit);

  PantryCheck of(List<PantryCheck> checks, String name) => checks.firstWhere((c) => c.ingredient.name == name);

  test('triple amount: enough, partial (kg in the pantry), missing and count units', () {
    final checks = checkPantryItems(recipe: dal, factor: 3, pantry: [
      item(1, 'Rote Linsen', 0.4, 'kg'), // 400 g von 600 g
      item(2, 'Gehackte Tomaten', 5), // Stück ↔ Dose
      item(3, 'Salz', 1, 'Pck.'),
      item(4, 'Zwiebeln', 2),
    ]);

    final lentils = of(checks, 'Rote Linsen');
    expect((lentils.status, lentils.need, lentils.needUnit), (PantryStatus.partial, 600, 'g'));
    expect(lentils.reserve, 0.4); // in kg, der Einheit des Artikels
    expect(lentils.shortfall, closeTo(200, 1e-9)); // in g auf die Einkaufsliste

    expect(of(checks, 'Kokosmilch').status, PantryStatus.missing);
    expect(of(checks, 'Kokosmilch').shortfall, 3);

    final tomatoes = of(checks, 'Gehackte Tomaten');
    expect((tomatoes.status, tomatoes.reserve), (PantryStatus.enough, 3));

    final salt = of(checks, 'Salz'); // 3 TL aus einer Packung: nicht vergleichbar, aber vorhanden
    expect((salt.status, salt.comparable, salt.reserve), (PantryStatus.enough, false, null));

    expect(of(checks, 'Zwiebel').status, PantryStatus.partial); // 2 von 3 Stück
  });

  test('what another cooking session reserved is no longer offered', () {
    final pantry = [item(1, 'Rote Linsen', 600, 'g'), item(3, 'Salz', 1, 'Pck.')];
    final reserved = [
      const PantryReservation(userid: 1, batchId: 7, itemId: 1, ingredient: 'Rote Linsen', amount: 600, unit: 'g'),
      const PantryReservation(userid: 1, batchId: 7, itemId: 3, ingredient: 'Salz'), // Menge unklar
    ];
    final checks = checkPantryItems(recipe: dal, factor: 1, pantry: pantry, reserved: reserved);
    final lentils = of(checks, 'Rote Linsen');
    expect((lentils.status, lentils.inPantry, lentils.shortfall), (PantryStatus.missing, false, 200));
    // Gewürze mit unklarer Menge blockieren andere Gerichte nicht
    expect(of(checks, 'Salz').inPantry, isTrue);
  });

  test('a second pack is used when the first one is reserved', () {
    final checks = checkPantryItems(
      recipe: dal,
      factor: 1,
      pantry: [item(1, 'Rote Linsen', 200, 'g'), item(9, 'Rote Linsen Bio', 500, 'g')],
      reserved: const [PantryReservation(userid: 1, batchId: 7, itemId: 1, ingredient: 'Rote Linsen', amount: 200, unit: 'g')],
    );
    final lentils = of(checks, 'Rote Linsen');
    expect((lentils.item!.id, lentils.status, lentils.reserve), (9, PantryStatus.enough, 200));
  });

  test('ingredient names match like on the cook screen', () {
    expect(matchesIngredient('Paprika', 'Paprika rot'), isTrue);
    expect(matchesIngredient('Ei', 'Eisbergsalat'), isFalse); // kurze Wörter passen nicht zu allem
    expect(matchesIngredient('Zwiebel', 'Zwiebeln'), isTrue);
    expect(matchesIngredient('Kokosmilch', 'Haferflocken'), isFalse);
  });
}
