import 'package:flutter/material.dart';
import 'package:frontend/core/ui/app_actions.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'package:frontend/core/ui/app_ui.dart';
import 'package:frontend/core/ui/modern_appbar.dart';
import 'package:frontend/features/finance/models/account.dart';
import 'package:frontend/features/finance/repositories/account_repository.dart';
import 'package:frontend/core/ui/form_widgets.dart';
import 'package:frontend/features/finance/widgets/transaction_form_fields.dart';

/// Konto anlegen oder bearbeiten. Gibt beim Schließen `true` zurück, wenn sich Daten geändert haben.
class AddUpdateAccount extends StatefulWidget {
  final int userid;
  final Account? account;
  const AddUpdateAccount({super.key, required this.userid, this.account});

  @override
  State<AddUpdateAccount> createState() => _AddUpdateAccountState();
}

class _AddUpdateAccountState extends State<AddUpdateAccount> {
  final _formKey = GlobalKey<FormState>();
  late final AccountRepository _accounts = context.read<AccountRepository>();

  late final TextEditingController _nameController;
  late final TextEditingController _iconController;
  late final TextEditingController _amountController;
  late int _codePoint;
  late String _fontFamily;
  bool _saving = false;

  bool get _isNew => widget.account == null;

  @override
  void initState() {
    super.initState();
    final a = widget.account;
    _nameController = TextEditingController(text: a?.accountName ?? '');
    _iconController = TextEditingController(text: a?.accountIconName ?? '');
    _amountController = TextEditingController(text: a?.accountAmount.toString() ?? '');
    _codePoint = a?.accountCodePoint ?? Icons.category.codePoint;
    _fontFamily = a?.accountFontFamily ?? 'MaterialIcons';
  }

  @override
  void dispose() {
    _nameController.dispose();
    _iconController.dispose();
    _amountController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    final navigator = Navigator.of(context);
    final account = Account(
      id: widget.account?.id,
      accountName: _nameController.text.trim(),
      accountCodePoint: _codePoint,
      accountFontFamily: _fontFamily,
      accountIconName: _iconController.text.isEmpty ? 'category' : _iconController.text,
      accountAmount: AmountField.parse(_amountController.text)!,
      accountUserid: widget.userid,
    );
    try {
      _isNew ? await _accounts.createAccount(account) : await _accounts.updateAccount(account);
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
    final a = widget.account;
    return Scaffold(
      appBar: ModernAppBar(title: _isNew ? 'Konto hinzufügen' : 'Konto bearbeiten'),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Form(
            key: _formKey,
            child: Column(children: [
              FormHeader(
                icon: Icons.account_balance_wallet,
                title: _isNew ? 'Neues Konto' : 'Konto bearbeiten',
                subtitle: _isNew ? 'Füge dein neues Konto hinzu' : 'Ändere vorhandenes Konto',
                bottom: a == null
                    ? null
                    : Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                        _headerValue('Kontoname', a.accountName, CrossAxisAlignment.start),
                        _headerValue('Kontostand', formatEuro(a.accountAmount, decimals: 2), CrossAxisAlignment.end),
                      ]),
              ),
              const SizedBox(height: 18),
              FormFieldCard(
                icon: Icons.wallet_outlined,
                label: 'Kontoname',
                child: TextFormField(
                  controller: _nameController,
                  decoration: bareInputDecoration,
                  validator: (v) => (v == null || v.trim().isEmpty) ? 'Kontoname erforderlich' : null,
                ),
              ),
              FormFieldCard(
                icon: Icons.attach_money_outlined,
                label: 'Kontostand',
                child: TextFormField(
                  controller: _amountController,
                  decoration: bareInputDecoration,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                  // Negativ erlaubt (z. B. Kreditkarte).
                  inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^-?\d*[.,]?\d{0,2}'))],
                  validator: (v) => AmountField.parse(v ?? '') == null ? 'Kontostand erforderlich' : null,
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

  Widget _headerValue(String label, String value, CrossAxisAlignment align) {
    return Column(crossAxisAlignment: align, children: [
      Text(label, style: const TextStyle(fontSize: 12)),
      const SizedBox(height: 4),
      Text(value, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
    ]);
  }
}
