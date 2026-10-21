import 'package:flutter/material.dart';

import 'package:frontend/core/ui/app_actions.dart';
import 'package:frontend/core/ui/app_ui.dart';
import 'package:frontend/features/lists/models/lists.dart';

/// Formular für einen Einkaufsartikel – beim Anlegen und Bearbeiten mit allen Feldern.
/// Liefert den Artikel (ohne Speichern) oder `null` bei Abbruch.
Future<ShoppingItem?> showShoppingItemSheet(BuildContext context, {required int userid, ShoppingItem? item}) =>
    showEditorSheet<ShoppingItem>(context, (_) => _ShoppingItemSheet(userid: userid, item: item));

/// Eingabe im Mengenfeld vereinheitlichen: „600g“ → „600 g“, „4x“/„4“ → „4×“.
String normalizeTypedQuantity(String typed) {
  final m = RegExp(r'^(\d+(?:[.,]\d+)?)\s*([^\d\s].*)?$').firstMatch(typed.trim());
  return m == null ? typed.trim() : normalizeQuantity(m.group(1)!, m.group(2)?.trim());
}

class _ShoppingItemSheet extends StatefulWidget {
  final int userid;
  final ShoppingItem? item;
  const _ShoppingItemSheet({required this.userid, this.item});

  @override
  State<_ShoppingItemSheet> createState() => _ShoppingItemSheetState();
}

class _ShoppingItemSheetState extends State<_ShoppingItemSheet> {
  final _formKey = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.item?.name);
  late final _amount = TextEditingController(text: widget.item?.quantityLabel);
  late ShoppingCategory _category = widget.item?.category ?? ShoppingCategory.food;
  late bool _categoryTouched = widget.item != null;

  @override
  void dispose() {
    _name.dispose();
    _amount.dispose();
    super.dispose();
  }

  void _nameChanged(String value) {
    if (_categoryTouched) return;
    final (name, _) = parseShoppingInput(value);
    setState(() => _category = ShoppingCategory.guess(name));
  }

  void _save() {
    if (!_formKey.currentState!.validate()) return;
    // Menge darf auch im Namen stehen: „600 g Magerquark“
    final (name, parsed) = parseShoppingInput(_name.text);
    final typed = _amount.text.trim();
    final text = typed.isEmpty ? parsed : normalizeTypedQuantity(typed);
    // Zahl mit Einheit → Menge (wird aufaddiert); sonst bleibt der Text als Notiz
    final amount = parseAmount(text);
    final old = widget.item;
    Navigator.of(context).pop(ShoppingItem(
      id: old?.id,
      userid: widget.userid,
      name: name,
      category: _category,
      quantity: amount == null ? text : (old?.quantity != null && parseAmount(old!.quantity) == null ? old.quantity : null),
      amount: amount?.$1,
      unit: amount == null ? old?.unit : amount.$2,
      foodId: old?.foodId,
      done: old?.done ?? false,
      doneAt: old?.doneAt,
      boughtAmount: old?.boughtAmount,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return EditorSheet(
      formKey: _formKey,
      title: widget.item == null ? 'Auf die Einkaufsliste' : 'Artikel bearbeiten',
      saveLabel: widget.item == null ? 'Hinzufügen' : 'Speichern',
      onSave: _save,
      children: [
        TextFormField(
          controller: _name,
          autofocus: widget.item == null,
          textInputAction: TextInputAction.next,
          decoration: const InputDecoration(labelText: 'Was?', hintText: 'z. B. Magerquark'),
          onChanged: _nameChanged,
          validator: (v) => (v ?? '').trim().isEmpty ? 'Bitte einen Artikel eingeben' : null,
        ),
        const SizedBox(height: 12),
        TextFormField(
          controller: _amount,
          textInputAction: TextInputAction.done,
          onFieldSubmitted: (_) => _save(),
          decoration: const InputDecoration(labelText: 'Menge (optional)', hintText: 'z. B. 600 g oder 4x'),
        ),
        const SizedBox(height: 16),
        Text('Abteilung', style: t.titleSmall),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final cat in ShoppingCategory.values)
            AppChip(
              label: cat.label,
              selected: cat == _category,
              onTap: () => setState(() {
                _category = cat;
                _categoryTouched = true;
              }),
            ),
        ]),
      ],
    );
  }
}
