import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:frontend/core/ui/app_actions.dart';
import 'package:frontend/core/ui/app_ui.dart';
import 'package:frontend/core/ui/theme.dart';
import 'package:frontend/features/fitness/models/nutrition.dart';
import 'package:frontend/features/fitness/repositories/nutrition_repository.dart';
import 'package:frontend/features/fitness/services/barcode_scanner.dart';
import 'package:frontend/features/fitness/services/open_food_facts_service.dart';
import 'package:frontend/features/lists/models/lists.dart';
import 'package:frontend/features/lists/repositories/lists_repository.dart';

/// Was die Detailansicht eines Artikels zurückgibt.
enum ShoppingDetailAction { edit, delete }

/// Detailansicht eines Einkaufsartikels: Gesamtmenge, Aufteilung nach Herkunft (z. B. je Rezept,
/// einzeln entfernbar), zugeordnetes Lebensmittel mit Packungsgrößen.
Future<ShoppingDetailAction?> showShoppingDetail(BuildContext context, ShoppingItem item) => showEditorSheet(
      context,
      (_) => _ShoppingDetailSheet(item: item),
    );

class _ShoppingDetailSheet extends StatefulWidget {
  final ShoppingItem item;
  const _ShoppingDetailSheet({required this.item});

  @override
  State<_ShoppingDetailSheet> createState() => _ShoppingDetailSheetState();
}

class _ShoppingDetailSheetState extends State<_ShoppingDetailSheet> {
  late final ListsRepository _repo = context.read<ListsRepository>();
  late final NutritionRepository _nutrition = context.read<NutritionRepository>();
  late ShoppingItem _item = widget.item;
  List<ShoppingSource>? _sources;
  Food? _food;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final sources = await _repo.getSources(_item.id!);
    final items = await _repo.getShopping(_item.userid);
    final food = _item.foodId == null ? null : await _nutrition.getFood(_item.foodId!);
    if (!mounted) return;
    setState(() {
      _sources = sources;
      _item = items.firstWhere((i) => i.id == _item.id, orElse: () => _item);
      _food = food;
    });
  }

  Future<void> _removeSource(ShoppingSource source) async {
    await deleteWithUndo(
      context,
      label: '${source.amountLabel ?? ''} ${_item.name}'.trim(),
      delete: () => _repo.removeSource(source),
      restore: () => _repo.restoreSource(source),
      onChanged: _load,
    );
  }

  Future<void> _pickFood() async {
    final food = await showFoodPicker(context, userid: _item.userid, initial: _item.name);
    if (food == null || !mounted) return;
    await runGuarded(context, () => _repo.saveShopping(_item.copyWith(foodId: food.id)));
    _item = _item.copyWith(foodId: food.id);
    _load();
  }

  Future<void> _editPackSizes() async {
    final food = _food!;
    final controller = TextEditingController(text: food.packSizes.map((s) => s.round()).join(', '));
    final unit = _item.unit ?? 'g';
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Packungsgrößen von ${food.name}'),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: TextInputType.text,
          decoration: InputDecoration(labelText: 'Größen in $unit, z. B. 400, 600'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Abbrechen')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, controller.text), child: const Text('Speichern')),
        ],
      ),
    );
    controller.dispose();
    if (result == null || !mounted) return;
    await runGuarded(context, () => _nutrition.saveFood(food.copyWith(packSizes: Food.parsePackSizes(result))));
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final t = Theme.of(context).textTheme;
    final sources = _sources;
    final need = _item.amount;
    final packs = _food?.packSizes ?? const <double>[];
    final plan = need != null && (_item.unit == 'g' || _item.unit == 'ml') ? packPlan(need, packs) : const <(double, int)>[];
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 16, 20, 16 + MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(_item.name, style: t.titleLarge),
          if (_item.quantityLabel != null)
            Text('Insgesamt: ${_item.quantityLabel}', style: t.titleMedium?.copyWith(color: c.accentText)),
          const SizedBox(height: 16),
          const GroupLabel('Wofür'),
          if (sources == null)
            const LinearProgressIndicator()
          else if (sources.isEmpty)
            Text('Keine Aufteilung vorhanden.', style: t.bodySmall)
          else
            AppCard(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
              child: Column(children: [
                for (final s in sources)
                  SwipeTile(
                    id: 'source-${s.id}',
                    onDelete: () => _removeSource(s),
                    child: ListTile(
                      dense: true,
                      leading: Icon(s.recipeKey != null || s.recipeId != null ? Icons.restaurant_menu_rounded : Icons.edit_note_rounded,
                          color: c.accentText),
                      title: Text(s.label),
                      trailing: Text(s.amountLabel ?? '', style: t.titleSmall),
                    ),
                  ),
              ]),
            ),
          const SizedBox(height: 16),
          const GroupLabel('Lebensmittel & Packungen'),
          AppCard(
            padding: const EdgeInsets.all(12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(child: Text(_food?.name ?? 'Keinem Lebensmittel zugeordnet', style: t.bodyLarge)),
                TextButton(onPressed: _pickFood, child: Text(_food == null ? 'Zuordnen' : 'Ändern')),
              ]),
              if (_food != null) ...[
                Row(children: [
                  Expanded(
                    child: Text(
                      packs.isEmpty
                          ? 'Keine Packungsgrößen hinterlegt'
                          : 'Erhältlich in ${packs.map((p) => formatAmount(p, _item.unit ?? 'g')).join(', ')}',
                      style: t.bodySmall,
                    ),
                  ),
                  TextButton(onPressed: _editPackSizes, child: const Text('Packungen')),
                ]),
                if (plan.isNotEmpty)
                  Text('Vorschlag: ${packPlanLabel(plan, _item.unit!)}', style: t.labelMedium?.copyWith(color: c.accentText)),
              ],
            ]),
          ),
          const SizedBox(height: 20),
          Row(children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => Navigator.of(context).pop(ShoppingDetailAction.delete),
                icon: Icon(Icons.delete_outline, color: c.negative),
                label: Text('Entfernen', style: TextStyle(color: c.negative)),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: ElevatedButton.icon(
                onPressed: () => Navigator.of(context).pop(ShoppingDetailAction.edit),
                icon: const Icon(Icons.edit_outlined),
                label: const Text('Bearbeiten'),
              ),
            ),
          ]),
        ]),
      ),
    );
  }
}

