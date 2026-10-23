import 'package:flutter/material.dart';

import 'package:frontend/app/app_tabs.dart';
import 'package:frontend/app/tab_style.dart';
import 'package:frontend/core/ui/hub_tabs.dart';
import 'package:frontend/features/auth/models/user.dart';
import 'package:frontend/features/fitness/screens/nutrition_screen.dart';
import 'package:frontend/features/fitness/widgets/food_actions.dart';
import 'package:frontend/features/inventory/models/inventory_item.dart';
import 'package:frontend/features/inventory/screens/inventory_screen.dart';
import 'package:frontend/features/lists/screens/shopping_list_screen.dart';
import 'package:frontend/features/meals/screens/meal_plan_screen.dart';
import 'package:frontend/features/receipts/screens/receipt_review_screen.dart';

/// Tab „Essen“: Ernährung, Essensplan, Einkauf und Vorrat.
class FoodHubScreen extends StatelessWidget {
  final UserModel user;
  final FoodSection initialSection;
  final ValueChanged<FoodSection>? onSectionChanged;
  const FoodHubScreen({super.key, required this.user, this.initialSection = FoodSection.nutrition, this.onSectionChanged});

  @override
  Widget build(BuildContext context) {
    return HubTabs(
      title: AppTab.food.style.label,
      icon: AppTab.food.style.activeIcon,
      color: AppTab.food.style.toneOf(context),
      initialIndex: initialSection.index,
      onChanged: (i) => onSectionChanged?.call(FoodSection.values[i]),
      tabs: [
        for (final s in FoodSection.values)
          switch (s) {
            FoodSection.nutrition => HubTab('Ernährung', (_) => NutritionScreen(user: user)),
            FoodSection.mealPlan => HubTab('Essensplan', (_) => MealPlanScreen(user: user)),
            FoodSection.shopping => HubTab('Einkauf', (_) => ShoppingListScreen(user: user)),
            FoodSection.pantry => HubTab('Vorrat', (_) => InventoryScreen(
                  user: user,
                  kinds: const {InventoryKind.food, InventoryKind.drink, InventoryKind.care, InventoryKind.other},
                  addKind: InventoryKind.food,
                  addKinds: const [InventoryKind.food, InventoryKind.drink, InventoryKind.care, InventoryKind.other],
                  onScanBarcode: () => scanPantryItem(context, user.uid),
                  onScanReceipt: (onSaved) => scanReceipt(context, userid: user.uid, onSaved: onSaved),
                )),
          },
      ],
    );
  }
}
