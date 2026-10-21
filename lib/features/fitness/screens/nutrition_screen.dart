import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import 'package:frontend/core/models/app_exceptions.dart';
import 'package:frontend/core/ui/app_actions.dart';
import 'package:frontend/core/ui/app_ui.dart';
import 'package:frontend/core/ui/dialogs.dart';
import 'package:frontend/core/ui/theme.dart';
import 'package:frontend/features/auth/models/user.dart';
import 'package:frontend/features/fitness/models/nutrition.dart';
import 'package:frontend/features/fitness/repositories/nutrition_repository.dart';
import 'package:frontend/features/fitness/screens/food_editor_screen.dart';
import 'package:frontend/features/fitness/services/food_photo_scanner.dart';
import 'package:frontend/features/fitness/services/meal_photo_ai.dart';
import 'package:frontend/features/fitness/services/nutrition_label_parser.dart';
import 'package:frontend/features/profile/screens/profile_screen.dart';
import 'package:frontend/features/fitness/widgets/food_actions.dart';
import 'package:frontend/features/meals/models/meal_plan.dart';
import 'package:frontend/features/meals/screens/recipes_screen.dart';
import 'package:frontend/features/inventory/models/inventory_item.dart';
import 'package:frontend/features/inventory/repositories/inventory_repository.dart';

/// Ernährungsprotokoll eines Tages: kcal-Ring, Makros gegen Tagesziele, Mahlzeiten.
class NutritionScreen extends StatefulWidget {
  final UserModel user;
  const NutritionScreen({super.key, required this.user});

  @override
  State<NutritionScreen> createState() => _NutritionScreenState();
}

class _NutritionScreenState extends State<NutritionScreen> {
  late final NutritionRepository _repo = context.read<NutritionRepository>();
  DateTime _date = _today();
  NutritionDay? _day;

  static DateTime _today() {
    final n = DateTime.now();
    return DateTime(n.year, n.month, n.day);
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final day = await _repo.getDay(widget.user.uid, _date);
    if (mounted) setState(() => _day = day);
  }

  void _shiftDay(int delta) {
    setState(() => _date = DateTime(_date.year, _date.month, _date.day + delta));
    _load();
  }

  Future<void> _editGoals() async {
    final g = _day!.goals.target;
    String n(double v) => v.round().toString();
    final values = await showTextFieldsDialog(context, title: 'Tagesziele', fields: [
      DialogField('Kalorien (kcal)', initial: n(g.kcal), required: true),
      DialogField('Eiweiß (g)', initial: n(g.protein), required: true),
      DialogField('Kohlenhydrate (g)', initial: n(g.carbs), required: true),
      DialogField('Fett (g)', initial: n(g.fat), required: true),
      DialogField('Trinken (ml)', initial: n(_day!.goals.waterMl), required: true),
    ]);
    if (values == null) return;
    double p(String? s) => double.tryParse(s!.replaceAll(',', '.')) ?? 0;
    await _repo.setGoals(widget.user.uid, Macros(kcal: p(values[0]), protein: p(values[1]), carbs: p(values[2]), fat: p(values[3])),
        waterMl: p(values[4]));
    _load();
  }

  Future<void> _add(Meal meal) async {
    if (await showFoodPicker(context, user: widget.user, meal: meal, date: _date)) _load();
  }

  Future<void> _deleteEntry(MealEntry e) => deleteWithUndo(
        context,
        label: e.name,
        delete: () => _repo.deleteEntry(e.id!),
        restore: () => _repo.restoreEntry(e.id!),
        onChanged: _load,
      );

  Future<void> _editEntry(MealEntry e) async {
    final result = await showEditorSheet<(double, Meal)>(context, (_) => _EntrySheet(entry: e));
    if (result == null || !mounted) return;
    final portions = e.portions;
    await runGuarded(
      context,
      () => portions == null
          ? _repo.updateEntry(e, grams: result.$1, meal: result.$2)
          : _repo.updateEntry(e, grams: e.grams * result.$1 / portions, meal: result.$2, portions: result.$1),
    );
    _load();
  }