/// Lebensmittel suchen und auswählen (Einkaufsliste, Kassenzettel).
Future<Food?> showFoodPicker(BuildContext context, {required int userid, String initial = ''}) =>
    showEditorSheet<Food>(context, (_) => _FoodPicker(userid: userid, initial: initial));

class _FoodPicker extends StatefulWidget {
  final int userid;
  final String initial;
  const _FoodPicker({required this.userid, required this.initial});

  @override
  State<_FoodPicker> createState() => _FoodPickerState();
}

class _FoodPickerState extends State<_FoodPicker> {
  late final NutritionRepository _repo = context.read<NutritionRepository>();
  late final _search = TextEditingController(text: widget.initial.split(' ').first);
  List<Food> _foods = const [];

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

  int _loadId = 0;

  Future<void> _load() async {
    final loadId = ++_loadId; // ältere, langsamere Suchen nicht über neuere schreiben
    await _repo.ensureStandardFoods(widget.userid);
    final foods = await _repo.searchFoods(widget.userid, search: _search.text.trim());
    if (mounted && loadId == _loadId) setState(() => _foods = foods);
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 16, 20, 16 + MediaQuery.viewInsetsOf(context).bottom),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('Lebensmittel zuordnen', style: t.titleLarge),
        const SizedBox(height: 12),
        TextField(
          controller: _search,
          decoration: const InputDecoration(prefixIcon: Icon(Icons.search_rounded), hintText: 'Lebensmittel suchen'),
          onChanged: (_) => _load(),
        ),
        const SizedBox(height: 8),
        ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.45),
          child: ListView(shrinkWrap: true, children: [
            for (final f in _foods)
              ListTile(
                title: Text(f.name),
                subtitle: f.packSizes.isEmpty ? null : Text('Packungen: ${f.packSizes.map((p) => p.round()).join(', ')}'),
                onTap: () => Navigator.of(context).pop(f),
              ),
          ]),
        ),
      ]),
    );
  }
}

