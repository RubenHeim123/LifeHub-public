import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:frontend/core/services/image_store.dart';
import 'package:frontend/core/ui/app_actions.dart';
import 'package:frontend/core/ui/app_ui.dart';
import 'package:frontend/core/ui/form_widgets.dart';
import 'package:frontend/core/ui/modern_appbar.dart';
import 'package:frontend/features/inventory/models/inventory_item.dart';
import 'package:frontend/features/inventory/repositories/inventory_repository.dart';
import 'package:frontend/features/inventory/widgets/inventory_widgets.dart';

/// Eintrag im Vorrat oder Kleiderschrank anlegen/bearbeiten.
/// Gibt beim Schließen `true` zurück, wenn sich etwas geändert hat.
class ItemEditorScreen extends StatefulWidget {
  final int userid;
  final InventoryKind kind;
  final InventoryItem? item;

  /// Vorbelegung für neue Einträge (z. B. aus einem Barcode).
  final InventoryItem? draft;

  /// Wählbare Arten beim Anlegen (z. B. Kleidung, Accessoire, Pflege & Duft).
  final List<InventoryKind>? kinds;

  /// Barcode scannen und Felder vorbelegen (nur beim Anlegen).
  final Future<InventoryItem?> Function()? onScanBarcode;

  /// Rückgabewert, wenn im Editor „Löschen“ gewählt wurde – die Liste löscht dann mit „Rückgängig“.
  static const deleted = kDeletedResult;

  const ItemEditorScreen({
    super.key,
    required this.userid,
    required this.kind,
    this.item,
    this.draft,
    this.kinds,
    this.onScanBarcode,
  });

  @override
  State<ItemEditorScreen> createState() => _ItemEditorScreenState();
}

class _ItemEditorScreenState extends State<ItemEditorScreen> {
  final _formKey = GlobalKey<FormState>();
  late final InventoryRepository _repo = context.read<InventoryRepository>();
  late final InventoryImageStore _images = context.read<InventoryImageStore>();

  late InventoryKind _kind;
  late final TextEditingController _name, _category, _location, _quantity, _unit, _brand, _size, _color, _season, _price, _notes;
  DateTime? _purchaseDate, _expiryDate, _openedDate;
  ItemCondition? _condition;
  String? _imagePath;
  File? _imageFile;
  bool _saving = false;

  bool get _isNew => widget.item == null;
  bool get _consumable => _kind.isConsumable;

  String? _barcode;
  int? _foodId;

  /// Passende Arten zur Auswahl: Kleiderschrank-Arten oder Vorrats-Arten.
  List<InventoryKind> get _kindChoices {
    final given = widget.kinds;
    if (given != null && given.contains(_kind)) return given;
    return _kind.isWearable || _kind == InventoryKind.care
        ? const [InventoryKind.clothing, InventoryKind.accessory, InventoryKind.care]
        : const [InventoryKind.food, InventoryKind.drink, InventoryKind.other];
  }

  @override
  void initState() {
    super.initState();
    final i = widget.item ?? widget.draft;
    _kind = i?.kind ?? widget.kind;
    TextEditingController t(String? v) => TextEditingController(text: v ?? '');
    _name = t(i?.name);
    _category = t(i?.category);
    _location = t(i?.location);
    _quantity = t(i == null ? '1' : _formatNumber(i.quantity));
    _unit = t(i?.unit);
    _brand = t(i?.brand);
    _size = t(i?.size);
    _color = t(i?.color);
    _season = t(i?.season);
    _price = t(i?.price == null ? null : _formatNumber(i!.price!));
    _notes = t(i?.notes);
    _purchaseDate = i?.purchaseDate ?? (_isNew ? DateTime.now() : null);
    _expiryDate = i?.expiryDate;
    _openedDate = i?.openedDate;
    _condition = i?.condition ?? (_kind.isWearable && _isNew ? ItemCondition.newItem : null);
    _imagePath = i?.imagePath;
    _barcode = i?.barcode;
    _foodId = i?.foodId;
    _images.resolve(_imagePath).then((f) => mounted ? setState(() => _imageFile = f) : null);
  }

  static String _formatNumber(double v) => v == v.roundToDouble() ? v.toInt().toString() : v.toString().replaceAll('.', ',');
  static double? _parse(String s) => double.tryParse(s.trim().replaceAll(',', '.'));
  static String? _text(TextEditingController c) => c.text.trim().isEmpty ? null : c.text.trim();

  @override
  void dispose() {
    for (final c in [_name, _category, _location, _quantity, _unit, _brand, _size, _color, _season, _price, _notes]) {
      c.dispose();
    }
    super.dispose();
  }