  /// Mahlzeit passend zur Uhrzeit (für den +-Button).
  static Meal _mealNow() {
    final h = DateTime.now().hour;
    if (h < 10) return Meal.breakfast;
    if (h < 14) return Meal.lunch;
    if (h < 17) return Meal.snack;
    return Meal.dinner;
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final day = _day;
    return Scaffold(
      floatingActionButton: AppFab(label: 'Lebensmittel', heroTag: 'nutrition-fab', onPressed: () => _add(_mealNow())),
      body: day == null
          ? Center(child: CircularProgressIndicator(color: c.accent))
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: pagePadding(context),
                children: [
                  _dayHeader(context),
                  const SizedBox(height: 12),
                  _summary(context, day),
                  const SizedBox(height: 12),
                  _water(context, day),
                  const SizedBox(height: 20),
                  for (final meal in Meal.values) ...[
                    _mealSection(context, day, meal),
                    const SizedBox(height: 16),
                  ],
                ],
              ),
            ),
    );
  }

  Widget _dayHeader(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final isToday = _date == _today();
    final label = isToday ? 'Heute' : DateFormat('EEEE, d. MMMM', 'de_DE').format(_date);
    return Row(children: [
      IconButton(tooltip: 'Vorheriger Tag', icon: const Icon(Icons.chevron_left_rounded), onPressed: () => _shiftDay(-1)),
      Expanded(child: Text(label, textAlign: TextAlign.center, style: t.titleLarge)),
      IconButton(
        tooltip: 'Nächster Tag',
        icon: const Icon(Icons.chevron_right_rounded),
        onPressed: isToday ? null : () => _shiftDay(1),
      ),
      IconButton(tooltip: 'Tagesziele', icon: const Icon(Icons.tune_rounded), onPressed: _editGoals),
    ]);
  }

  Widget _summary(BuildContext context, NutritionDay day) {
    final c = AppColors.of(context);
    final t = Theme.of(context).textTheme;
    final total = day.total;
    final goal = day.goals.target;
    final rest = goal.kcal - total.kcal;
    Widget macro(String label, double value, double target, Color color) => Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(child: Text(label, style: t.labelMedium)),
              Text('${value.round()} / ${target.round()} g', style: t.labelMedium),
            ]),
            const SizedBox(height: 4),
            AppProgressBar(value: target <= 0 ? 0 : value / target, color: value > target * 1.05 ? c.negative : color),
          ]),
        );
    return AppCard(
      padding: const EdgeInsets.all(18),
      child: Row(children: [
        ScoreRing(
          progress: goal.kcal <= 0 ? 0 : total.kcal / goal.kcal,
          color: rest < 0 ? c.negative : c.accent,
          track: c.cardAlt,
          size: 104,
          child: Padding(
            padding: const EdgeInsets.all(14),
            // Bei großer Schrift verkleinern statt überlaufen
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Text('${total.kcal.round()}', style: t.headlineMedium),
                Text('von ${goal.kcal.round()} kcal', style: t.labelSmall),
              ]),
            ),
          ),
        ),
        const SizedBox(width: 18),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(rest >= 0 ? 'Noch ${rest.round()} kcal' : '${(-rest).round()} kcal über dem Ziel',
                style: t.titleSmall?.copyWith(color: rest >= 0 ? c.text : c.negative)),
            const SizedBox(height: 10),
            macro('Eiweiß', total.protein, goal.protein, c.accent),
            macro('Kohlenhydrate', total.carbs, goal.carbs, c.streak),
            macro('Fett', total.fat, goal.fat, c.event),
          ]),
        ),
      ]),
    );
  }

  Future<void> _drink(double ml) async {
    await _repo.addWater(uid: widget.user.uid, ml: ml, date: _date);
    _load();
  }

  Future<void> _drinkCustom() async {
    final values = await showTextFieldsDialog(context, title: 'Wasser trinken', confirmLabel: 'Eintragen', fields: [
      const DialogField('Menge in ml', initial: '330', required: true),
    ]);
    final ml = double.tryParse((values?.first ?? '').replaceAll(',', '.'));
    if (ml != null && ml > 0) await _drink(ml);
  }

  Widget _water(BuildContext context, NutritionDay day) {
    final c = AppColors.of(context);
    final t = Theme.of(context).textTheme;
    final drank = day.drankMl;
    final goal = day.goals.waterMl;
    String l(double ml) => ml >= 1000 ? '${(ml / 1000).toStringAsFixed(1).replaceAll('.', ',')} l' : '${ml.round()} ml';
    return AppCard(
      padding: const EdgeInsets.all(14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Icon(Icons.water_drop_rounded, color: c.event),
          const SizedBox(width: 8),
          Expanded(child: Text('Getrunken', style: t.titleSmall)),
          Text('${l(drank)} / ${l(goal)}', style: t.titleSmall),
        ]),
        const SizedBox(height: 8),
        AppProgressBar(value: goal <= 0 ? 0 : drank / goal, color: c.event),
        const SizedBox(height: 10),
        Wrap(spacing: 8, runSpacing: 8, children: [
          ActionChip(avatar: const Icon(Icons.local_drink_outlined, size: 18), label: const Text('+ 250 ml'), onPressed: () => _drink(250)),
          ActionChip(avatar: const Icon(Icons.water_rounded, size: 18), label: const Text('+ 500 ml'), onPressed: () => _drink(500)),
          ActionChip(avatar: const Icon(Icons.edit_rounded, size: 18), label: const Text('Menge'), onPressed: _drinkCustom),
        ]),
      ]),
    );
  }

  Widget _mealSection(BuildContext context, NutritionDay day, Meal meal) {
    final t = Theme.of(context).textTheme;
    final entries = day.entriesFor(meal);
    final kcal = day.totalFor(meal).kcal.round();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      SectionTitle(meal.label, trailing: entries.isEmpty ? null : '$kcal kcal'),
      AppCard(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        child: Column(children: [
          for (final e in entries)
            SwipeTile(
              id: 'entry-${e.id}',
              onEdit: () => _editEntry(e),
              onDelete: () => _deleteEntry(e),
              child: ListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                title: Text(e.name, style: t.bodyLarge),
                subtitle: Text(
                  e.meal == Meal.drinks
                      ? '${e.grams.round()} ml'
                      : '${e.portions != null ? portionsLabel(e.portions!) : '${e.grams.round()} g'} · ${e.macros.protein.round()} g Eiweiß',
                  style: t.labelMedium,
                ),
                trailing: Text('${e.macros.kcal.round()} kcal', style: t.titleSmall),
                onTap: () => _editEntry(e),
              ),
            ),
          TextButton.icon(
            onPressed: () => _add(meal),
            icon: const Icon(Icons.add_rounded, size: 18),
            label: Text('${meal.label} hinzufügen'),
          ),
        ]),
      ),
    ]);
  }
}