/// Ergebnis des Abhak-Dialogs: tatsächlich gekaufte Menge (oder `null` = wie geplant), dazu
/// optional ein gescannter Barcode und das dabei gefundene Lebensmittel.
class BoughtResult {
  final double? amount;

  /// g, ml, eine andere Einheit des Artikels oder `null` = Stück.
  final String? unit;
  final String? barcode;
  final int? foodId;
  const BoughtResult({this.amount, this.unit, this.barcode, this.foodId});
}

/// Beim Abhaken fragen, was tatsächlich gekauft wurde: Packung(en) des Lebensmittels, selbst
/// eingetragene Menge oder per Barcode. `null` = abgebrochen.
Future<BoughtResult?> askBought(BuildContext context, ShoppingItem item) async {
  final food = item.foodId == null ? null : await context.read<NutritionRepository>().getFood(item.foodId!);
  if (!context.mounted) return null;
  return showDialog<BoughtResult>(context: context, builder: (_) => _BoughtDialog(item: item, food: food));
}

class _BoughtDialog extends StatefulWidget {
  final ShoppingItem item;

  /// Zugeordnetes Lebensmittel (Packungsgrößen), falls vorhanden.
  final Food? food;
  const _BoughtDialog({required this.item, this.food});

  @override
  State<_BoughtDialog> createState() => _BoughtDialogState();
}

class _BoughtDialogState extends State<_BoughtDialog> {
  late final NutritionRepository _nutrition = context.read<NutritionRepository>();
  late final _amount = TextEditingController(text: widget.item.amount == null ? '' : _plain(widget.item.amount!));
  late String? _unit = widget.item.unit;
  Food? _food;
  String? _barcode;
  String? _scanInfo;
  bool _manual = false;
  bool _rememberPack = false;
  Map<double, int> _counts = {};

  static String _plain(double v) => v == v.roundToDouble() ? v.round().toString() : v.toString().replaceAll('.', ',');

  /// Packungen gibt es nur in g/ml; ohne Mengenangabe wird g angenommen.
  String get _packUnit => _unit == 'ml' ? 'ml' : 'g';
  List<double> get _sizes => _food?.packSizes ?? const [];
  bool get _usePacks => !_manual && _sizes.isNotEmpty && (_unit == 'g' || _unit == 'ml' || widget.item.amount == null);

  double get _packTotal => _counts.entries.fold(0.0, (s, e) => s + e.key * e.value);
  double? get _typed => double.tryParse(_amount.text.trim().replaceAll(',', '.'));

  @override
  void initState() {
    super.initState();
    _setFood(widget.food);
  }

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  void _setFood(Food? food) {
    _food = food;
    final need = widget.item.unit == 'g' || widget.item.unit == 'ml' ? (widget.item.amount ?? 0) : 0.0;
    final plan = packPlan(need, _sizes);
    _counts = {
      for (final s in _sizes) s: 0,
      for (final (size, count) in plan) size: count,
    };
    // Ohne Plan (z. B. ohne Mengenangabe): eine Packung der ersten Größe
    if (plan.isEmpty && _sizes.isNotEmpty) _counts[_sizes.first] = 1;
  }

  Future<void> _scan() async {
    final scanner = context.read<BarcodeScanner>();
    final lookup = context.read<FoodLookupService>();
    final code = await scanner.scan(context);
    if (code == null || !mounted) return;
    Food? found;
    var offline = false;
    try {
      found = await lookup.byBarcode(widget.item.userid, code);
    } on OpenFoodFactsException {
      offline = true;
    }
    final current = _food;
    if (found == null && current != null) {
      // Unbekannt/offline: Barcode an das zugeordnete Lebensmittel hängen (samt Packungsgrößen),
      // damit der nächste Scan sofort klappt
      final linked = await _nutrition.linkBarcode(widget.item.userid, code, current);
      found = await _nutrition.saveFood(linked.copyWith(packSizes: current.packSizes));
    }
    if (!mounted) return;
    setState(() {
      _barcode = code;
      if (found != null) {
        _setFood(found);
        _manual = false;
        final packs = found.packSizes.map((p) => formatAmount(p, _packUnit)).join(', ');
        _scanInfo = 'Barcode $code · ${found.name}${packs.isEmpty ? '' : ' · $packs'}';
      } else {
        _scanInfo = offline
            ? 'Barcode $code gespeichert – Produktdaten gerade nicht erreichbar'
            : 'Barcode $code gespeichert – Produkt unbekannt';
      }
    });
  }

