import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:frontend/core/ui/dialogs.dart';
import 'package:frontend/features/fitness/catalog/standard_foods.dart';
import 'package:frontend/features/fitness/models/nutrition.dart';
import 'package:frontend/features/fitness/repositories/nutrition_repository.dart';
import 'package:frontend/features/fitness/screens/food_editor_screen.dart';
import 'package:frontend/features/fitness/services/barcode_scanner.dart';
import 'package:frontend/features/fitness/services/open_food_facts_service.dart';
import 'package:frontend/features/inventory/models/inventory_item.dart';

/// Barcode scannen und das passende Lebensmittel liefern: aus den eigenen Lebensmitteln
/// (funktioniert offline), von Open Food Facts oder – wenn unbekannt/offline – per Zuordnung
/// zu einem vorhandenen Lebensmittel bzw. Standardprodukt oder über den Editor mit vorbelegtem
/// Barcode. `null`, wenn abgebrochen wurde.
Future<Food?> scanFoodBarcode(BuildContext context, int uid) async {
  final scanner = context.read<BarcodeScanner>();
  final lookup = context.read<FoodLookupService>();
  final messenger = ScaffoldMessenger.of(context);
  final navigator = Navigator.of(context);
  final nutrition = context.read<NutritionRepository>();

  final code = await scanner.scan(context);
  if (code == null) return null;

  Food? food;
  var offline = false;
  try {
    food = await lookup.byBarcode(uid, code);
  } on OpenFoodFactsException {
    offline = true;
  }
  if (food != null) return food;
  if (!context.mounted) return null;

  final choice = await showModalBottomSheet<String>(
    context: context,
    builder: (ctx) => SafeArea(
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
          child: Text(offline ? 'Keine Verbindung' : 'Produkt unbekannt', style: Theme.of(ctx).textTheme.titleLarge),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
          child: Text(
            offline
                ? 'Barcode $code ist noch nicht gespeichert und Open Food Facts ist gerade nicht erreichbar. '
                    'Ordne ihn einem Lebensmittel zu – beim nächsten Scan klappt es dann auch offline.'
                : 'Barcode $code ist bei Open Food Facts nicht bekannt.',
            style: Theme.of(ctx).textTheme.bodySmall,
          ),
        ),
        ListTile(
          leading: const Icon(Icons.link_rounded),
          title: const Text('Vorhandenem Lebensmittel zuordnen'),
          subtitle: const Text('z. B. einem Standardprodukt wie Haferflocken'),
          onTap: () => Navigator.of(ctx).pop('link'),
        ),
        ListTile(
          leading: const Icon(Icons.edit_note_rounded),
          title: const Text('Nährwerte selbst eintragen'),
          onTap: () => Navigator.of(ctx).pop('edit'),
        ),
      ]),
    ),
  );
  if (choice == 'link' && context.mounted) {
    final source = await pickFood(context, uid);
    if (source == null) return null;
    final linked = await nutrition.linkBarcode(uid, code, source);
    messenger.showSnackBar(SnackBar(content: Text('Barcode mit „${linked.name}“ verknüpft')));
    return linked;
  }
  if (choice != 'edit') return null;
  return navigator.push<Food>(MaterialPageRoute(
    builder: (_) => FoodEditorScreen(userid: uid, draft: Food(userid: uid, name: '', barcode: code)),
  ));
}

/// Anzeige der Herkunft eines Lebensmittels in Listen.
String foodSubtitle(Food f) => f.isDish
    ? ['Gericht', '${f.portionMacros.kcal.round()} kcal je Portion', '${f.portionMacros.protein.round()} g Eiweiß'].join(' · ')
    : [
        if (f.brand == standardFoodBrand) 'Standardprodukt' else if (f.brand != null) f.brand!,
        '${f.per100.kcal.round()} kcal / 100 g',
        '${f.per100.protein.round()} g Eiweiß',
      ].join(' · ');

/// Lebensmittel aus den eigenen (inkl. Standardprodukten) auswählen.
Future<Food?> pickFood(BuildContext context, int uid) {
  return showModalBottomSheet<Food>(
    context: context,
    isScrollControlled: true,
    builder: (_) => FractionallySizedBox(heightFactor: 0.85, child: _FoodPicker(uid: uid)),
  );
}

class _FoodPicker extends StatefulWidget {
  final int uid;
  const _FoodPicker({required this.uid});

  @override
  State<_FoodPicker> createState() => _FoodPickerState();
}

class _FoodPickerState extends State<_FoodPicker> {
  late final NutritionRepository _repo = context.read<NutritionRepository>();
  String _query = '';
  List<Food> _foods = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  int _loadId = 0;

  Future<void> _load() async {
    final loadId = ++_loadId; // ältere, langsamere Suchen nicht über neuere schreiben
    await _repo.ensureStandardFoods(widget.uid);
    final list = await _repo.searchFoods(widget.uid, search: _query);
    if (mounted && loadId == _loadId) setState(() => _foods = list);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
          child: Text('Lebensmittel zuordnen', style: Theme.of(context).textTheme.titleLarge),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: TextField(
            autofocus: true,
            decoration: const InputDecoration(hintText: 'Suchen', prefixIcon: Icon(Icons.search_rounded)),
            onChanged: (v) {
              _query = v;
              _load();
            },
          ),
        ),
        Expanded(
          child: ListView(children: [
            for (final f in _foods)
              ListTile(
                title: Text(f.name),
                subtitle: Text(foodSubtitle(f)),
                onTap: () => Navigator.of(context).pop(f),
              ),
          ]),
        ),
      ]),
    );
  }
}

/// Barcode scannen und einen Vorrats-Entwurf daraus machen (Name, Marke, verknüpftes Lebensmittel).
Future<InventoryItem?> scanPantryItem(BuildContext context, int uid) async {
  final food = await scanFoodBarcode(context, uid);
  if (food == null) return null;
  return InventoryItem(
    userid: uid,
    kind: InventoryKind.food,
    name: food.name,
    brand: food.brand,
    barcode: food.barcode,
    foodId: food.id,
  );
}

/// Fragt die Anzahl Portionen ab (Gerichte und Rezepte), z. B. „1,5“.
Future<double?> askPortions(BuildContext context, String title, {double initial = 1}) async {
  final values = await showTextFieldsDialog(
    context,
    title: title,
    confirmLabel: 'Eintragen',
    fields: [DialogField('Portionen', initial: initial == initial.roundToDouble() ? '${initial.toInt()}' : '$initial'.replaceAll('.', ','), required: true)],
  );
  if (values == null) return null;
  final portions = double.tryParse(values[0]!.trim().replaceAll(',', '.'));
  return portions == null || portions <= 0 ? null : portions;
}

/// Fragt die Menge in Gramm ab (Vorschlag: Portion oder 100 g).
Future<double?> askGrams(BuildContext context, Food food, {String unit = 'g', double? initial}) async {
  final suggestion = initial ?? food.servingGrams ?? 100;
  final values = await showTextFieldsDialog(
    context,
    title: food.name,
    confirmLabel: 'Eintragen',
    fields: [DialogField('Menge in $unit', initial: suggestion == suggestion.roundToDouble() ? '${suggestion.toInt()}' : '$suggestion', required: true)],
  );
  if (values == null) return null;
  final grams = double.tryParse(values[0]!.replaceAll(',', '.'));
  return grams == null || grams <= 0 ? null : grams;
}
