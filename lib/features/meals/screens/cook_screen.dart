import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import 'package:frontend/core/ui/app_actions.dart';
import 'package:frontend/core/ui/app_ui.dart';
import 'package:frontend/core/ui/modern_appbar.dart';
import 'package:frontend/core/ui/theme.dart';
import 'package:frontend/features/inventory/models/inventory_item.dart';
import 'package:frontend/features/inventory/repositories/inventory_repository.dart';
import 'package:frontend/features/meals/models/meal_plan.dart';
import 'package:frontend/features/meals/repositories/meal_plan_repository.dart';
import 'package:frontend/features/meals/services/pantry_check.dart';

/// „Gekocht“ eintragen: an welchem Tag, welches Rezept – und was dafür aus dem Vorrat genommen
/// wurde. Je Zutat steht die Menge laut Rezept (z. B. 200 g Paprika) neben dem tatsächlich
/// Genommenen (z. B. 2 Stück Paprika aus dem Vorrat). Liefert `true` nach dem Speichern.
class CookScreen extends StatefulWidget {
  final int userid;
  final Recipe recipe;

  /// Eingeplanter Koch-Block (sonst „ohne Plan gekocht“).
  final MealBatch? batch;
  const CookScreen({super.key, required this.userid, required this.recipe, this.batch});

  @override
  State<CookScreen> createState() => _CookScreenState();
}

class _Row {
  final Ingredient ingredient;
  InventoryItem? item;
  final TextEditingController amount = TextEditingController();
  _Row(this.ingredient);
}

class _CookScreenState extends State<CookScreen> {
  late final InventoryRepository _inventory = context.read<InventoryRepository>();
  late DateTime _date = _today();
  late double _factor = widget.batch?.factor ?? 1;
  List<InventoryItem> _pantry = const [];

  /// Vorrat und Reservierungen geladen – vorher gibt es nichts abzubuchen.
  bool _loaded = false;
  late final List<_Row> _rows = [for (final i in widget.recipe.ingredients) _Row(i)];
  bool _saving = false;

  static DateTime _today() {
    final n = DateTime.now();
    return DateTime(n.year, n.month, n.day);
  }

  @override
  void initState() {
    super.initState();
    _loadPantry();
  }

  /// Vorrat laden; beim Kochen eines geplanten Blocks stehen die beim Planen reservierten Artikel
  /// und Mengen schon drin, sonst wird nach dem Namen vorgeschlagen.
  Future<void> _loadPantry() async {
    final meals = context.read<MealPlanRepository>();
    final items = await _inventory.getItems(widget.userid, kinds: {InventoryKind.food, InventoryKind.drink, InventoryKind.other});
    final batch = widget.batch;
    final reserved = batch?.id == null ? const <PantryReservation>[] : await meals.reservationsOf(batch!.id!);
    if (!mounted) return;
    setState(() {
      _pantry = items;
      _loaded = true;
      for (final r in _rows) {
        final reservation = reserved.where((x) => x.ingredient == r.ingredient.name).firstOrNull;
        final reservedItem = reservation == null ? null : items.where((i) => i.id == reservation.itemId).firstOrNull;
        if (reservedItem != null) {
          r.item = reservedItem;
          if (reservation!.amount != null) {
            r.amount.text = _num(reservation.amount!.clamp(0, reservedItem.quantity).toDouble());
          } else {
            _prefill(r);
          }
        } else {
          r.item = _suggest(r.ingredient);
          _prefill(r);
        }
      }
    });
  }

  @override
  void dispose() {
    for (final r in _rows) {
      r.amount.dispose();
    }
    super.dispose();
  }

  /// Vorratsartikel, dessen Name zur Zutat passt („Paprika“ ↔ „Paprika rot“).
  InventoryItem? _suggest(Ingredient ingredient) => matchPantryItem(ingredient, _pantry);

  /// Vorschlag für die genommene Menge: gleiche Einheit → Rezeptmenge, sonst leer lassen.
  void _prefill(_Row r) {
    final item = r.item;
    final need = r.ingredient.amount == null ? null : r.ingredient.amount! * _factor;
    if (item == null || need == null) {
      r.amount.text = '';
      return;
    }
    final unit = item.unit?.toLowerCase().trim();
    final same = unit == r.ingredient.unit?.toLowerCase() || (unit == null && r.ingredient.unit == null);
    r.amount.text = same ? _num(need.clamp(0, item.quantity).toDouble()) : '';
  }

