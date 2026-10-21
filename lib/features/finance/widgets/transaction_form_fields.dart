import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:frontend/features/finance/models/account.dart';
import 'package:frontend/features/finance/models/category.dart';
import 'package:frontend/features/finance/models/transaction_type.dart';
import 'package:frontend/core/ui/form_widgets.dart';

/// Was im Transaktionsformular erfasst wird. Eine Umbuchung wird als Ausgabe
/// + Einnahme gespeichert und hat deshalb keinen eigenen [TransactionType].
enum EntryKind {
  income('Einnahme'),
  expense('Ausgabe'),
  transfer('Umbuchung');

  const EntryKind(this.label);
  final String label;

  TransactionType? get type => switch (this) {
        income => TransactionType.income,
        expense => TransactionType.expense,
        transfer => null,
      };

  static EntryKind of(TransactionType type, {required bool isTransfer}) =>
      isTransfer ? transfer : (type.isIncome ? income : expense);
}

String? _required(String? v) => (v == null || v.isEmpty) ? 'Erforderlich' : null;

class EntryKindField extends StatelessWidget {
  final EntryKind value;
  final ValueChanged<EntryKind>? onChanged;

  const EntryKindField({super.key, required this.value, this.onChanged});

  @override
  Widget build(BuildContext context) {
    return FormFieldCard(
      icon: Icons.swap_vert,
      label: 'Transaktionstyp',
      child: DropdownButtonFormField<EntryKind>(
        isExpanded: true,
        value: value,
        decoration: bareInputDecoration,
        items: [for (final k in EntryKind.values) DropdownMenuItem(value: k, child: Text(k.label))],
        onChanged: onChanged == null ? null : (k) => onChanged!(k!),
      ),
    );
  }
}

class AmountField extends StatelessWidget {
  final TextEditingController controller;

  const AmountField({super.key, required this.controller});

  /// Akzeptiert Komma und Punkt als Dezimaltrenner.
  static double? parse(String text) => double.tryParse(text.trim().replaceAll(',', '.'));

  @override
  Widget build(BuildContext context) {
    return FormFieldCard(
      icon: Icons.attach_money,
      label: 'Betrag',
      child: TextFormField(
        controller: controller,
        decoration: bareInputDecoration,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d+[.,]?\d{0,2}'))],
        validator: (v) {
          final amount = parse(v ?? '');
          if (amount == null) return 'Betrag erforderlich';
          if (amount <= 0) return 'Betrag muss größer als 0 sein';
          return null;
        },
      ),
    );
  }
}

class CategoryField extends StatelessWidget {
  final List<Category> categories;
  final TransactionType type;
  final String? value;
  final ValueChanged<String?> onChanged;

  const CategoryField({
    super.key,
    required this.categories,
    required this.type,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final names = categories.where((c) => c.transactionType == type).map((c) => c.categoryName).toSet().toList();
    // Beim Bearbeiten kann die gespeicherte Kategorie inzwischen gelöscht sein.
    if (value != null && !names.contains(value)) names.add(value!);
    return FormFieldCard(
      icon: Icons.category,
      label: 'Kategorie',
      child: DropdownButtonFormField<String>(
        isExpanded: true,
        value: value,
        decoration: bareInputDecoration,
        items: [for (final n in names) DropdownMenuItem(value: n, child: Text(n))],
        onChanged: onChanged,
        validator: _required,
      ),
    );
  }
}

class AccountField extends StatelessWidget {
  final String label;
  final List<Account> accounts;
  final String? value;
  final String? exclude;
  final ValueChanged<String?> onChanged;

  const AccountField({
    super.key,
    this.label = 'Konto',
    required this.accounts,
    required this.value,
    required this.onChanged,
    this.exclude,
  });

  @override
  Widget build(BuildContext context) {
    final names = accounts.map((a) => a.accountName).where((n) => n != exclude).toSet().toList();
    return FormFieldCard(
      icon: Icons.account_balance_wallet,
      label: label,
      child: DropdownButtonFormField<String>(
        isExpanded: true,
        value: names.contains(value) ? value : null,
        decoration: bareInputDecoration,
        items: [for (final n in names) DropdownMenuItem(value: n, child: Text(n))],
        onChanged: onChanged,
        validator: _required,
      ),
    );
  }
}

class DescriptionField extends StatelessWidget {
  final TextEditingController controller;

  const DescriptionField({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    return FormFieldCard(
      icon: Icons.description,
      label: 'Beschreibung',
      child: TextFormField(controller: controller, decoration: bareInputDecoration),
    );
  }
}
