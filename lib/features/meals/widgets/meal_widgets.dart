import 'package:flutter/material.dart';

import 'package:frontend/core/ui/app_ui.dart';
import 'package:frontend/core/ui/theme.dart';
import 'package:frontend/features/fitness/models/nutrition.dart';
import 'package:frontend/features/meals/models/meal_plan.dart';

IconData mealIcon(Meal meal) => switch (meal) {
      Meal.breakfast => Icons.free_breakfast_rounded,
      Meal.lunch => Icons.lunch_dining_rounded,
      Meal.dinner => Icons.dinner_dining_rounded,
      Meal.snack => Icons.apple_rounded,
      Meal.drinks => Icons.local_drink_rounded,
    };

/// „25 min · 605 kcal · 27 g Eiweiß“
String recipeFacts(Recipe r) =>
    '${r.minutes} min · ${r.perServing.kcal.round()} kcal · ${r.perServing.protein.round()} g Eiweiß';

/// Karte eines Rezepts in Listen.
class RecipeCard extends StatelessWidget {
  final Recipe recipe;
  final VoidCallback? onTap;
  const RecipeCard({super.key, required this.recipe, this.onTap});

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final t = Theme.of(context).textTheme;
    final r = recipe;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: GestureDetector(
        child: AppCard(
          onTap: onTap,
          padding: const EdgeInsets.all(14),
          child: Row(children: [
            IconTile(icon: mealIcon(r.meals.isEmpty ? Meal.lunch : r.meals.first), color: c.accentText),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(r.name, style: t.titleMedium),
                if (r.summary.isNotEmpty) Text(r.summary, style: t.bodySmall, maxLines: 2, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 4),
                Text(recipeFacts(r), style: t.labelMedium?.copyWith(color: c.accentText)),
                if (r.isOwn || r.tags.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Wrap(spacing: 6, runSpacing: 4, children: [
                    for (final tag in [if (r.isOwn) 'Eigenes Rezept', ...r.tags]) _Tag(tag),
                  ]),
                ],
              ]),
            ),
            const Icon(Icons.chevron_right_rounded),
          ]),
        ),
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  final String label;
  const _Tag(this.label);

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(color: c.cardAlt, borderRadius: BorderRadius.circular(20)),
      child: Text(label, style: TextStyle(fontSize: 11, color: c.muted)),
    );
  }
}