  /// Barcode scannen: Name, Marke, Kategorie und Verknüpfung zum Lebensmittel übernehmen.
  Future<void> _scan() async {
    final scanned = await widget.onScanBarcode!();
    if (scanned == null || !mounted) return;
    setState(() {
      if (_kindChoices.contains(scanned.kind)) _kind = scanned.kind;
      _name.text = scanned.name;
      if (scanned.brand != null) _brand.text = scanned.brand!;
      if (scanned.category != null) _category.text = scanned.category!;
      if (scanned.unit != null) _unit.text = scanned.unit!;
      _barcode = scanned.barcode ?? _barcode;
      _foodId = scanned.foodId ?? _foodId;
    });
  }

  /// Schnellwahl fürs Ablaufdatum: „3 Tage“, „1 Woche“ …
  Widget _expiryChips() {
    final now = DateTime.now();
    DateTime inDays(int d) => DateTime(now.year, now.month, now.day + d);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Wrap(spacing: 8, runSpacing: 8, children: [
        for (final (label, days) in const [('3 Tage', 3), ('1 Woche', 7), ('1 Monat', 30), ('6 Monate', 182), ('1 Jahr', 365)])
          AppChip(
            label: label,
            selected: _expiryDate == inDays(days),
            onTap: () => setState(() => _expiryDate = inDays(days)),
          ),
      ]),
    );
  }

  Future<void> _pickImage() async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final result = await FilePicker.platform.pickFiles(type: FileType.image);
      final path = result?.files.single.path;
      if (path == null) return;
      final stored = await _images.importFile(path);
      final file = await _images.resolve(stored);
      setState(() {
        _imagePath = stored;
        _imageFile = file;
      });
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Bild konnte nicht übernommen werden: ${errorText(e)}')));
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    final navigator = Navigator.of(context);
    final old = widget.item;
    final item = InventoryItem(
      id: old?.id,
      userid: widget.userid,
      kind: _kind,
      name: _name.text.trim(),
      category: _text(_category),
      location: _text(_location),
      quantity: _consumable ? (_parse(_quantity.text) ?? 1) : 1,
      unit: _consumable ? _text(_unit) : null,
      brand: _text(_brand),
      barcode: _barcode,
      purchaseDate: _purchaseDate,
      expiryDate: _consumable ? _expiryDate : null,
      openedDate: _consumable ? _openedDate : null,
      condition: _condition,
      imagePath: _imagePath,
      size: _consumable ? null : _text(_size),
      color: _consumable ? null : _text(_color),
      season: _consumable ? null : _text(_season),
      lastUsedAt: old?.lastUsedAt,
      wearCount: old?.wearCount ?? 0,
      price: _parse(_price.text),
      notes: _text(_notes),
      foodId: _foodId,
    );
    final ok = await runGuarded(context, () async {
      if (_isNew) {
        await _repo.createItem(item);
      } else {
        await _repo.updateItem(item);
        if (old!.imagePath != _imagePath) await _images.delete(old.imagePath);
      }
      return true;
    });
    if (ok != true) {
      if (mounted) setState(() => _saving = false);
      return;
    }
    navigator.pop(true);
  }

  void _delete() => Navigator.of(context).pop(ItemEditorScreen.deleted);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: ModernAppBar(
        title: _isNew ? '${_kind.label} hinzufügen' : 'Bearbeiten',
        customActions: [
          if (_isNew && widget.onScanBarcode != null)
            IconButton(tooltip: 'Barcode scannen', icon: const Icon(Icons.qr_code_scanner_rounded), onPressed: _scan),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Form(
            key: _formKey,
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              _photo(),
              const SizedBox(height: 16),
              _textCard(Icons.label_outline, 'Name', _name, required: true),
              FormFieldCard(
                  icon: Icons.category_outlined,
                  label: 'Art',
                  child: DropdownButtonFormField<InventoryKind>(
                    isExpanded: true,
                    value: _kind,
                    decoration: bareInputDecoration,
                    items: [
                      for (final k in _kindChoices) DropdownMenuItem(value: k, child: Text(k.label)),
                    ],
                    onChanged: (k) => setState(() => _kind = k!),
                  ),
                ),
              _suggestCard(Icons.folder_outlined, 'Kategorie', _category, _kind.suggestedCategories),
              _suggestCard(Icons.place_outlined, 'Ort', _location, _kind.suggestedLocations),
              if (_consumable)
                Row(children: [
                  Expanded(child: _textCard(Icons.numbers_rounded, 'Menge', _quantity, number: true)),
                  const SizedBox(width: 12),
                  Expanded(child: _textCard(Icons.straighten_rounded, 'Einheit', _unit, hint: 'Stück, g, l …')),
                ]),
              if (_consumable) ...[
                DateField(
                  label: 'Ablaufdatum',
                  icon: Icons.event_busy_rounded,
                  value: _expiryDate,
                  required: false,
                  onChanged: (d) => setState(() => _expiryDate = d),
                  onCleared: () => setState(() => _expiryDate = null),
                ),
                _expiryChips(),
                DateField(
                  label: 'Geöffnet am',
                  icon: Icons.lock_open_rounded,
                  value: _openedDate,
                  required: false,
                  onChanged: (d) => setState(() => _openedDate = d),
                  onCleared: () => setState(() => _openedDate = null),
                ),
              ],
              if (!_consumable) ...[
                Row(children: [
                  Expanded(child: _textCard(Icons.straighten_rounded, 'Größe', _size)),
                  const SizedBox(width: 12),
                  Expanded(child: _textCard(Icons.palette_outlined, 'Farbe', _color)),
                ]),
                _suggestCard(Icons.wb_sunny_outlined, 'Saison', _season, const ['Ganzjährig', 'Sommer', 'Winter', 'Übergang']),
              ],
              FormFieldCard(
                icon: Icons.verified_outlined,
                label: 'Zustand',
                child: DropdownButtonFormField<ItemCondition?>(
                  isExpanded: true,
                  value: _condition,
                  decoration: bareInputDecoration,
                  items: [
                    const DropdownMenuItem(value: null, child: Text('–')),
                    for (final c in ItemCondition.values) DropdownMenuItem(value: c, child: Text(c.label)),
                  ],
                  onChanged: (c) => setState(() => _condition = c),
                ),
              ),
              _textCard(Icons.sell_outlined, 'Marke', _brand),
              DateField(
                label: 'Gekauft am',
                icon: Icons.shopping_bag_outlined,
                value: _purchaseDate,
                required: false,
                onChanged: (d) => setState(() => _purchaseDate = d),
                onCleared: () => setState(() => _purchaseDate = null),
              ),
              _textCard(Icons.euro_rounded, 'Preis (€)', _price, number: true),
              _textCard(Icons.notes_rounded, 'Notizen', _notes, maxLines: 3),
              const SizedBox(height: 8),
              FormActions(isNew: _isNew, busy: _saving, onSave: _save, onDelete: _isNew ? null : _delete),
              const SizedBox(height: 24),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _photo() {
    final preview = widget.item ?? InventoryItem(userid: widget.userid, kind: _kind, name: '', category: _category.text);
    return Center(
      child: Stack(children: [
        InkWell(
          onTap: _pickImage,
          borderRadius: BorderRadius.circular(28),
          child: InventoryThumb(item: preview, image: _imageFile, size: 112),
        ),
        Positioned(
          right: 0,
          bottom: 0,
          child: IconButton.filledTonal(
            tooltip: _imageFile == null ? 'Foto hinzufügen' : 'Foto ändern',
            onPressed: _pickImage,
            icon: Icon(_imageFile == null ? Icons.add_a_photo_outlined : Icons.edit_outlined, size: 18),
          ),
        ),
        if (_imageFile != null)
          Positioned(
            left: 0,
            bottom: 0,
            child: IconButton.filledTonal(
              tooltip: 'Foto entfernen',
              onPressed: () => setState(() {
                _imagePath = null;
                _imageFile = null;
              }),
              icon: const Icon(Icons.delete_outline, size: 18),
            ),
          ),
      ]),
    );
  }

  Widget _textCard(IconData icon, String label, TextEditingController c,
      {bool required = false, bool number = false, String? hint, int maxLines = 1}) {
    return FormFieldCard(
      icon: icon,
      label: label,
      child: TextFormField(
        controller: c,
        maxLines: maxLines,
        keyboardType: number ? const TextInputType.numberWithOptions(decimal: true) : null,
        decoration: bareInputDecoration.copyWith(hintText: hint),
        validator: required
            ? (v) => (v == null || v.trim().isEmpty) ? '$label erforderlich' : null
            : number
                ? (v) => (v == null || v.trim().isEmpty || _parse(v) != null) ? null : 'Zahl eingeben'
                : null,
      ),
    );
  }

  /// Textfeld mit antippbaren Vorschlägen.
  Widget _suggestCard(IconData icon, String label, TextEditingController c, List<String> suggestions) {
    return FormFieldCard(
      icon: icon,
      label: label,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        TextFormField(controller: c, decoration: bareInputDecoration.copyWith(hintText: 'Optional')),
        if (suggestions.isNotEmpty) ...[
          const SizedBox(height: 6),
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (final s in suggestions)
              ChoiceChip(
                label: Text(s, style: const TextStyle(fontSize: 12)),
                selected: c.text == s,
                visualDensity: VisualDensity.compact,
                onSelected: (_) => setState(() => c.text = s),
              ),
          ]),
        ],
      ]),
    );
  }
}
