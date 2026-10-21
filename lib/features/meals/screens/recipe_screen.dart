import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import 'package:frontend/core/ui/app_actions.dart';
import 'package:frontend/core/ui/app_ui.dart';
import 'package:frontend/core/ui/modern_appbar.dart';
import 'package:frontend/core/ui/theme.dart';
import 'package:frontend/features/meals/models/meal_plan.dart';
import 'package:frontend/features/meals/repositories/meal_plan_repository.dart';
import 'package:frontend/features/lists/repositories/lists_repository.dart';
import 'package:frontend/features/meals/screens/portion_planner_screen.dart';
import 'package:frontend/features/meals/screens/recipe_editor_screen.dart';
import 'package:frontend/features/meals/widgets/meal_widgets.dart';

/// Rezept mit Zutaten (passend zur Portionenzahl), Zubereitung und Nährwerten.
/// Aus dem Essensplan geöffnet ([planned]) lässt sich das Gericht als gegessen eintragen,
/// die Portionen und die Uhrzeit ändern; aus der Rezeptliste lässt es sich einplanen.
class RecipeScreen extends StatefulWidget {
  final int userid;
  final Recipe recipe;
  final PlannedMeal? planned;
  const RecipeScreen({super.key, required this.userid, required this.recipe, this.planned});

  @override
  State<RecipeScreen> createState() => _RecipeScreenState();
}

class _RecipeScreenState extends State<RecipeScreen> {
  late final MealPlanRepository _repo = context.read<MealPlanRepository>();
  late Recipe _recipe = widget.recipe;
  late PlannedMeal? _planned = widget.planned;
  late double _servings = widget.planned?.servings ?? widget.recipe.servings.toDouble();
  bool _busy = false;

  double get _factor => _servings / _recipe.servings;

  Future<void> _setServings(double servings) async {
    if (servings < 0.5) return;
    setState(() => _servings = servings);
    final planned = _planned;
    if (planned != null && !planned.eaten) {
      final updated = planned.copyWith(servings: servings);
      _planned = updated;
      await _repo.update(updated);
    }
  }

