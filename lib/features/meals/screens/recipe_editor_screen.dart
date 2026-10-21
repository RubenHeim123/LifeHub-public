import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:frontend/core/ui/form_widgets.dart';
import 'package:frontend/core/ui/app_actions.dart';
import 'package:frontend/core/ui/app_ui.dart';
import 'package:frontend/core/ui/modern_appbar.dart';
import 'package:frontend/features/fitness/models/nutrition.dart';
import 'package:frontend/features/meals/models/meal_plan.dart';
import 'package:frontend/features/meals/repositories/meal_plan_repository.dart';

/// Eigenes Rezept anlegen oder bearbeiten. Zutaten und Schritte je eine Zeile.
/// Liefert das gespeicherte [Recipe] bzw. [deleted] zurück.
class RecipeEditorScreen extends StatefulWidget {
  final int userid;
  final Recipe? recipe;
  const RecipeEditorScreen({super.key, required this.userid, this.recipe});

  static const deleted = kDeletedResult;

  @override
  State<RecipeEditorScreen> createState() => _RecipeEditorScreenState();
}

class _RecipeEditorScreenState extends State<RecipeEditorScreen> {
  final _formKey = GlobalKey<FormState>();
  late final Recipe? _r = widget.recipe;
  late final _name = TextEditingController(text: _r?.name);
  late final _summary = TextEditingController(text: _r?.summary);
  late final _servings = TextEditingController(text: '${_r?.servings ?? 2}');
  late final _minutes = TextEditingController(text: '${_r?.minutes ?? 20}');
  late final _ingredients = TextEditingController(text: _r?.ingredients.map((i) => i.toString()).join('\n'));
  late final _steps = TextEditingController(text: _r?.steps.join('\n'));
  late final _kcal = TextEditingController(text: _num(_r?.perServing.kcal));
  late final _protein = TextEditingController(text: _num(_r?.perServing.protein));
  late final _carbs = TextEditingController(text: _num(_r?.perServing.carbs));
  late final _fat = TextEditingController(text: _num(_r?.perServing.fat));
  late final _grams = TextEditingController(text: _num(_r?.gramsPerServing));
  late final Set<Meal> _meals = {...?_r?.meals};

  /// Nährwerte gelten pro Portion (Standard) oder fürs ganze Rezept – gespeichert wird pro Portion.
  bool _perRecipe = false;

  static String? _num(double? v) => v == null || v == 0 ? null : v.round().toString();
  static double _parse(TextEditingController c) => double.tryParse(c.text.replaceAll(',', '.').trim()) ?? 0;

  @override
  void dispose() {
    for (final c in [_name, _summary, _servings, _minutes, _ingredients, _steps, _kcal, _protein, _carbs, _fat, _grams]) {
      c.dispose();
    }
    super.dispose();
  }

  List<String> _lines(TextEditingController c) =>
      c.text.split('\n').map((l) => l.trim()).where((l) => l.isNotEmpty).toList();

