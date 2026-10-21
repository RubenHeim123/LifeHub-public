import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import 'package:frontend/core/models/dates.dart';
import 'package:frontend/core/ui/app_actions.dart';
import 'package:frontend/core/ui/dialogs.dart';
import 'package:frontend/core/ui/app_ui.dart';
import 'package:frontend/core/ui/theme.dart';
import 'package:frontend/features/auth/models/user.dart';
import 'package:frontend/features/fitness/models/nutrition.dart';
import 'package:frontend/features/fitness/repositories/nutrition_repository.dart';
import 'package:frontend/features/fitness/screens/nutrition_screen.dart';
import 'package:frontend/features/fitness/widgets/food_actions.dart';
import 'package:frontend/features/meals/models/meal_plan.dart';
import 'package:frontend/features/meals/repositories/meal_plan_repository.dart';
import 'package:frontend/features/meals/screens/cook_screen.dart';
import 'package:frontend/features/meals/screens/portion_planner_screen.dart';
import 'package:frontend/features/meals/screens/recipe_screen.dart';
import 'package:frontend/features/meals/screens/recipes_screen.dart';
import 'package:frontend/features/meals/widgets/meal_widgets.dart';

/// Essensplan einer Woche: Für jeden Tag stehen Frühstück, Mittag, Snack und Abendessen mit
/// Uhrzeit. Rezepte werden immer ganz eingeplant (Koch-Block) und ihre Portionen vollständig
/// verteilt; am Kochtag lässt sich „Gekocht“ mit dem Vorratsverbrauch eintragen.
/// Antippen eines Gerichts zeigt das Rezept.
class MealPlanScreen extends StatefulWidget {
  final UserModel user;

  /// Für Tests; sonst die aktuelle Zeit.
  final DateTime Function()? clock;
  const MealPlanScreen({super.key, required this.user, this.clock});

  @override
  State<MealPlanScreen> createState() => _MealPlanScreenState();
}

class _MealPlanScreenState extends State<MealPlanScreen> {
  late final MealPlanRepository _repo = context.read<MealPlanRepository>();
  late DateTime _day = _dateOnly(_now());
  List<PlannedMeal>? _week;
  List<MealBatch> _batches = const [];
  Map<String, Recipe> _recipes = {};

  /// Je Koch-Block: noch keiner Mahlzeit zugeordnete Portionen und reservierte Zutaten.
  Map<int, double> _unplanned = const {};

  /// Eingeplante einzelne Lebensmittel (für Nährwerte und „Gegessen“).
  Map<int, Food> _foods = const {};
  Map<int, int> _reserved = const {};

