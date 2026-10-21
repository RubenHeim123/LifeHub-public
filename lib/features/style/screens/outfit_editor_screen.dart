import 'package:flutter/material.dart';
import 'package:frontend/core/ui/app_actions.dart';
import 'package:provider/provider.dart';

import 'package:frontend/core/services/image_store.dart';
import 'package:frontend/core/ui/app_ui.dart';
import 'package:frontend/core/ui/form_widgets.dart';
import 'package:frontend/core/ui/modern_appbar.dart';
import 'package:frontend/core/ui/theme.dart';
import 'package:frontend/features/inventory/models/inventory_item.dart';
import 'package:frontend/features/inventory/repositories/inventory_repository.dart';
import 'package:frontend/features/style/models/style.dart';
import 'package:frontend/features/style/repositories/style_repository.dart';
import 'package:frontend/features/style/widgets/style_widgets.dart';

/// Outfit aus Kleidungsstücken zusammenstellen (Auswahl-Raster). Gibt `true` zurück, wenn gespeichert/gelöscht.
class OutfitEditorScreen extends StatefulWidget {
  final int userid;
  final Outfit? outfit;
  const OutfitEditorScreen({super.key, required this.userid, this.outfit});

  @override
  State<OutfitEditorScreen> createState() => _OutfitEditorScreenState();
}

class _OutfitEditorScreenState extends State<OutfitEditorScreen> {
  final _formKey = GlobalKey<FormState>();
  late final StyleRepository _repo = context.read<StyleRepository>();
  late final _name = TextEditingController(text: widget.outfit?.name ?? '');
  late final Set<int> _selected = {for (final i in widget.outfit?.items ?? const <InventoryItem>[]) i.id!};
  late String? _imagePath = widget.outfit?.imagePath;
  List<InventoryItem>? _clothing;
  String? _category;
  String? _error;
  bool _saving = false;

  bool get _isNew => widget.outfit == null;

  @override
  void initState() {
    super.initState();
    context
        .read<InventoryRepository>()
        .getItems(widget.userid, kinds: {InventoryKind.clothing, InventoryKind.accessory})
        .then((items) => mounted ? setState(() => _clothing = items) : null);
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    final path = await pickStyleImage(context);
    if (path != null) setState(() => _imagePath = path);
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selected.isEmpty) {
      setState(() => _error = 'Wähle mindestens ein Teil aus.');
      return;
    }
    setState(() => _saving = true);
    final navigator = Navigator.of(context);
    final images = context.read<InventoryImageStore>();
    final old = widget.outfit;
    await _repo.saveOutfit(Outfit(
      id: old?.id,
      userid: widget.userid,
      name: _name.text.trim(),
      imagePath: _imagePath,
      lastWornAt: old?.lastWornAt,
      wearCount: old?.wearCount ?? 0,
      items: [for (final i in _clothing!) if (_selected.contains(i.id)) i],
    ));
    if (old?.imagePath != null && old!.imagePath != _imagePath) await images.delete(old.imagePath);
    navigator.pop(true);
  }

  void _delete() => Navigator.of(context).pop(kDeletedResult);

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final t = Theme.of(context).textTheme;
    final clothing = _clothing;
    final categories = {for (final i in clothing ?? const <InventoryItem>[]) if (i.category != null) i.category!}.toList()..sort();
    final visible = clothing?.where((i) => _category == null || i.category == _category).toList();
    return Scaffold(
      appBar: ModernAppBar(title: _isNew ? 'Neues Outfit' : 'Outfit bearbeiten'),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(padding: const EdgeInsets.all(16), children: [
            Row(children: [
              GestureDetector(
                onTap: _pickImage,
                child: StoredImage(path: _imagePath, fallback: Icons.add_a_photo_outlined, size: 72),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FormFieldCard(
                  icon: Icons.checkroom_rounded,
                  label: 'Name',
                  child: TextFormField(
                    controller: _name,
                    decoration: bareInputDecoration.copyWith(hintText: 'z. B. Büro, Date, Sport'),
                    validator: (v) => (v == null || v.trim().isEmpty) ? 'Name erforderlich' : null,
                  ),
                ),
              ),
            ]),
            SectionTitle('Teile auswählen', trailing: _selected.isEmpty ? null : '${_selected.length} gewählt'),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(_error!, style: t.bodyMedium?.copyWith(color: c.negative)),
              ),
            if (categories.length > 1)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Wrap(spacing: 6, runSpacing: 6, children: [
                  AppChip(label: 'Alle', selected: _category == null, onTap: () => setState(() => _category = null)),
                  for (final cat in categories)
                    AppChip(label: cat, selected: _category == cat, onTap: () => setState(() => _category = cat)),
                ]),
              ),
            if (visible == null)
              Center(child: CircularProgressIndicator(color: c.accent))
            else if (clothing!.isEmpty)
              Text('Dein Kleiderschrank ist leer – leg dort zuerst Kleidung an.', style: t.bodyMedium?.copyWith(color: c.muted))
            else
              GridView.count(
                crossAxisCount: 3,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: 8,
                crossAxisSpacing: 8,
                childAspectRatio: 0.78,
                children: [for (final item in visible) _pickTile(context, item)],
              ),
            const SizedBox(height: 20),
            FormActions(isNew: _isNew, busy: _saving, onSave: _save, onDelete: _isNew ? null : _delete),
            const SizedBox(height: 24),
          ]),
        ),
      ),
    );
  }

  Widget _pickTile(BuildContext context, InventoryItem item) {
    final c = AppColors.of(context);
    final t = Theme.of(context).textTheme;
    final selected = _selected.contains(item.id);
    return GestureDetector(
      onTap: () => setState(() {
        selected ? _selected.remove(item.id) : _selected.add(item.id!);
        _error = null;
      }),
      child: Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: selected ? c.accent : Colors.transparent, width: 2),
        ),
        child: Column(children: [
          Expanded(
            child: Stack(fit: StackFit.expand, children: [
              StoredImage(path: item.imagePath, fallback: Icons.checkroom_rounded),
              if (selected)
                Positioned(
                  top: 4,
                  right: 4,
                  child: Icon(Icons.check_circle_rounded, color: c.accent),
                ),
            ]),
          ),
          const SizedBox(height: 4),
          Text(item.name, style: t.labelMedium, maxLines: 1, overflow: TextOverflow.ellipsis),
        ]),
      ),
    );
  }
}
