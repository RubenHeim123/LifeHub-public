import 'package:flutter/material.dart';
import 'package:frontend/core/ui/app_actions.dart';
import 'package:provider/provider.dart';

import 'package:frontend/core/ui/modern_appbar.dart';
import 'package:frontend/features/finance/models/category.dart';
import 'package:frontend/features/finance/models/transaction_type.dart';
import 'package:frontend/features/finance/repositories/category_repository.dart';
import 'package:frontend/core/ui/form_widgets.dart';
import 'package:frontend/features/finance/widgets/transaction_form_fields.dart';

/// Kategorie anlegen oder bearbeiten. Gibt beim Schließen `true` zurück, wenn sich Daten geändert haben.
class AddUpdateCategory extends StatefulWidget {
  final int userid;
  final Category? category;
  const AddUpdateCategory({super.key, required this.userid, this.category});

  @override
  State<AddUpdateCategory> createState() => _AddUpdateCategoryState();
}

class _AddUpdateCategoryState extends State<AddUpdateCategory> {
  final _formKey = GlobalKey<FormState>();
  late final CategoryRepository _categories = context.read<CategoryRepository>();

  late final TextEditingController _nameController;
  late final TextEditingController _iconController;
  late final TextEditingController _budgetController;
  TransactionType? _type;
  late int _codePoint;
  late String _fontFamily;
  bool _saving = false;

  bool get _isNew => widget.category == null;

  @override
  void initState() {
    super.initState();
    final c = widget.category;
    _nameController = TextEditingController(text: c?.categoryName ?? '');
    _iconController = TextEditingController(text: c?.categoryIconName ?? '');
    _budgetController = TextEditingController(text: c?.monthlyBudget.toString() ?? '');
    _type = c?.transactionType;
    _codePoint = c?.categoryCodePoint ?? Icons.category.codePoint;
    _fontFamily = c?.categoryFontFamily ?? 'MaterialIcons';
  }

  @override
  void dispose() {
    _nameController.dispose();
    _iconController.dispose();
    _budgetController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    final navigator = Navigator.of(context);
    final category = Category(
      id: widget.category?.id,
      categoryName: _nameController.text.trim(),
      categoryCodePoint: _codePoint,
      categoryFontFamily: _fontFamily,
      categoryIconName: _iconController.text.isEmpty ? 'category' : _iconController.text,
      transactionType: _type!,
      categoryUserid: widget.userid,
      monthlyBudget: AmountField.parse(_budgetController.text) ?? 0.0,
    );
    try {
      _isNew ? await _categories.createCategory(category) : await _categories.updateCategory(category);
      navigator.pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      showAppSnack(context, 'Speichern fehlgeschlagen: ${errorText(e)}', error: true);
    }
  }

  /// Die Liste löscht dann mit „Rückgängig“.
  void _delete() => Navigator.of(context).pop(kDeletedResult);

  @override
  Widget build(BuildContext context) {
    final c = widget.category;
    return Scaffold(
      appBar: ModernAppBar(title: _isNew ? 'Kategorie hinzufügen' : 'Kategorie bearbeiten'),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Form(
            key: _formKey,
            child: Column(children: [
              FormHeader(
                icon: Icons.category,
                title: _isNew ? 'Neue Kategorie' : 'Kategorie bearbeiten',
                subtitle: _isNew ? 'Füge eine neue Kategorie hinzu' : 'Ändere vorhandene Kategorie',
                trailing: c == null
                    ? null
                    : Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                        Text(c.categoryName, style: const TextStyle(fontWeight: FontWeight.w600)),
                        const SizedBox(height: 4),
                        Text(c.transactionType.label),
                      ]),
              ),
              const SizedBox(height: 18),
              FormFieldCard(
                icon: Icons.label,
                label: 'Kategoriename',
                child: TextFormField(
                  controller: _nameController,
                  decoration: bareInputDecoration,
                  validator: (v) => (v == null || v.trim().isEmpty) ? 'Kategoriename erforderlich' : null,
                ),
              ),
              FormFieldCard(
                icon: Icons.swap_vert,
                label: 'Transaktionstyp',
                child: DropdownButtonFormField<TransactionType>(
                  isExpanded: true,
                  value: _type,
                  decoration: bareInputDecoration,
                  items: [for (final t in TransactionType.values) DropdownMenuItem(value: t, child: Text(t.label))],
                  onChanged: (v) => setState(() => _type = v),
                  validator: (v) => v == null ? 'Erforderlich' : null,
                ),
              ),
              FormFieldCard(
                icon: Icons.account_balance_wallet,
                label: _type == TransactionType.income ? 'Erwartete Einnahmen (€)' : 'Monatliches Budget (€)',
                child: TextFormField(
                  controller: _budgetController,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: bareInputDecoration.copyWith(hintText: '0.0'),
                ),
              ),
              IconPickerField(
                controller: _iconController,
                onPicked: (codePoint, fontFamily) => setState(() {
                  _codePoint = codePoint;
                  _fontFamily = fontFamily;
                }),
              ),
              const SizedBox(height: 8),
              FormActions(isNew: _isNew, busy: _saving, onSave: _save, onDelete: _delete),
              const SizedBox(height: 24),
            ]),
          ),
        ),
      ),
    );
  }
}