/// Lebensmittel für eine Mahlzeit auswählen: Suche, Barcode, neues Lebensmittel oder aus dem Vorrat.
/// Gewähltes Lebensmittel mit Menge und Mahlzeit (und ggf. Vorratsartikel).
class FoodPick {
  final Food food;
  final double grams;
  final Meal meal;
  final InventoryItem? fromPantry;

  /// Bei Gerichten: Anzahl Portionen (die [grams] sind dann Portionen × Portionsgröße).
  final double? portions;
  const FoodPick(this.food, this.grams, this.meal, this.fromPantry, [this.portions]);
}

/// Lebensmittel-Auswahl für eine Mahlzeit: Suche, Foto (KI/Nährwerttabelle), Barcode, neues
/// Lebensmittel und Vorrat. Ohne [onPicked] trägt das Sheet direkt ins Ernährungsprotokoll ein,
/// mit [onPicked] entscheidet der Aufrufer (z. B. der Essensplan plant es nur ein).
/// Schließt mit `true`, wenn etwas gewählt wurde.
Future<bool> showFoodPicker(BuildContext context,
    {required UserModel user, required Meal meal, required DateTime date, Future<void> Function(FoodPick pick)? onPicked}) async {
  final added = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    builder: (_) => FractionallySizedBox(
      heightFactor: 0.85,
      child: FoodPickerSheet(user: user, meal: meal, date: date, onPicked: onPicked),
    ),
  );
  return added == true;
}