  int get _uid => widget.user.uid;
  DateTime _now() => (widget.clock ?? DateTime.now)();
  static DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);
  DateTime get _weekStart => weekStart(_day);
  List<DateTime> get _days => [for (var i = 0; i < 7; i++) addDays(_weekStart, i)];

  static String _recipeId(String? key, int? id) => key ?? 'own-$id';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final from = _weekStart;
    final nutrition = context.read<NutritionRepository>();
    final results = await Future.wait([
      _repo.getRange(_uid, from, addDays(from, 6)),
      _repo.getRecipes(_uid),
      _repo.getBatches(_uid, from, addDays(from, 6)),
    ]);
    final recipes = {for (final r in results[1] as List<Recipe>) _recipeId(r.key, r.id): r};
    final batches = results[2] as List<MealBatch>;
    final unplanned = <int, double>{};
    final reserved = <int, int>{};
    final foods = <int, Food>{};
    await Future.wait([
      for (final id in {for (final p in results[0] as List<PlannedMeal>) if (p.foodId != null) p.foodId!})
        nutrition.getFood(id).then((f) {
          if (f != null) foods[id] = f;
        }),
      for (final b in batches) ...[
        if (recipes[_recipeId(b.recipeKey, b.recipeId)] case final recipe?)
          _repo.unplannedServings(b, recipe).then((v) => unplanned[b.id!] = v),
        _repo.reservationsOf(b.id!).then((r) => reserved[b.id!] = r.length),
      ],
    ]);
    if (!mounted) return;
    setState(() {
      _week = results[0] as List<PlannedMeal>;
      _recipes = recipes;
      _batches = batches;
      _unplanned = unplanned;
      _reserved = reserved;
      _foods = foods;
    });
  }

  void _select(DateTime day) {
    final sameWeek = weekStart(day) == _weekStart;
    setState(() => _day = _dateOnly(day));
    if (!sameWeek) _load();
  }

  Recipe? _recipeOf(String? key, int? id) => _recipes[_recipeId(key, id)];

  /// Rezept wählen und ganz einplanen – bei „+“ in einer Mahlzeit liegt dort schon die erste Portion.
  /// „+“: Kochen planen, ein Gericht ohne Kochen (Reste, Kantine, auswärts) oder ein einzelnes
  /// Lebensmittel – wie in der Ernährung, auch per Foto.
  Future<void> _add([Meal? meal]) async {
    final kind = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            leading: const Icon(Icons.soup_kitchen_outlined),
            title: const Text('Kochen planen'),
            subtitle: const Text('Rezept kochen und Portionen verteilen'),
            onTap: () => Navigator.pop(ctx, 'recipe'),
          ),
          ListTile(
            leading: const Icon(Icons.restaurant_rounded),
            title: const Text('Gericht ohne Kochen'),
            subtitle: const Text('Reste, Kantine, auswärts – ohne Einkauf und Vorrat'),
            onTap: () => Navigator.pop(ctx, 'dish'),
          ),
          ListTile(
            leading: const Icon(Icons.egg_alt_outlined),
            title: const Text('Lebensmittel'),
            subtitle: const Text('Suche, Foto, Barcode oder aus dem Vorrat'),
            onTap: () => Navigator.pop(ctx, 'food'),
          ),
        ]),
      ),
    );
    if (kind == null || !mounted) return;
    if (kind == 'food') return _addFood(meal ?? Meal.lunch);
    if (kind == 'dish') return _addWithoutCooking(meal);
    await _addRecipe(meal);
  }

  /// Ein Rezept nur einplanen: keine Koch-Planung, kein Termin, kein Vorrat, keine Einkaufsliste.
  Future<void> _addWithoutCooking(Meal? meal) async {
    final day = _day;
    final recipe = await Navigator.of(context).push<Recipe>(
      MaterialPageRoute(builder: (_) => RecipesScreen(userid: _uid, pickFor: meal, pick: meal == null)),
    );
    if (recipe == null || !mounted) return;
    final values = await showTextFieldsDialog(
      context,
      title: recipe.name,
      confirmLabel: 'Einplanen',
      fields: const [DialogField('Portionen', initial: '1', required: true)],
    );
    final servings = double.tryParse((values?.first ?? '').trim().replaceAll(',', '.'));
    if (servings == null || servings <= 0 || !mounted) return;
    final target = meal ?? (recipe.meals.isEmpty ? Meal.lunch : recipe.meals.first);
    await runGuarded(context, () => _repo.plan(uid: _uid, recipe: recipe, date: day, meal: target, servings: servings));
    _load();
  }

  Future<void> _addFood(Meal meal) async {
    final day = _day;
    final planned = await showFoodPicker(
      context,
      user: widget.user,
      meal: meal,
      date: day,
      onPicked: (pick) => _repo
          .planFood(uid: _uid, food: pick.food, grams: pick.grams, date: day, meal: pick.meal, itemId: pick.fromPantry?.id)
          .then((_) {}),
    );
    if (planned && mounted) {
      showAppSnack(context, 'Eingeplant');
      _load();
    }
  }

  /// Eingeplantes Lebensmittel: als gegessen eintragen (bzw. zurücknehmen) oder Menge ändern.
  Future<void> _openFood(PlannedMeal p) async {
    final food = _foods[p.foodId];
    if (food == null) return showAppSnack(context, 'Das Lebensmittel „${p.name}“ gibt es nicht mehr.');
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(title: Text(p.name, style: Theme.of(ctx).textTheme.titleMedium), subtitle: Text(_foodLine(p))),
          if (!p.eaten)
            ListTile(
              leading: const Icon(Icons.check_circle_outline_rounded),
              title: const Text('Als gegessen eintragen'),
              onTap: () => Navigator.pop(ctx, 'eat'),
            )
          else
            ListTile(
              leading: const Icon(Icons.undo_rounded),
              title: const Text('Gegessen zurücknehmen'),
              onTap: () => Navigator.pop(ctx, 'uneat'),
            ),
          ListTile(leading: const Icon(Icons.scale_rounded), title: const Text('Menge ändern'), onTap: () => Navigator.pop(ctx, 'grams')),
        ]),
      ),
    );
    if (action == null || !mounted) return;
    await runGuarded(context, () async {
      switch (action) {
        case 'eat':
          await _repo.markFoodEaten(p, food);
        case 'uneat':
          await _repo.unmarkEaten(p);
        case 'grams':
          final grams = await askGrams(context, food, unit: p.meal.unit, initial: p.grams);
          if (grams != null) await _repo.update(p.copyWith(grams: grams));
      }
    });
    _load();
  }

  String _foodLine(PlannedMeal p) {
    final food = _foods[p.foodId];
    final grams = p.grams ?? 0;
    return [
      if (p.time != null) '${formatMinutes(p.minutes)} Uhr',
      '${grams == grams.roundToDouble() ? grams.toInt() : grams} ${p.meal.unit}',
      if (food != null) '${(food.per100.kcal * grams / 100).round()} kcal',
      if (food == null) 'Lebensmittel gelöscht',
    ].join(' · ');
  }

  Future<void> _addRecipe([Meal? meal]) async {
    final recipe = await Navigator.of(context).push<Recipe>(
      MaterialPageRoute(builder: (_) => RecipesScreen(userid: _uid, pickFor: meal, pick: meal == null)),
    );
    if (recipe == null || !mounted) return;
    await _openPlanner(recipe, presetMeal: meal);
  }

  Future<void> _openPlanner(Recipe recipe, {Meal? presetMeal, MealBatch? batch}) async {
    final saved = await Navigator.of(context).push<bool>(MaterialPageRoute(
      builder: (_) => PortionPlannerScreen(
        userid: _uid,
        recipe: recipe,
        initialDate: _day,
        presetMeal: presetMeal,
        batch: batch,
      ),
    ));
    if (saved == true) _load();
  }

  Future<void> _editBatch(MealBatch batch) async {
    final recipe = _recipeOf(batch.recipeKey, batch.recipeId);
    if (recipe == null) return showAppSnack(context, 'Das Rezept zu „${batch.name}“ wurde gelöscht.');
    await _openPlanner(recipe, batch: batch);
  }

  Future<void> _deleteBatch(MealBatch batch) {
    late String at;
    return deleteWithUndo(
      context,
      label: '${batch.name} (alle Portionen)',
      delete: () async => at = await _repo.deleteBatch(batch.id!),
      restore: () => _repo.restoreBatch(batch.id!, at),
      onChanged: _load,
    );
  }

  Future<void> _cook(MealBatch? batch, [Recipe? recipe]) async {
    final r = recipe ?? (batch == null ? null : _recipeOf(batch.recipeKey, batch.recipeId));
    if (r == null) return;
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => CookScreen(userid: _uid, recipe: r, batch: batch)),
    );
    if (saved == true && mounted) {
      showAppSnack(context, '„${r.name}“ als gekocht eingetragen – Vorrat aktualisiert');
      _load();
    }
  }

  /// „Gekocht“ ohne Plan: Rezept wählen und eintragen, was aus dem Vorrat genommen wurde.
  Future<void> _cookUnplanned() async {
    final recipe = await Navigator.of(context).push<Recipe>(
      MaterialPageRoute(builder: (_) => RecipesScreen(userid: _uid, pick: true)),
    );
    if (recipe != null && mounted) await _cook(null, recipe);
  }

  Future<void> _batchFromShopping(MealBatch batch) {
    late String at;
    return deleteWithUndo(
      context,
      label: 'Zutaten von ${batch.name} auf der Einkaufsliste',
      delete: () async => at = await _repo.removeBatchFromShopping(_uid, batch.id!),
      restore: () => _repo.restoreShopping(_uid, at),
    );
  }

  Future<void> _open(PlannedMeal p) async {
    await openPlannedMeal(context, _uid, p);
    _load();
  }

  Future<void> _remove(PlannedMeal p) {
    final batch = _batches.where((b) => b.id == p.batchId).firstOrNull;
    // Portionen eines Koch-Blocks gehören zusammen – gelöscht wird der ganze Block.
    if (batch != null) return _deleteBatch(batch);
    return deleteWithUndo(
      context,
      label: p.name,
      delete: () => _repo.remove(p.id!),
      restore: () => _repo.restore(p.id!),
      onChanged: _load,
    );
  }

  Future<void> _editDish(PlannedMeal p) async {
    if (p.isFood) return _openFood(p);
    final batch = _batches.where((b) => b.id == p.batchId).firstOrNull;
    if (batch != null) return _editBatch(batch);
    return _open(p);
  }

  Future<void> _browse() async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => RecipesScreen(userid: _uid)));
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final week = _week;
    return Scaffold(
      floatingActionButton: AppFab(label: 'Einplanen', heroTag: 'meal-plan-fab', onPressed: () => _add()),
      body: week == null
          ? Center(child: CircularProgressIndicator(color: c.accent))
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: pagePadding(context),
                children: [
                  _weekHeader(context),
                  const SizedBox(height: 8),
                  _dayStrip(context, week),
                  const SizedBox(height: 16),
                  for (final b in _batches.where((b) => (_unplanned[b.id] ?? 0) > 0)) _leftoverHint(context, b),
                  _dayTitle(context),
                  const SizedBox(height: 8),
                  for (final b in _batches.where((b) => b.cookDate == _day)) _cookCard(context, b),
                  for (final meal in plannedMeals) _slot(context, meal, week.where((p) => p.date == _day && p.meal == meal).toList()),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: _browse,
                    icon: const Icon(Icons.menu_book_rounded),
                    label: const Text('Rezepte'),
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: _cookUnplanned,
                    icon: const Icon(Icons.soup_kitchen_outlined),
                    label: const Text('Ohne Plan gekocht'),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _weekHeader(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final end = addDays(_weekStart, 6);
    final fmt = DateFormat('d.M.', 'de_DE');
    return Row(children: [
      IconButton(
        tooltip: 'Vorige Woche',
        onPressed: () => _select(addDays(_day, -7)),
        icon: const Icon(Icons.chevron_left_rounded),
      ),
      Expanded(
        child: GestureDetector(
          onTap: () => _select(_now()),
          child: Text('${fmt.format(_weekStart)} – ${fmt.format(end)}', textAlign: TextAlign.center, style: t.titleMedium),
        ),
      ),
      IconButton(
        tooltip: 'Nächste Woche',
        onPressed: () => _select(addDays(_day, 7)),
        icon: const Icon(Icons.chevron_right_rounded),
      ),
    ]);
  }

  Widget _dayStrip(BuildContext context, List<PlannedMeal> week) {
    final c = AppColors.of(context);
    final today = _dateOnly(_now());
    return Row(children: [
      for (final d in _days)
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: Material(
              color: d == _day ? c.accent : c.card,
              borderRadius: BorderRadius.circular(14),
              child: InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: () => _select(d),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  decoration: d == today && d != _day
                      ? BoxDecoration(borderRadius: BorderRadius.circular(14), border: Border.all(color: c.accentText))
                      : null,
                  child: Column(children: [
                    Text(DateFormat('E', 'de_DE').format(d).replaceAll('.', ''),
                        style: TextStyle(fontSize: 11, color: d == _day ? c.onAccent : c.muted)),
                    Text('${d.day}',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: d == _day ? c.onAccent : c.text)),
                    const SizedBox(height: 2),
                    Text(
                      '•' * week.where((p) => p.date == d).length.clamp(0, 4),
                      style: TextStyle(fontSize: 10, height: 1, color: d == _day ? c.onAccent : c.accentText),
                    ),
                  ]),
                ),
              ),
            ),
          ),
        ),
    ]);
  }

  Widget _dayTitle(BuildContext context) {
    final today = _dateOnly(_now());
    final diff = daysBetween(today, _day);
    final prefix = switch (diff) { 0 => 'Heute, ', 1 => 'Morgen, ', -1 => 'Gestern, ', _ => '' };
    return GroupLabel('$prefix${DateFormat('EEEE d. MMMM', 'de_DE').format(_day)}');
  }

  Widget _slot(BuildContext context, Meal meal, List<PlannedMeal> dishes) {
    final c = AppColors.of(context);
    final t = Theme.of(context).textTheme;
    final time = dishes.isEmpty ? defaultMealMinutes(meal) : dishes.first.minutes;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: AppCard(
        padding: const EdgeInsets.fromLTRB(14, 10, 6, 4),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Icon(mealIcon(meal), size: 20, color: c.accentText),
            const SizedBox(width: 8),
            Expanded(child: Text(meal.label, style: t.titleMedium)),
            Text(formatMinutes(time), style: t.labelMedium),
            IconButton(
              tooltip: '${meal.label}: Gericht hinzufügen',
              visualDensity: VisualDensity.compact,
              onPressed: () => _add(meal),
              icon: const Icon(Icons.add_circle_outline_rounded),
            ),
          ]),
          if (dishes.isEmpty)
            Padding(
              padding: const EdgeInsets.only(left: 28, bottom: 8),
              child: Text('Noch nichts geplant', style: t.bodySmall?.copyWith(color: c.muted)),
            ),
          for (final p in dishes) _dish(context, p),
        ]),
      ),
    );
  }

  Widget _dish(BuildContext context, PlannedMeal p) {
    final c = AppColors.of(context);
    final t = Theme.of(context).textTheme;
    if (p.isFood) {
      return SwipeTile(
        id: 'meal-${p.id}',
        onEdit: () => _openFood(p),
        onDelete: () => _remove(p),
        child: ListTile(
          contentPadding: const EdgeInsets.only(left: 28, right: 8),
          dense: true,
          leading: Icon(Icons.egg_alt_outlined, size: 18, color: c.muted),
          minLeadingWidth: 18,
          title: Text(p.name, style: t.bodyLarge?.copyWith(decoration: p.eaten ? TextDecoration.lineThrough : null)),
          subtitle: Text(_foodLine(p), style: t.labelMedium),
          trailing: p.eaten ? Icon(Icons.check_circle_rounded, color: c.positive) : const Icon(Icons.chevron_right_rounded),
          onTap: () => _openFood(p),
        ),
      );
    }
    final recipe = _recipes[_recipeId(p.recipeKey, p.recipeId)];
    return SwipeTile(
      id: 'meal-${p.id}',
      onEdit: () => _editDish(p),
      onDelete: () => _remove(p),
      child: ListTile(
        contentPadding: const EdgeInsets.only(left: 28, right: 8),
        dense: true,
        title: Text(p.name, style: t.bodyLarge?.copyWith(decoration: p.eaten ? TextDecoration.lineThrough : null)),
        subtitle: Text(
          [
            if (p.time != null) '${formatMinutes(p.minutes)} Uhr',
            portionsLabel(p.servings),
            if (recipe != null) '${recipe.minutes} min',
            if (recipe != null) '${(recipe.perServing.kcal * p.servings).round()} kcal',
            if (recipe == null) 'Rezept gelöscht',
          ].join(' · '),
          style: t.labelMedium,
        ),
        trailing: p.eaten ? Icon(Icons.check_circle_rounded, color: c.positive) : const Icon(Icons.chevron_right_rounded),
        onTap: () => _open(p),
      ),
    );
  }

  /// Am Kochtag: was gekocht wird, „Gekocht“ eintragen, Zutaten wieder von der Liste nehmen.
  Widget _cookCard(BuildContext context, MealBatch b) {
    final c = AppColors.of(context);
    final t = Theme.of(context).textTheme;
    final recipe = _recipeOf(b.recipeKey, b.recipeId);
    final servings = recipe == null ? null : b.servingsOf(recipe);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: SwipeTile(
        id: 'batch-${b.id}',
        startAction: SwipeAction(label: 'Einkauf weg', icon: Icons.remove_shopping_cart_outlined, onPressed: () => _batchFromShopping(b)),
        onEdit: () => _editBatch(b),
        onDelete: () => _deleteBatch(b),
        child: AppCard(
          color: c.accent.withValues(alpha: 0.10),
          padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
          child: Row(children: [
            Icon(b.cooked ? Icons.check_circle_rounded : Icons.soup_kitchen_rounded, color: b.cooked ? c.positive : c.accentText),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Kochen: ${b.name}', style: t.titleSmall),
                Text(
                  [
                    if (b.cookTimeLabel != null) '${b.cookTimeLabel} Uhr',
                    if (servings != null) portionsLabel(servings),
                    if ((_reserved[b.id] ?? 0) > 0) '${_reserved[b.id]} aus dem Vorrat',
                    if (b.cooked) 'gekocht',
                  ].join(' · '),
                  style: t.labelMedium,
                ),
              ]),
            ),
            if (!b.cooked)
              FilledButton.tonal(onPressed: () => _cook(b), child: const Text('Gekocht')),
          ]),
        ),
      ),
    );
  }

  /// Hinweis: Von einem Koch-Block sind noch Portionen keiner Mahlzeit zugeordnet.
  Widget _leftoverHint(BuildContext context, MealBatch b) {
    final c = AppColors.of(context);
    final t = Theme.of(context).textTheme;
    final left = _unplanned[b.id] ?? 0;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: AppCard(
        color: c.streak.withValues(alpha: 0.12),
        padding: const EdgeInsets.fromLTRB(14, 8, 6, 8),
        child: Row(children: [
          Icon(Icons.info_outline_rounded, color: c.streak),
          const SizedBox(width: 10),
          Expanded(
            child: Text('${b.name}: ${portionsLabel(left)} noch nicht eingeplant',
                style: t.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
          ),
          TextButton(onPressed: () => _editBatch(b), child: const Text('Verteilen')),
        ]),
      ),
    );
  }
}