  Future<void> _pickTime() async {
    final planned = _planned!;
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: planned.minutes ~/ 60, minute: planned.minutes % 60),
      helpText: 'Uhrzeit für ${planned.meal.label}',
    );
    if (picked == null) return;
    final updated = planned.copyWith(time: picked.hour * 60 + picked.minute);
    await _repo.update(updated);
    if (mounted) setState(() => _planned = updated);
  }

  Future<void> _toggleEaten() async {
    final planned = _planned!;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    final updated = await runGuarded(context, () => planned.eaten ? _repo.unmarkEaten(planned) : _repo.markEaten(planned, _recipe));
    if (!mounted) return;
    setState(() {
      if (updated != null) _planned = updated;
      _busy = false;
    });
    if (updated == null) return;
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(SnackBar(
      content: Text(updated.eaten
          ? '${(_recipe.perServing.kcal * updated.servings).round()} kcal unter ${updated.meal.label} eingetragen'
          : 'Aus dem Ernährungsprotokoll entfernt'),
    ));
  }

  Future<void> _toShopping() async {
    final messenger = ScaffoldMessenger.of(context);
    final added = await _repo.addToShopping(widget.userid, [(_recipe, _servings)]);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(SnackBar(
      content: Text(added == 0
          ? 'Das Rezept hat keine Zutaten'
          : '$added ${added == 1 ? 'Zutat' : 'Zutaten'} auf der Einkaufsliste – nochmal tippen ersetzt sie, statt sie zu verdoppeln'),
    ));
  }

  /// Ganzes Rezept einplanen und alle Portionen verteilen.
  Future<void> _plan() async {
    final saved = await Navigator.of(context).push<bool>(MaterialPageRoute(
      builder: (_) => PortionPlannerScreen(userid: widget.userid, recipe: _recipe, initialDate: DateTime.now()),
    ));
    if (saved == true && mounted) showAppSnack(context, '„${_recipe.name}“ eingeplant');
  }

  /// Vertippt? Alle Zutaten dieses Rezepts (die nicht zu einem Koch-Block gehören) wieder herunter.
  Future<void> _removeFromShopping() async {
    final lists = context.read<ListsRepository>();
    late String at;
    await deleteWithUndo(
      context,
      label: 'Zutaten von ${_recipe.name}',
      delete: () async => at = await lists.removeFromList(widget.userid,
          recipeKey: _recipe.key, recipeId: _recipe.key == null ? _recipe.id : null, onlyWithoutBatch: true),
      restore: () => lists.restoreRemoved(widget.userid, at),
    );
  }

  Future<void> _edit() async {
    final navigator = Navigator.of(context);
    final result = await navigator.push<Object?>(
      MaterialPageRoute(builder: (_) => RecipeEditorScreen(userid: widget.userid, recipe: _recipe)),
    );
    if (result == RecipeEditorScreen.deleted) {
      navigator.pop(kDeletedResult); // die Rezeptliste löscht mit „Rückgängig“
    } else if (result is Recipe && mounted) {
      setState(() => _recipe = result);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final t = Theme.of(context).textTheme;
    final r = _recipe;
    final planned = _planned;
    final total = r.perServing.scaled(_servings);
    return Scaffold(
      appBar: ModernAppBar(
        title: r.name,
        customActions: [
          if (r.isOwn) IconButton(tooltip: 'Rezept bearbeiten', icon: const Icon(Icons.edit_outlined), onPressed: _edit),
        ],
      ),
      body: ListView(padding: detailPadding(context), children: [
        if (r.summary.isNotEmpty) ...[
          Text(r.summary, style: t.bodyMedium?.copyWith(color: c.muted)),
          const SizedBox(height: 12),
        ],
        if (planned != null) ...[
          AppCard(
            padding: const EdgeInsets.fromLTRB(14, 8, 8, 8),
            child: Row(children: [
              Icon(mealIcon(planned.meal), color: c.accentText),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  '${DateFormat('EEEE, d. MMMM', 'de_DE').format(planned.date)}\n'
                  '${planned.meal.label} um ${formatMinutes(planned.minutes)} Uhr',
                  style: t.bodyMedium,
                ),
              ),
              TextButton(onPressed: _pickTime, child: const Text('Uhrzeit')),
            ]),
          ),
          const SizedBox(height: 12),
        ],
        Wrap(spacing: 8, runSpacing: 8, children: [
          _Fact(icon: Icons.timer_outlined, label: '${r.minutes} min'),
          _Fact(icon: Icons.local_fire_department_outlined, label: '${r.perServing.kcal.round()} kcal / Portion'),
          for (final m in r.meals) _Fact(icon: mealIcon(m), label: m.label),
        ]),
        const SizedBox(height: 16),
        AppCard(
          padding: const EdgeInsets.fromLTRB(14, 6, 6, 6),
          child: Row(children: [
            Expanded(child: Text('Portionen', style: t.titleMedium)),
            IconButton(
              tooltip: 'Weniger Portionen',
              onPressed: planned?.eaten == true ? null : () => _setServings(_servings - (_servings > 1 ? 1 : 0.5)),
              icon: const Icon(Icons.remove_circle_outline),
            ),
            Text(portionsLabel(_servings), style: t.titleMedium),
            IconButton(
              tooltip: 'Mehr Portionen',
              onPressed: planned?.eaten == true ? null : () => _setServings(_servings < 1 ? 1 : _servings + 1),
              icon: const Icon(Icons.add_circle_outline),
            ),
          ]),
        ),
        const SizedBox(height: 20),
        const GroupLabel('Zutaten'),
        AppCard(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          child: Column(children: [
            for (final (i, ingredient) in r.ingredients.indexed)
              Container(
                padding: const EdgeInsets.symmetric(vertical: 8),
                decoration: BoxDecoration(
                  border: i == 0 ? null : Border(top: BorderSide(color: c.line.withValues(alpha: 0.5))),
                ),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  SizedBox(
                    width: 92,
                    child: Text(ingredient.amountFor(_factor),
                        style: t.bodyMedium?.copyWith(fontWeight: FontWeight.w700, color: c.accentText)),
                  ),
                  Expanded(child: Text(ingredient.name, style: t.bodyMedium)),
                ]),
              ),
          ]),
        ),
        const SizedBox(height: 20),
        const GroupLabel('Zubereitung'),
        for (final (i, step) in r.steps.indexed)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              CircleAvatar(
                radius: 13,
                backgroundColor: c.accent,
                child: Text('${i + 1}', style: TextStyle(fontSize: 12, color: c.onAccent, fontWeight: FontWeight.w700)),
              ),
              const SizedBox(width: 10),
              Expanded(child: Padding(padding: const EdgeInsets.only(top: 3), child: Text(step, style: t.bodyMedium))),
            ]),
          ),
        const SizedBox(height: 10),
        GroupLabel('Nährwerte', trailing: 'für ${portionsLabel(_servings)}'),
        AppCard(
          padding: const EdgeInsets.all(14),
          child: Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
            _Macro('kcal', total.kcal),
            _Macro('Eiweiß', total.protein, unit: 'g'),
            _Macro('Kohlenh.', total.carbs, unit: 'g'),
            _Macro('Fett', total.fat, unit: 'g'),
          ]),
        ),
        const SizedBox(height: 20),
        if (planned != null)
          planned.eaten
              ? OutlinedButton.icon(
                  onPressed: _busy ? null : _toggleEaten,
                  icon: Icon(Icons.check_circle_rounded, color: c.positive),
                  label: const Text('Gegessen – rückgängig machen'),
                )
              : ElevatedButton.icon(
                  onPressed: _busy ? null : _toggleEaten,
                  icon: const Icon(Icons.restaurant_rounded),
                  label: const Text('Als gegessen eintragen'),
                )
        else
          ElevatedButton.icon(
            onPressed: _plan,
            icon: const Icon(Icons.event_available_rounded),
            label: const Text('Einplanen'),
          ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: _toShopping,
          icon: const Icon(Icons.add_shopping_cart_rounded),
          label: const Text('Zutaten auf die Einkaufsliste'),
        ),
        TextButton.icon(
          onPressed: _removeFromShopping,
          icon: const Icon(Icons.remove_shopping_cart_outlined),
          label: const Text('Zutaten wieder von der Einkaufsliste nehmen'),
        ),
      ]),
    );
  }
}