class FoodPickerSheet extends StatefulWidget {
  final UserModel user;
  final Meal meal;
  final DateTime date;
  final Future<void> Function(FoodPick pick)? onPicked;
  const FoodPickerSheet({super.key, required this.user, required this.meal, required this.date, this.onPicked});

  @override
  State<FoodPickerSheet> createState() => FoodPickerSheetState();
}

class FoodPickerSheetState extends State<FoodPickerSheet> {
  late final NutritionRepository _repo = context.read<NutritionRepository>();
  late final InventoryRepository _inventory = context.read<InventoryRepository>();
  final _search = TextEditingController();
  List<Food> _foods = [];
  List<InventoryItem> _pantry = [];
  bool _showPantry = false;
  late Meal _meal = widget.meal;

  int get _uid => widget.user.uid;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  /// Zählt Suchen mit – eine langsamere ältere Antwort überschreibt nicht das neuere Ergebnis.
  int _loadId = 0;

  Future<void> _load() async {
    final loadId = ++_loadId;
    // Beide vor dem ersten await holen: wird das Sheet währenddessen geschlossen, gibt es keinen context mehr.
    final repo = _repo, inventory = _inventory;
    await repo.ensureStandardFoods(_uid);
    final foods = await repo.searchFoods(_uid, search: _search.text);
    final pantry = (await inventory.getItems(_uid, kinds: {InventoryKind.food, InventoryKind.drink}))
        .where((i) => i.foodId != null)
        .toList();
    if (mounted && loadId == _loadId) {
      setState(() {
        _foods = foods;
        _pantry = pantry;
      });
    }
  }

  Future<void> _addFood(Food food, {InventoryItem? fromPantry}) async {
    final navigator = Navigator.of(context);
    double? portions;
    final double? grams;
    if (food.isDish) {
      portions = await askPortions(context, food.name);
      grams = portions == null ? null : portions * food.portionGrams;
    } else {
      grams = await askGrams(context, food, unit: _meal.unit);
    }
    if (grams == null) return;
    if (widget.onPicked != null) {
      await widget.onPicked!(FoodPick(food, grams, _meal, fromPantry, portions));
    } else if (fromPantry != null) {
      await _repo.eatFromPantry(uid: _uid, item: fromPantry, food: food, grams: grams, meal: _meal, date: widget.date);
    } else {
      await _repo.addEntry(uid: _uid, food: food, grams: grams, meal: _meal, date: widget.date, portions: portions);
    }
    if (mounted) navigator.pop(true);
  }