  static String _num(double v) => v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(1).replaceAll('.', ',');

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(_date.year - 1),
      lastDate: _today(),
      helpText: 'Gekocht am',
    );
    if (picked != null) setState(() => _date = DateTime(picked.year, picked.month, picked.day));
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final navigator = Navigator.of(context);
    final usages = [
      for (final r in _rows)
        CookUsage(
          ingredient: r.ingredient.name,
          planned: r.ingredient.amountFor(_factor).isEmpty ? null : r.ingredient.amountFor(_factor),
          itemId: r.item?.id,
          itemName: r.item?.name,
          amount: double.tryParse(r.amount.text.trim().replaceAll(',', '.')),
          unit: r.item?.unit,
        ),
    ];
    final ok = await runGuarded(context, () async {
      await context.read<MealPlanRepository>().markCooked(
            uid: widget.userid,
            recipe: widget.recipe,
            date: _date,
            usages: usages,
            batch: widget.batch,
          );
      return true;
    });
    if (!mounted) return;
    setState(() => _saving = false);
    if (ok == true) navigator.pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final t = Theme.of(context).textTheme;
    return Scaffold(
      appBar: ModernAppBar(title: 'Gekocht'),
      body: SafeArea(
        child: !_loaded
            ? Center(child: CircularProgressIndicator(color: c.accent))
            : ListView(padding: detailPadding(context), children: [
                Text(widget.recipe.name, style: t.titleLarge),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: _pickDate,
                  icon: const Icon(Icons.event_available_rounded),
                  label: Text('Gekocht am ${DateFormat('EEEE, d. MMMM', 'de_DE').format(_date)}'),
                ),
                if (widget.batch == null) ...[
                  const SizedBox(height: 8),
                  Wrap(spacing: 8, runSpacing: 8, children: [
                    for (final f in const [1.0, 1.5, 2.0])
                      AppChip(
                        label: '×${_num(f)} (${_num(widget.recipe.servings * f)} Portionen)',
                        selected: _factor == f,
                        onTap: () => setState(() {
                          _factor = f;
                          for (final r in _rows) {
                            _prefill(r);
                          }
                        }),
                      ),
                  ]),
                ],
                const SizedBox(height: 16),
                GroupLabel('Aus dem Vorrat genommen', trailing: 'laut Rezept'),
                for (final r in _rows) _row(context, r),
                const SizedBox(height: 8),
                Text('Ohne Vorratsartikel wird nichts abgebucht. Die Mengen sind in der Einheit des Vorrats (z. B. Stück).',
                    style: t.bodySmall?.copyWith(color: c.muted)),
                const SizedBox(height: 16),
                ElevatedButton.icon(
                  onPressed: _saving ? null : _save,
                  icon: const Icon(Icons.check_rounded),
                  label: const Text('Als gekocht eintragen'),
                ),
              ]),
      ),
    );
  }

  Widget _row(BuildContext context, _Row r) {
    final c = AppColors.of(context);
    final t = Theme.of(context).textTheme;
    final planned = r.ingredient.amountFor(_factor);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: AppCard(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Expanded(child: Text(r.ingredient.name, style: t.titleSmall)),
            if (planned.isNotEmpty) Text(planned, style: t.labelMedium?.copyWith(color: c.accentText)),
          ]),
          const SizedBox(height: 6),
          Row(children: [
            Expanded(
              flex: 3,
              child: DropdownButtonFormField<int?>(
                isExpanded: true,
                value: r.item?.id,
                decoration: const InputDecoration(isDense: true, labelText: 'Vorrat'),
                items: [
                  const DropdownMenuItem(value: null, child: Text('Nicht aus dem Vorrat')),
                  for (final item in _pantry)
                    DropdownMenuItem(
                      value: item.id,
                      child: Text('${item.name} (${_num(item.quantity)} ${item.unit ?? 'Stück'})', overflow: TextOverflow.ellipsis),
                    ),
                ],
                onChanged: (id) => setState(() {
                  r.item = id == null ? null : _pantry.firstWhere((i) => i.id == id);
                  _prefill(r);
                }),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              flex: 2,
              child: TextField(
                controller: r.amount,
                enabled: r.item != null,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(isDense: true, labelText: 'Genommen', suffixText: r.item?.unit ?? 'Stück'),
              ),
            ),
          ]),
        ]),
      ),
    );
  }
}