  bool _saving = false;

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final navigator = Navigator.of(context);
    final servings = int.tryParse(_servings.text.trim())?.clamp(1, 50) ?? 1;
    // Angaben fürs ganze Rezept auf eine Portion umrechnen
    final divisor = _perRecipe ? servings.toDouble() : 1.0;
    final recipe = Recipe(
      id: _r?.id,
      userid: widget.userid,
      name: _name.text.trim(),
      summary: _summary.text.trim(),
      meals: _meals.isEmpty ? {Meal.lunch, Meal.dinner} : _meals,
      servings: servings,
      minutes: int.tryParse(_minutes.text.trim()) ?? 0,
      ingredients: _lines(_ingredients).map(Ingredient.parse).toList(),
      steps: _lines(_steps),
      perServing: Macros(kcal: _parse(_kcal), protein: _parse(_protein), carbs: _parse(_carbs), fat: _parse(_fat))
          .scaled(1 / divisor),
      gramsPerServing: _parse(_grams) > 0 ? _parse(_grams) : (_r?.gramsPerServing ?? 350),
    );
    final repo = context.read<MealPlanRepository>();
    setState(() => _saving = true);
    final id = await runGuarded(context, () => repo.saveRecipe(recipe));
    if (!mounted) return;
    setState(() => _saving = false);
    if (id != null) navigator.pop(Recipe.fromMap({...recipe.toMap(), 'id': id}));
  }

  /// Die Liste löscht dann mit „Rückgängig“; eingeplante Gerichte behalten ihren Namen.
  void _delete() => Navigator.of(context).pop(RecipeEditorScreen.deleted);

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    InputDecoration deco(String label, {String? hint}) => InputDecoration(labelText: label, hintText: hint);
    InputDecoration bare(String hint) => bareInputDecoration.copyWith(hintText: hint);
    Widget number(TextEditingController c, String label) => Expanded(
          child: TextFormField(controller: c, keyboardType: TextInputType.number, decoration: deco(label)),
        );
    return Scaffold(
      appBar: ModernAppBar(title: _r == null ? 'Neues Rezept' : 'Rezept bearbeiten'),
      body: Form(
        key: _formKey,
        child: ListView(padding: detailPadding(context), children: [
          FormFieldCard(
            icon: Icons.restaurant_menu_rounded,
            label: 'Name',
            child: TextFormField(
              controller: _name,
              autofocus: _r == null,
              decoration: bare('z. B. Ofengemüse'),
              validator: (v) => (v ?? '').trim().isEmpty ? 'Bitte einen Namen eingeben' : null,
            ),
          ),
          FormFieldCard(
            icon: Icons.notes_rounded,
            label: 'Kurzbeschreibung',
            child: TextFormField(controller: _summary, decoration: bare('Optional')),
          ),
          const GroupLabel('Passt zu'),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final m in plannedMeals)
              AppChip(
                label: m.label,
                selected: _meals.contains(m),
                onTap: () => setState(() => _meals.contains(m) ? _meals.remove(m) : _meals.add(m)),
              ),
          ]),
          const SizedBox(height: 16),
          Row(children: [
            number(_servings, 'Portionen'),
            const SizedBox(width: 12),
            number(_minutes, 'Minuten'),
          ]),
          const SizedBox(height: 16),
          FormFieldCard(
            icon: Icons.shopping_basket_outlined,
            label: 'Zutaten – eine pro Zeile',
            child: TextFormField(
              controller: _ingredients,
              minLines: 4,
              maxLines: null,
              decoration: bare('250 g rote Linsen\n1 Dose Tomaten\n2 Knoblauchzehen'),
            ),
          ),
          FormFieldCard(
            icon: Icons.format_list_numbered_rounded,
            label: 'Zubereitung – ein Schritt pro Zeile',
            child: TextFormField(controller: _steps, minLines: 4, maxLines: null, decoration: bare('Zwiebeln anbraten …')),
          ),
          const GroupLabel('Nährwerte (optional)'),
          Wrap(spacing: 8, runSpacing: 8, children: [
            AppChip(label: 'pro Portion', selected: !_perRecipe, onTap: () => setState(() => _perRecipe = false)),
            AppChip(label: 'fürs ganze Rezept', selected: _perRecipe, onTap: () => setState(() => _perRecipe = true)),
          ]),
          const SizedBox(height: 8),
          Row(children: [
            number(_kcal, 'kcal'),
            const SizedBox(width: 8),
            number(_protein, 'Eiweiß g'),
          ]),
          const SizedBox(height: 8),
          Row(children: [
            number(_carbs, 'KH g'),
            const SizedBox(width: 8),
            number(_fat, 'Fett g'),
          ]),
          const SizedBox(height: 8),
          Row(children: [number(_grams, 'Gramm pro Portion')]),
          if (_perRecipe)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text('Wird beim Speichern durch die Portionen geteilt.', style: t.bodySmall),
            ),
          const SizedBox(height: 24),
          FormActions(isNew: _r == null, busy: _saving, onSave: _save, onDelete: _delete),
        ]),
      ),
    );
  }
}