  /// „Gericht“: eigenes Gericht anlegen (wird gemerkt) oder ein Rezept in Portionen eintragen.
  Future<void> _dish() async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            leading: const Icon(Icons.restaurant_menu_rounded),
            title: const Text('Eigenes Gericht'),
            subtitle: const Text('z. B. Pizza vom Italiener – Nährwerte je Portion'),
            onTap: () => Navigator.pop(ctx, 'own'),
          ),
          if (widget.onPicked == null)
            ListTile(
              leading: const Icon(Icons.menu_book_rounded),
              title: const Text('Aus Rezept'),
              subtitle: const Text('Eigene und mitgelieferte Rezepte in Portionen'),
              onTap: () => Navigator.pop(ctx, 'recipe'),
            ),
        ]),
      ),
    );
    if (!mounted || choice == null) return;
    if (choice == 'own') {
      await _ownDish();
    } else {
      await _fromRecipe();
    }
  }

  Future<void> _ownDish() async {
    final navigator = Navigator.of(context);
    final draft = await showEditorSheet<_DishDraft>(context, (_) => const _DishSheet());
    if (draft == null || !mounted) return;
    final food = await runGuarded(
      context,
      () => _repo.saveDish(uid: _uid, name: draft.name, perPortion: draft.perPortion, gramsPerPortion: draft.gramsPerPortion),
    );
    if (food == null || !mounted) return;
    final grams = draft.portions * food.portionGrams;
    if (widget.onPicked != null) {
      await widget.onPicked!(FoodPick(food, grams, _meal, null, draft.portions));
    } else {
      await _repo.addEntry(uid: _uid, food: food, grams: grams, meal: _meal, date: widget.date, portions: draft.portions);
    }
    if (mounted) navigator.pop(true);
  }

  Future<void> _fromRecipe() async {
    final navigator = Navigator.of(context);
    final recipe = await navigator.push<Recipe>(MaterialPageRoute(builder: (_) => RecipesScreen(userid: _uid, pick: true)));
    if (recipe == null || !mounted) return;
    final portions = await askPortions(context, recipe.name);
    if (portions == null || !mounted) return;
    await runGuarded(
      context,
      () => _repo.addDishEntry(
        uid: _uid,
        name: recipe.name,
        perPortion: recipe.perServing,
        gramsPerPortion: recipe.gramsPerServing,
        portions: portions,
        meal: _meal,
        date: widget.date,
      ),
    );
    if (mounted) navigator.pop(true);
  }

  Future<void> _scan() async {
    final food = await scanFoodBarcode(context, _uid);
    if (food != null && mounted) await _addFood(food);
  }

  /// Foto: Gericht per KI schätzen oder Nährwerttabelle lesen, prüfen, dann eintragen.
  Future<void> _photo() async {
    final choice = await showModalBottomSheet<(bool, bool)>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            leading: const Icon(Icons.restaurant_rounded),
            title: const Text('Gericht fotografieren'),
            subtitle: const Text('KI schätzt Menge und Nährwerte (Internet)'),
            onTap: () => Navigator.pop(ctx, (true, false)),
          ),
          ListTile(
            leading: const Icon(Icons.table_chart_outlined),
            title: const Text('Nährwerttabelle fotografieren'),
            subtitle: const Text('Liest die Werte von der Verpackung (offline)'),
            onTap: () => Navigator.pop(ctx, (false, false)),
          ),
          ListTile(
            leading: const Icon(Icons.photo_library_outlined),
            title: const Text('Gericht aus der Galerie'),
            onTap: () => Navigator.pop(ctx, (true, true)),
          ),
          ListTile(
            leading: const Icon(Icons.photo_library_outlined),
            title: const Text('Nährwerttabelle aus der Galerie'),
            onTap: () => Navigator.pop(ctx, (false, true)),
          ),
        ]),
      ),
    );
    if (choice == null || !mounted) return;
    final (dish, fromGallery) = choice;
    final scanner = context.read<FoodPhotoScanner>();
    final ai = context.read<MealPhotoAi>();
    final keys = context.read<AiKeyStore>();
    if (dish && await keys.read() == null) {
      if (mounted) await _noKeyHint();
      return;
    }
    if (!mounted) return;
    final photo = await runGuarded(context, () => scanner.pick(fromGallery: fromGallery));
    if (photo == null || !mounted) return;
    try {
      setState(() => _analyzing = true);
      final (Food? draft, String hint) = dish ? await _fromDish(ai, photo) : await _fromLabel(scanner, photo);
      if (!mounted || !_analyzing) return; // abgebrochen
      setState(() => _analyzing = false);
      if (draft == null) {
        if (await _photoProblem(hint, actionLabel: 'Manuell eingeben') && mounted) await _newFood();
        return;
      }
      final food = await Navigator.push<Food>(
        context,
        MaterialPageRoute(builder: (_) => FoodEditorScreen(userid: _uid, draft: draft, photo: photo.bytes, photoHint: hint)),
      );
      if (food != null && mounted) await _addFood(food);
    } on UserFacingException catch (e) {
      if (mounted) {
        setState(() => _analyzing = false);
        await _photoProblem(e.message);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _analyzing = false);
        await _photoProblem('Foto konnte nicht ausgewertet werden: ${errorText(e)}');
      }
    } finally {
      await scanner.discard(photo);
    }
  }

  bool _analyzing = false;

  Future<(Food?, String)> _fromLabel(FoodPhotoScanner scanner, FoodPhoto photo) async {
    final values = parseNutritionLabel(await scanner.readLines(photo));
    if (values == null) return (null, 'Auf dem Foto wurde keine Nährwerttabelle erkannt.');
    final missing = [
      if (values.kcal == null) 'Kalorien',
      if (values.protein == null) 'Eiweiß',
      if (values.carbs == null) 'Kohlenhydrate',
      if (values.fat == null) 'Fett',
    ];
    final draft = Food(
      userid: _uid,
      name: _search.text.trim(),
      per100: Macros(kcal: values.kcal ?? 0, protein: values.protein ?? 0, carbs: values.carbs ?? 0, fat: values.fat ?? 0),
      servingGrams: values.servingGrams,
    );
    return (
      draft,
      missing.isEmpty
          ? 'Werte pro 100 g von der Nährwerttabelle – bitte Namen ergänzen und prüfen.'
          : 'Nicht erkannt: ${missing.join(', ')} – bitte ergänzen.',
    );
  }

  Future<(Food?, String)> _fromDish(MealPhotoAi ai, FoodPhoto photo) async {
    final e = await ai.estimate(photo.bytes);
    if (e.grams <= 0 || e.kcal <= 0) return (null, 'Auf dem Foto wurde kein Essen erkannt.');
    final per100 = 100 / e.grams;
    final draft = Food(
      userid: _uid,
      name: e.name,
      per100: Macros(kcal: e.kcal * per100, protein: e.protein * per100, carbs: e.carbs * per100, fat: e.fat * per100),
      servingGrams: e.grams.roundToDouble(),
      isDish: true, // eingetragen wird in Portionen (eine Portion = die geschätzte Menge)
    );
    final fmt = NumberFormat('#,##0', 'de_DE');
    return (
      draft,
      [
        'Geschätzt aus dem Foto – bitte prüfen: etwa ${fmt.format(e.grams)} g, ${fmt.format(e.kcal)} kcal.',
        if (e.components.isNotEmpty) 'Erkannt: ${e.components.join(', ')}.',
        if (e.note != null) e.note!,
      ].join(' '),
    );
  }

  Future<void> _noKeyHint() async {
    final go = await _photoProblem('Für die KI-Schätzung brauchst du einen API-Schlüssel – im Profil unter „KI“ eintragen.',
        actionLabel: 'Zum Profil');
    if (go && mounted) await Navigator.of(context).push(MaterialPageRoute(builder: (_) => ProfilePage(user: widget.user)));
  }

  /// Hinweis als Dialog – eine Snackbar läge hinter diesem Sheet und wäre verdeckt.
  /// `true`, wenn [actionLabel] gewählt wurde.
  Future<bool> _photoProblem(String message, {String? actionLabel}) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Foto'),
        content: Text(message),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Schließen')),
          if (actionLabel != null) FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(actionLabel)),
        ],
      ),
    );
    return result == true;
  }

  Future<void> _newFood() async {
    final food = await Navigator.push<Food>(
      context,
      MaterialPageRoute(builder: (_) => FoodEditorScreen(userid: _uid, draft: Food(userid: _uid, name: _search.text.trim()))),
    );
    if (food != null && mounted) await _addFood(food);
  }

  Future<void> _fromPantry(InventoryItem item) async {
    final food = await _repo.getFood(item.foodId!);
    if (food != null && mounted) await _addFood(food, fromPantry: item);
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
          child: Text(widget.onPicked == null ? '${_meal.label} hinzufügen' : '${_meal.label} einplanen', style: t.titleLarge),
        ),
        if (_analyzing)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: AppCard(
              padding: const EdgeInsets.fromLTRB(14, 8, 6, 8),
              child: Row(children: [
                const SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2)),
                const SizedBox(width: 12),
                const Expanded(child: Text('Foto wird ausgewertet …')),
                TextButton(onPressed: () => setState(() => _analyzing = false), child: const Text('Abbrechen')),
              ]),
            ),
          ),
        SizedBox(
          height: 44,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            children: [
              for (final m in Meal.values) ...[
                AppChip(label: m.label, selected: m == _meal, onTap: () => setState(() => _meal = m)),
                const SizedBox(width: 8),
              ],
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: TextField(
            controller: _search,
            onChanged: (_) => _load(),
            decoration: const InputDecoration(hintText: 'Lebensmittel suchen', prefixIcon: Icon(Icons.search_rounded)),
          ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 44,
          child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 20), children: [
            ActionChip(avatar: const Icon(Icons.photo_camera_outlined, size: 18), label: const Text('Foto'), onPressed: _analyzing ? null : _photo),
            const SizedBox(width: 8),
            ActionChip(avatar: const Icon(Icons.restaurant_menu_rounded, size: 18), label: const Text('Gericht'), onPressed: _dish),
            const SizedBox(width: 8),
            ActionChip(avatar: const Icon(Icons.qr_code_scanner_rounded, size: 18), label: const Text('Barcode'), onPressed: _scan),
            const SizedBox(width: 8),
            ActionChip(avatar: const Icon(Icons.add_rounded, size: 18), label: const Text('Neues Lebensmittel'), onPressed: _newFood),
            const SizedBox(width: 8),
            FilterChip(
              avatar: const Icon(Icons.kitchen_rounded, size: 18),
              label: Text('Aus Vorrat (${_pantry.length})'),
              selected: _showPantry,
              onSelected: (v) => setState(() => _showPantry = v),
            ),
          ]),
        ),
        const Divider(height: 16),
        Expanded(
          child: _showPantry
              ? (_pantry.isEmpty
                  ? _hint('Im Vorrat ist nichts mit Nährwerten. Per Barcode angelegte Vorräte erscheinen hier.')
                  : ListView(children: [
                      for (final i in _pantry)
                        ListTile(
                          leading: const Icon(Icons.kitchen_rounded),
                          title: Text(i.name),
                          subtitle: Text('Vorrat: ${i.quantity == i.quantity.roundToDouble() ? i.quantity.toInt() : i.quantity} ${i.unit ?? ''}'),
                          onTap: () => _fromPantry(i),
                        ),
                    ]))
              : (_foods.isEmpty
                  ? _hint(_search.text.isEmpty
                      ? 'Noch keine Lebensmittel. Scanne einen Barcode oder lege eins an.'
                      : 'Nichts gefunden – als neues Lebensmittel anlegen?')
                  : ListView(children: [
                      for (final f in _foods)
                        ListTile(
                          leading: f.isDish ? const Icon(Icons.restaurant_menu_rounded) : null,
                          title: Text(f.name),
                          subtitle: Text(foodSubtitle(f)),
                          trailing: const Icon(Icons.add_circle_outline_rounded),
                          onTap: () => _addFood(f),
                        ),
                    ])),
        ),
      ]),
    );
  }

  Widget _hint(String text) => Padding(
        padding: const EdgeInsets.all(24),
        child: Text(text, textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodySmall),
      );
}