  BoughtResult? get _result {
    if (_usePacks) {
      if (_packTotal <= 0) return null;
      return BoughtResult(amount: _packTotal, unit: _packUnit, barcode: _barcode, foodId: _food?.id);
    }
    final typed = _typed;
    if (typed == null || typed <= 0) return null;
    return BoughtResult(amount: typed, unit: _unit, barcode: _barcode, foodId: _food?.id);
  }

  Future<void> _confirm() async {
    final result = _result!;
    final food = _food;
    if (!_usePacks && _rememberPack && food != null && (result.unit == 'g' || result.unit == 'ml')) {
      final sizes = {...food.packSizes, result.amount!}.toList()..sort();
      await _nutrition.saveFood(food.copyWith(packSizes: sizes));
    }
    if (mounted) Navigator.of(context).pop(result);
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final c = AppColors.of(context);
    final item = widget.item;
    final units = <String?>{null, 'g', 'ml', item.unit};
    return AlertDialog(
      title: const Text('Was hast du gekauft?'),
      content: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(item.quantityLabel == null ? item.name : '${item.name} – gebraucht: ${item.quantityLabel}', style: t.bodyMedium),
          const SizedBox(height: 12),
          if (_usePacks) ...[
            for (final size in _sizes)
              Row(children: [
                Expanded(child: Text('Packung ${formatAmount(size, _packUnit)}')),
                IconButton(
                  tooltip: 'Eine weniger',
                  onPressed: (_counts[size] ?? 0) == 0 ? null : () => setState(() => _counts[size] = _counts[size]! - 1),
                  icon: const Icon(Icons.remove_circle_outline),
                ),
                Text('${_counts[size] ?? 0}×', style: t.titleMedium),
                IconButton(
                  tooltip: 'Eine mehr',
                  onPressed: () => setState(() => _counts[size] = (_counts[size] ?? 0) + 1),
                  icon: const Icon(Icons.add_circle_outline),
                ),
              ]),
            const SizedBox(height: 4),
            Text('In den Vorrat: ${formatAmount(_packTotal, _packUnit)}', style: t.titleSmall),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(onPressed: () => setState(() => _manual = true), child: const Text('Andere Menge eintragen')),
            ),
          ] else ...[
            Row(children: [
              Expanded(
                child: TextField(
                  key: const Key('boughtAmount'),
                  controller: _amount,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: 'Gekaufte Menge'),
                  onChanged: (_) => setState(() {}),
                ),
              ),
              const SizedBox(width: 12),
              DropdownButton<String?>(
                value: _unit,
                items: [for (final u in units) DropdownMenuItem(value: u, child: Text(u ?? 'Stück'))],
                onChanged: (u) => setState(() => _unit = u),
              ),
            ]),
            if (_food != null && (_unit == 'g' || _unit == 'ml'))
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                value: _rememberPack,
                onChanged: (v) => setState(() => _rememberPack = v ?? false),
                title: Text('Als Packungsgröße von ${_food!.name} merken'),
              ),
            if (_sizes.isNotEmpty)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(onPressed: () => setState(() => _manual = false), child: const Text('Packungen wählen')),
              ),
          ],
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _scan,
            icon: const Icon(Icons.qr_code_scanner_rounded),
            label: Text(_barcode == null ? 'Barcode scannen' : 'Neu scannen'),
          ),
          if (_scanInfo != null) ...[
            const SizedBox(height: 6),
            Text(_scanInfo!, style: t.bodySmall?.copyWith(color: c.accentText)),
          ],
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Abbrechen')),
        TextButton(
          onPressed: () => Navigator.of(context).pop(BoughtResult(barcode: _barcode, foodId: _food?.id)),
          child: const Text('Wie geplant'),
        ),
        ElevatedButton(onPressed: _result == null ? null : _confirm, child: const Text('Abhaken')),
      ],
    );
  }
}
