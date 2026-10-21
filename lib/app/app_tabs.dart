/// Tabs der unteren Leiste – nach Nutzung: das Tägliche vorn, Seltenes unter „Mehr“.
enum AppTab { today, plan, food, training, money, more }

/// Unterbereiche von [AppTab.plan]; die Reihenfolge ist die der Chips.
enum PlanSection { todos, habits, appointments, journal }

/// Unterbereiche von [AppTab.food]; die Reihenfolge ist die der Chips.
enum FoodSection { nutrition, mealPlan, shopping, pantry }

/// Seiten unter [AppTab.more]; sie öffnen sich als eigene Seite.
enum MoreSection { learning, contacts, gifts, wardrobe, outfits, wishlist }

/// Wechselt zu [tab] und dort zum Unterbereich [section] ([PlanSection] oder [FoodSection]).
typedef TabNavigator = void Function(AppTab tab, [Enum? section]);