/// Menge und Mahlzeit eines Eintrags ändern.
class _EntrySheet extends StatefulWidget {
  final MealEntry entry;
  const _EntrySheet({required this.entry});

  @override
  State<_EntrySheet> createState() => _EntrySheetState();
}

class _EntrySheetState extends State<_EntrySheet> {
  final _formKey = GlobalKey<FormState>();
  late final _grams = TextEditingController(text: _initial(widget.entry));

  static String _initial(MealEntry e) {
    final p = e.portions;
    if (p == null) return e.grams.round().toString();
    return p == p.roundToDouble() ? '${p.toInt()}' : '$p'.replaceAll('.', ',');
  }
  late Meal _meal = widget.entry.meal;

  @override
  void dispose() {
    _grams.dispose();
    super.dispose();
  }

  void _save() {
    if (!_formKey.currentState!.validate()) return;
    Navigator.of(context).pop((double.parse(_grams.text.trim().replaceAll(',', '.')), _meal));
  }

  @override
  Widget build(BuildContext context) {
    return EditorSheet(
      formKey: _formKey,
      title: widget.entry.name,
      onSave: _save,
      children: [
        TextFormField(
          controller: _grams,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(labelText: widget.entry.portions != null ? 'Portionen' : 'Menge (${_meal.unit})'),
          validator: (v) {
            final value = double.tryParse((v ?? '').trim().replaceAll(',', '.'));
            return value == null || value <= 0 ? 'Bitte eine Menge eingeben' : null;
          },
          onFieldSubmitted: (_) => _save(),
        ),
        const SizedBox(height: 12),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final m in Meal.values) AppChip(label: m.label, selected: m == _meal, onTap: () => setState(() => _meal = m)),
        ]),
      ],
    );
  }
}