class _Fact extends StatelessWidget {
  final IconData icon;
  final String label;
  const _Fact({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(color: c.cardAlt, borderRadius: BorderRadius.circular(20)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 16, color: c.accentText),
        const SizedBox(width: 6),
        Text(label, style: TextStyle(fontSize: 12, color: c.text)),
      ]),
    );
  }
}

class _Macro extends StatelessWidget {
  final String label;
  final double value;
  final String unit;
  const _Macro(this.label, this.value, {this.unit = ''});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Column(children: [
      Text('${value.round()}${unit.isEmpty ? '' : ' $unit'}', style: t.titleMedium),
      Text(label, style: t.labelMedium),
    ]);
  }
}

/// Öffnet das Rezept zu einer geplanten Mahlzeit; meldet, wenn es nicht mehr existiert.
Future<void> openPlannedMeal(BuildContext context, int userid, PlannedMeal planned) async {
  final navigator = Navigator.of(context);
  final messenger = ScaffoldMessenger.of(context);
  final repo = context.read<MealPlanRepository>();
  final recipe = await repo.recipeFor(planned);
  if (recipe == null) {
    messenger.showSnackBar(SnackBar(content: Text('Das Rezept zu „${planned.name}“ wurde gelöscht.')));
    return;
  }
  final result = await navigator.push<Object?>(
    MaterialPageRoute(builder: (_) => RecipeScreen(userid: userid, recipe: recipe, planned: planned)),
  );
  if (result == kDeletedResult && recipe.id != null && context.mounted) {
    await deleteWithUndo(
      context,
      label: recipe.name,
      delete: () => repo.deleteRecipe(recipe.id!),
      restore: () => repo.restoreRecipe(recipe.id!),
    );
  }
}
