import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:frontend/core/ui/app_actions.dart';
import 'package:frontend/core/ui/form_widgets.dart';
import 'package:frontend/core/ui/modern_appbar.dart';
import 'package:frontend/core/ui/app_ui.dart';
import 'package:frontend/core/ui/theme.dart';
import 'package:frontend/features/fitness/models/nutrition.dart';
import 'package:frontend/features/fitness/repositories/nutrition_repository.dart';

/// Lebensmittel mit Nährwerten pro 100 g anlegen/bearbeiten. Gibt das gespeicherte [Food] zurück.
class FoodEditorScreen extends StatefulWidget {
  final int userid;
  final Food? food;

  /// Vorbelegung für neue Lebensmittel (z. B. Name oder Barcode).
  final Food? draft;

  /// Aus einem Foto erkannt: Vorschau und Hinweis oben (z. B. „Geschätzt aus dem Foto – bitte prüfen“).
  final Uint8List? photo;
  final String? photoHint;

  const FoodEditorScreen({super.key, required this.userid, this.food, this.draft, this.photo, this.photoHint});

  @override
  State<FoodEditorScreen> createState() => _FoodEditorScreenState();
}

class _FoodEditorScreenState extends State<FoodEditorScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name, _brand, _kcal, _protein, _carbs, _fat, _serving, _packs;
  bool _saving = false;

  bool get _isNew => widget.food == null;

  @override
  void initState() {
    super.initState();
    final f = widget.food ?? widget.draft;
    String n(double? v) => v == null || v == 0 ? '' : (v == v.roundToDouble() ? v.toInt().toString() : v.toString().replaceAll('.', ','));
    _name = TextEditingController(text: f?.name ?? '');
    _brand = TextEditingController(text: f?.brand ?? '');
    _kcal = TextEditingController(text: n(f?.per100.kcal));
    _protein = TextEditingController(text: n(f?.per100.protein));
    _carbs = TextEditingController(text: n(f?.per100.carbs));
    _fat = TextEditingController(text: n(f?.per100.fat));
    _serving = TextEditingController(text: n(f?.servingGrams));
    _packs = TextEditingController(text: f?.packSizes.map((p) => n(p)).join(', ') ?? '');
  }

  @override
  void dispose() {
    for (final c in [_name, _brand, _kcal, _protein, _carbs, _fat, _serving, _packs]) {
      c.dispose();
    }
    super.dispose();
  }

  static double? _parse(String s) => double.tryParse(s.trim().replaceAll(',', '.'));

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    final navigator = Navigator.of(context);
    final base = widget.food ?? widget.draft;
    final repo = context.read<NutritionRepository>();
    final saved = await runGuarded(context, () => repo.saveFood(Food(
          id: widget.food?.id,
          userid: widget.userid,
          name: _name.text.trim(),
          brand: _brand.text.trim().isEmpty ? null : _brand.text.trim(),
          barcode: base?.barcode,
          per100: Macros(
            kcal: _parse(_kcal.text) ?? 0,
            protein: _parse(_protein.text) ?? 0,
            carbs: _parse(_carbs.text) ?? 0,
            fat: _parse(_fat.text) ?? 0,
          ),
          servingGrams: _parse(_serving.text),
          packSizes: Food.parsePackSizes(_packs.text),
          isDish: base?.isDish ?? false,
        )));
    if (saved == null) {
      if (mounted) setState(() => _saving = false);
      return;
    }
    navigator.pop(saved);
  }

  Widget _number(IconData icon, String label, TextEditingController c, {bool required = false}) {
    return FormFieldCard(
      icon: icon,
      label: label,
      child: TextFormField(
        controller: c,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: bareInputDecoration.copyWith(hintText: required ? null : 'Optional'),
        validator: (v) {
          if ((v == null || v.trim().isEmpty)) return required ? '$label erforderlich' : null;
          return _parse(v) == null ? 'Zahl eingeben' : null;
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final barcode = (widget.food ?? widget.draft)?.barcode;
    return Scaffold(
      appBar: ModernAppBar(title: _isNew ? 'Neues Lebensmittel' : 'Lebensmittel bearbeiten'),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Form(
            key: _formKey,
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              if (widget.photo != null || widget.photoHint != null) _photoHeader(context),
              FormFieldCard(
                icon: Icons.restaurant_rounded,
                label: 'Name',
                child: TextFormField(
                  controller: _name,
                  decoration: bareInputDecoration,
                  validator: (v) => (v == null || v.trim().isEmpty) ? 'Name erforderlich' : null,
                ),
              ),
              FormFieldCard(
                icon: Icons.sell_outlined,
                label: 'Marke',
                child: TextFormField(controller: _brand, decoration: bareInputDecoration.copyWith(hintText: 'Optional')),
              ),
              if (barcode != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12, left: 4),
                  child: Text('Barcode $barcode', style: Theme.of(context).textTheme.labelMedium),
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 4, 4, 8),
                child: Text('Nährwerte pro 100 g', style: Theme.of(context).textTheme.titleSmall),
              ),
              _number(Icons.local_fire_department_outlined, 'Kalorien (kcal)', _kcal, required: true),
              _number(Icons.egg_outlined, 'Eiweiß (g)', _protein),
              _number(Icons.bakery_dining_outlined, 'Kohlenhydrate (g)', _carbs),
              _number(Icons.opacity_rounded, 'Fett (g)', _fat),
              _number(Icons.scale_rounded, 'Portion (g)', _serving),
              FormFieldCard(
                icon: Icons.inventory_2_outlined,
                label: 'Packungsgrößen (g bzw. ml)',
                child: TextFormField(
                  controller: _packs,
                  decoration: bareInputDecoration.copyWith(hintText: 'z. B. 400, 600'),
                ),
              ),
              const SizedBox(height: 8),
              FormActions(isNew: _isNew, busy: _saving, onSave: _save),
              const SizedBox(height: 24),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _photoHeader(BuildContext context) {
    final c = AppColors.of(context);
    final t = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: AppCard(
        color: c.streak.withValues(alpha: 0.10),
        padding: const EdgeInsets.all(10),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (widget.photo != null)
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Image.memory(widget.photo!, width: 72, height: 72, fit: BoxFit.cover, errorBuilder: (_, __, ___) => const SizedBox.square(dimension: 72)),
            ),
          if (widget.photo != null) const SizedBox(width: 12),
          Expanded(child: Text(widget.photoHint ?? 'Aus dem Foto erkannt – bitte prüfen.', style: t.bodySmall)),
        ]),
      ),
    );
  }
}