/// Eingaben eines eigenen Gerichts.
class _DishDraft {
  final String name;
  final Macros perPortion;
  final double? gramsPerPortion;
  final double portions;
  const _DishDraft(this.name, this.perPortion, this.gramsPerPortion, this.portions);
}

/// Eigenes Gericht: Name, Nährwerte je Portion (kcal Pflicht), optional Gramm, und wie viele Portionen.
class _DishSheet extends StatefulWidget {
  const _DishSheet();

  @override
  State<_DishSheet> createState() => _DishSheetState();
}

class _DishSheetState extends State<_DishSheet> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _kcal = TextEditingController();
  final _protein = TextEditingController();
  final _carbs = TextEditingController();
  final _fat = TextEditingController();
  final _grams = TextEditingController();
  final _portions = TextEditingController(text: '1');

  @override
  void dispose() {
    for (final c in [_name, _kcal, _protein, _carbs, _fat, _grams, _portions]) {
      c.dispose();
    }
    super.dispose();
  }

  static double? _num(String s) => double.tryParse(s.trim().replaceAll(',', '.'));

  void _save() {
    if (!_formKey.currentState!.validate()) return;
    Navigator.of(context).pop(_DishDraft(
      _name.text.trim(),
      Macros(kcal: _num(_kcal.text)!, protein: _num(_protein.text) ?? 0, carbs: _num(_carbs.text) ?? 0, fat: _num(_fat.text) ?? 0),
      _num(_grams.text),
      _num(_portions.text)!,
    ));
  }

  Widget _field(TextEditingController c, String label, {bool required = false, bool positive = false}) => TextFormField(
        controller: c,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: InputDecoration(labelText: label),
        validator: (v) {
          final text = (v ?? '').trim();
          if (text.isEmpty) return required ? 'Bitte eingeben' : null;
          final n = _num(text);
          if (n == null || n < 0 || (positive && n == 0)) return 'Bitte eine Zahl eingeben';
          return null;
        },
      );

  @override
  Widget build(BuildContext context) => EditorSheet(
        formKey: _formKey,
        title: 'Neues Gericht',
        saveLabel: 'Eintragen',
        onSave: _save,
        children: [
          TextFormField(
            controller: _name,
            autofocus: true,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(labelText: 'Name', hintText: 'z. B. Pizza vom Italiener'),
            validator: (v) => (v ?? '').trim().isEmpty ? 'Wie heißt das Gericht?' : null,
          ),
          const SizedBox(height: 12),
          _field(_kcal, 'kcal pro Portion', required: true, positive: true),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(child: _field(_protein, 'Eiweiß (g)')),
            const SizedBox(width: 8),
            Expanded(child: _field(_carbs, 'KH (g)')),
            const SizedBox(width: 8),
            Expanded(child: _field(_fat, 'Fett (g)')),
          ]),
          const SizedBox(height: 12),
          _field(_grams, 'Gramm pro Portion (optional)', positive: true),
          const SizedBox(height: 12),
          _field(_portions, 'Portionen', required: true, positive: true),
          const SizedBox(height: 4),
          Text('Das Gericht wird gemerkt – beim nächsten Mal findest du es in der Suche.',
              style: Theme.of(context).textTheme.bodySmall),
        ],
      );
}
