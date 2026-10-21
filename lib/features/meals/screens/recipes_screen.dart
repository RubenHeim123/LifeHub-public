import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:frontend/core/ui/app_actions.dart';
import 'package:frontend/core/ui/app_ui.dart';
import 'package:frontend/core/ui/modern_appbar.dart';
import 'package:frontend/core/ui/theme.dart';
import 'package:frontend/features/fitness/models/nutrition.dart';
import 'package:frontend/features/meals/models/meal_plan.dart';
import 'package:frontend/features/meals/repositories/meal_plan_repository.dart';
import 'package:frontend/features/meals/screens/recipe_editor_screen.dart';
import 'package:frontend/features/meals/screens/recipe_screen.dart';
import 'package:frontend/features/meals/widgets/meal_widgets.dart';

/// Alle Rezepte (eigene und mitgelieferte) mit Suche und Filter nach Mahlzeit.
/// Mit [pickFor] dient der Screen als Auswahl: Antippen liefert das Rezept zurück.
class RecipesScreen extends StatefulWidget {
  final int userid;
  final Meal? pickFor;

  /// Auswahl ohne Mahlzeitfilter (z. B. „Kochen einplanen“).
  final bool pick;
  const RecipesScreen({super.key, required this.userid, this.pickFor, this.pick = false});

  bool get picking => pick || pickFor != null;

  @override
  State<RecipesScreen> createState() => _RecipesScreenState();
}

class _RecipesScreenState extends State<RecipesScreen> {
  late final MealPlanRepository _repo = context.read<MealPlanRepository>();
  List<Recipe>? _recipes;
  String _search = '';

  /// `null` = alle, sonst nur Rezepte, die zu dieser Mahlzeit passen.
  late Meal? _meal = widget.pickFor;
  bool _ownOnly = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final recipes = await _repo.getRecipes(widget.userid);
    if (mounted) setState(() => _recipes = recipes);
  }

  List<Recipe> get _visible {
    final q = _search.trim().toLowerCase();
    return [
      for (final r in _recipes ?? const <Recipe>[])
        if ((_meal == null || r.meals.contains(_meal)) &&
            (!_ownOnly || r.isOwn) &&
            (q.isEmpty ||
                r.name.toLowerCase().contains(q) ||
                r.ingredients.any((i) => i.name.toLowerCase().contains(q))))
          r,
    ];
  }

  Future<void> _open(Recipe r) async {
    if (widget.picking) {
      Navigator.of(context).pop(r);
      return;
    }
    final result = await Navigator.of(context).push<Object?>(
      MaterialPageRoute(builder: (_) => RecipeScreen(userid: widget.userid, recipe: r)),
    );
    if (result == kDeletedResult && mounted) return _delete(r);
    _load();
  }

  Future<void> _delete(Recipe r) => deleteWithUndo(
        context,
        label: r.name,
        delete: () => _repo.deleteRecipe(r.id!),
        restore: () => _repo.restoreRecipe(r.id!),
        onChanged: _load,
      );

  Future<void> _edit([Recipe? r]) async {
    final result = await Navigator.of(context).push<Object?>(
      MaterialPageRoute(builder: (_) => RecipeEditorScreen(userid: widget.userid, recipe: r)),
    );
    if (result == null || !mounted) return;
    if (result == kDeletedResult && r != null) return _delete(r);
    await _load();
    if (result is Recipe && r == null && widget.picking && mounted) Navigator.of(context).pop(result);
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final t = Theme.of(context).textTheme;
    final recipes = _recipes;
    final visible = _visible;
    return Scaffold(
      appBar: ModernAppBar(
        title: widget.pickFor != null ? 'Gericht für ${widget.pickFor!.label}' : (widget.pick ? 'Rezept wählen' : 'Rezepte'),
      ),
      floatingActionButton: AppFab(heroTag: 'recipe-new', label: 'Eigenes Rezept', onPressed: () => _edit()),
      body: recipes == null
          ? Center(child: CircularProgressIndicator(color: c.accent))
          : ListView(padding: pagePadding(context), children: [
              TextField(
                decoration: const InputDecoration(prefixIcon: Icon(Icons.search_rounded), hintText: 'Gericht oder Zutat suchen'),
                onChanged: (v) => setState(() => _search = v),
              ),
              const SizedBox(height: 10),
              SizedBox(
                height: 40,
                child: ListView(scrollDirection: Axis.horizontal, children: [
                  AppChip(label: 'Alle', selected: _meal == null && !_ownOnly, onTap: () => setState(() {
                        _meal = null;
                        _ownOnly = false;
                      })),
                  for (final m in plannedMeals) ...[
                    const SizedBox(width: 8),
                    AppChip(label: m.label, selected: _meal == m, onTap: () => setState(() => _meal = _meal == m ? null : m)),
                  ],
                  const SizedBox(width: 8),
                  AppChip(label: 'Eigene', selected: _ownOnly, onTap: () => setState(() => _ownOnly = !_ownOnly)),
                ]),
              ),
              const SizedBox(height: 12),
              if (visible.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 32),
                  child: Text(
                    _ownOnly ? 'Noch keine eigenen Rezepte – leg unten eins an.' : 'Kein Rezept gefunden.',
                    textAlign: TextAlign.center,
                    style: t.bodyMedium?.copyWith(color: c.muted),
                  ),
                ),
              for (final r in visible)
                r.isOwn
                    ? SwipeTile(
                        id: 'recipe-${r.id}',
                        onEdit: () => _edit(r),
                        onDelete: () => _delete(r),
                        child: RecipeCard(recipe: r, onTap: () => _open(r)),
                      )
                    : RecipeCard(recipe: r, onTap: () => _open(r)),
            ]),
    );
  }
}
