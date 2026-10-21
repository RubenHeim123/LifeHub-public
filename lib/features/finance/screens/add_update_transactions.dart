import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:frontend/core/ui/app_actions.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import 'package:frontend/core/ui/app_ui.dart';
import 'package:frontend/core/ui/modern_appbar.dart';
import 'package:frontend/core/ui/theme.dart';
import 'package:frontend/features/finance/models/account.dart';
import 'package:frontend/features/finance/models/category.dart';
import 'package:frontend/features/finance/models/transaction.dart' as tr;
import 'package:frontend/features/finance/models/transaction_type.dart';
import 'package:frontend/features/finance/repositories/account_repository.dart';
import 'package:frontend/features/finance/repositories/category_repository.dart';
import 'package:frontend/features/finance/repositories/transaction_repository.dart';
import 'package:frontend/core/ui/form_widgets.dart';
import 'package:frontend/features/finance/widgets/transaction_form_fields.dart';
import 'package:frontend/features/receipts/screens/receipt_review_screen.dart';
import 'package:frontend/features/receipts/services/receipt_scanner.dart';
import 'package:frontend/features/receipts/widgets/receipt_photo.dart';

/// Neue Transaktion/Umbuchung anlegen oder bestehende Transaktion bearbeiten.
/// Gibt beim Schließen `true` zurück, wenn sich Daten geändert haben.
class AddUpdateTransaction extends StatefulWidget {
  final int userid;
  final tr.Transaction? transaction;
  const AddUpdateTransaction({super.key, required this.userid, this.transaction});

  @override
  State<AddUpdateTransaction> createState() => _AddUpdateTransactionState();
}

class _AddUpdateTransactionState extends State<AddUpdateTransaction> {
  final _formKey = GlobalKey<FormState>();
  late final TransactionRepository _transactions;
  late final ReceiptImageStore _images;

  late final TextEditingController _amountController;
  late final TextEditingController _descriptionController;
  late EntryKind _kind;
  DateTime? _date;
  String? _category;
  String? _account;
  String? _targetAccount;
  String? _imagePath;
  bool _saving = false;

  /// Bilder, die nach dem Schließen verwaist sein können: das ursprüngliche und alle hier gewählten.
  final _imageCandidates = <String>{};

  List<Category> _categories = [];
  List<Account> _accounts = [];

  bool get _isNew => widget.transaction == null;

  @override
  void initState() {
    super.initState();
    // Hier holen, nicht erst bei Bedarf: dispose() braucht beide und darf den Context nicht mehr fragen.
    _transactions = context.read<TransactionRepository>();
    _images = context.read<ReceiptImageStore>();
    final t = widget.transaction;
    _amountController = TextEditingController(text: t?.amount.toString() ?? '');
    _descriptionController = TextEditingController(text: t?.description ?? '');
    // Beim Bearbeiten wird eine Umbuchungs-Hälfte wie eine normale Buchung behandelt.
    _kind = t == null ? EntryKind.expense : EntryKind.of(t.transactionType, isTransfer: false);
    _date = t?.date ?? DateTime.now();
    _category = t?.category;
    _account = t?.account;
    _imagePath = t?.imagePath;
    if (_imagePath != null) _imageCandidates.add(_imagePath!);
    _loadData();
  }

  Future<void> _loadData() async {
    final categoryRepo = context.read<CategoryRepository>();
    final accountRepo = context.read<AccountRepository>();
    final categories = await categoryRepo.getAllCategories(widget.userid);
    final accounts = await accountRepo.getAllAccounts(widget.userid);
    if (!mounted) return;
    setState(() {
      _categories = categories;
      _accounts = accounts;
    });
  }

  @override
  void dispose() {
    _amountController.dispose();
    _descriptionController.dispose();
    _removeUnusedImages(_transactions, _images, _imageCandidates);
    super.dispose();
  }

  /// Löscht ersetzte oder nach Abbrechen ungenutzte Bilder (nur die eigenen in `receipt_images/`).
  static Future<void> _removeUnusedImages(TransactionRepository repo, ReceiptImageStore images, Set<String> paths) async {
    for (final path in paths) {
      try {
        if (!await repo.isImageUsed(path)) await images.delete(path);
      } catch (_) {}
    }
  }

  Future<void> _pickImage() async {
    try {
      final result = await FilePicker.platform.pickFiles(type: FileType.image);
      final path = result?.files.single.path;
      if (path == null) return;
      // In den App-Ordner kopieren: Picker-Dateien im Cache kann das System löschen.
      final stored = await _images.importFile(path);
      _imageCandidates.add(stored);
      if (mounted) setState(() => _imagePath = stored);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Bildauswahl fehlgeschlagen: ${errorText(e)}')));
      }
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    final navigator = Navigator.of(context);
    final amount = AmountField.parse(_amountController.text)!;
    final description = _descriptionController.text;

    try {
      if (_kind == EntryKind.transfer) {
        await _transactions.createTransfer(
          userid: widget.userid,
          fromAccount: _account!,
          toAccount: _targetAccount!,
          amount: amount,
          date: _date!,
          description: description,
          imagePath: _imagePath,
        );
      } else {
        final transaction = tr.Transaction(
          id: widget.transaction?.id,
          date: _date!,
          amount: amount,
          category: _category!,
          description: description,
          account: _account!,
          transactionType: _kind.type!,
          userid: widget.userid,
          imagePath: _imagePath,
        );
        _isNew ? await _transactions.createTransaction(transaction) : await _transactions.updateTransaction(transaction);
      }
      navigator.pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Speichern fehlgeschlagen: ${errorText(e)}')));
    }
  }

  /// Die Liste löscht dann mit „Rückgängig“.
  void _delete() => Navigator.of(context).pop(kDeletedResult);

  @override
  Widget build(BuildContext context) {
    final t = widget.transaction;
    return Scaffold(
      appBar: ModernAppBar(title: _isNew ? 'Transaktion hinzufügen' : 'Transaktion bearbeiten'),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Form(
            key: _formKey,
            child: Column(children: [
              FormHeader(
                icon: Icons.swap_horiz,
                title: _isNew ? 'Neue Transaktion' : 'Transaktion bearbeiten',
                subtitle: _isNew ? 'Füge Einnahme / Ausgabe hinzu' : 'Ändere vorhandene Transaktion',
                trailing: t == null
                    ? null
                    : Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                        Text(DateFormat('dd.MM.yyyy').format(t.date), style: const TextStyle(fontWeight: FontWeight.w600)),
                        const SizedBox(height: 4),
                        Text(formatEuro(t.amount, decimals: 2)),
                      ]),
              ),
              const SizedBox(height: 18),
              EntryKindField(
                value: _kind,
                // Typ ist beim Bearbeiten fest: aus einer Buchung wird keine Umbuchung.
                onChanged: _isNew
                    ? (k) => setState(() {
                          _kind = k;
                          _category = null;
                          _targetAccount = null;
                        })
                    : null,
              ),
              DateField(label: 'Datum', value: _date, onChanged: (d) => setState(() => _date = d)),
              AmountField(controller: _amountController),
              if (_kind != EntryKind.transfer)
                CategoryField(
                  categories: _categories,
                  type: _kind.type!,
                  value: _category,
                  onChanged: (v) => setState(() => _category = v),
                ),
              AccountField(accounts: _accounts, value: _account, onChanged: (v) => setState(() => _account = v)),
              if (_kind == EntryKind.transfer)
                AccountField(
                  label: 'Zielkonto',
                  accounts: _accounts,
                  exclude: _account,
                  value: _targetAccount,
                  onChanged: (v) => setState(() => _targetAccount = v),
                ),
              DescriptionField(controller: _descriptionController),
              _imageCard(),
              const SizedBox(height: 8),
              FormActions(isNew: _isNew, busy: _saving, onSave: _save, onDelete: _delete),
              const SizedBox(height: 24),
            ]),
          ),
        ),
      ),
    );
  }

  bool get _canScanReceipt {
    final t = widget.transaction;
    return t != null && t.id != null && t.transactionType == TransactionType.expense && !t.isTransfer;
  }

  /// Bon zu dieser Buchung: erkennen, mit dem Einkauf vom selben Tag abgleichen und die Buchung ergänzen.
  Future<void> _scanReceipt() async {
    final navigator = Navigator.of(context);
    await scanReceipt(context, userid: widget.userid, existing: widget.transaction, onSaved: () => navigator.pop(true));
  }

  Widget _imageCard() {
    final c = AppColors.of(context);
    return FormFieldCard(
      icon: Icons.image,
      label: 'Bild (optional)',
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (_imagePath != null)
          Stack(children: [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: ReceiptPhoto(
                  path: _imagePath,
                  width: double.infinity,
                  height: 150,
                  placeholder: Container(
                    height: 150,
                    color: c.cardAlt,
                    alignment: Alignment.center,
                    child: Text('Bild nicht mehr vorhanden', style: TextStyle(color: c.muted)),
                  ),
                ),
              ),
            ),
            Positioned(
              right: 8,
              top: 16,
              child: GestureDetector(
                onTap: () => setState(() => _imagePath = null),
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(color: c.card, shape: BoxShape.circle),
                  child: Icon(Icons.close, size: 18, color: c.negative),
                ),
              ),
            ),
          ]),
        TextButton.icon(
          onPressed: _pickImage,
          icon: Icon(_imagePath == null ? Icons.add_a_photo : Icons.edit),
          label: Text(_imagePath == null ? 'Bild hinzufügen' : 'Bild ändern'),
        ),
        if (_canScanReceipt)
          TextButton.icon(
            onPressed: _scanReceipt,
            icon: const Icon(Icons.receipt_long_rounded),
            label: const Text('Kassenzettel scannen & abgleichen'),
          ),
      ]),
    );
  }
}
