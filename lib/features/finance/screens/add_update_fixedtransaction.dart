import 'package:flutter/material.dart';
import 'package:frontend/core/ui/app_actions.dart';
import 'package:provider/provider.dart';

import 'package:frontend/core/ui/modern_appbar.dart';
import 'package:frontend/features/finance/models/account.dart';
import 'package:frontend/features/finance/models/category.dart';
import 'package:frontend/features/finance/models/fixedtransaction.dart';
import 'package:frontend/features/finance/models/recurrence_interval.dart';
import 'package:frontend/features/finance/models/transaction_type.dart';
import 'package:frontend/features/finance/repositories/account_repository.dart';
import 'package:frontend/features/finance/repositories/category_repository.dart';
import 'package:frontend/features/finance/repositories/transaction_repository.dart';
import 'package:frontend/core/ui/form_widgets.dart';
import 'package:frontend/features/finance/widgets/transaction_form_fields.dart';

/// Wiederkehrende Transaktion/Umbuchung anlegen oder bearbeiten.
/// Gibt beim Schließen `true` zurück, wenn sich Daten geändert haben.
class AddUpdateFixedTransaction extends StatefulWidget {
  final int userid;
  final FixedTransaction? fixedtransaction;
  const AddUpdateFixedTransaction({super.key, required this.userid, this.fixedtransaction});

  @override
  State<AddUpdateFixedTransaction> createState() => _AddUpdateFixedTransactionState();
}

class _AddUpdateFixedTransactionState extends State<AddUpdateFixedTransaction> {
  final _formKey = GlobalKey<FormState>();
  late final TransactionRepository _transactions = context.read<TransactionRepository>();

  late final TextEditingController _amountController;
  late final TextEditingController _descriptionController;
  late EntryKind _kind;
  late RecurrenceInterval _interval;
  DateTime? _startDate;
  DateTime? _endDate;
  String? _category;
  String? _account;
  String? _targetAccount;
  bool _saving = false;

  List<Category> _categories = [];
  List<Account> _accounts = [];

  bool get _isNew => widget.fixedtransaction == null;

  /// Ohne Enddatum läuft eine Serie praktisch unbegrenzt.
  static final DateTime _openEnd = DateTime(2300, 12, 31);

  @override
  void initState() {
    super.initState();
    final ft = widget.fixedtransaction;
    _amountController = TextEditingController(text: ft?.amount.toString() ?? '');
    _descriptionController = TextEditingController(text: ft?.description ?? '');
    _kind = ft == null ? EntryKind.expense : EntryKind.of(ft.transactionType, isTransfer: false);
    _interval = ft?.interval ?? RecurrenceInterval.monthly;
    _startDate = ft?.startTime;
    _endDate = ft == null || !ft.endTime.isBefore(_openEnd) ? null : ft.endTime;
    _category = ft?.category;
    _account = ft?.account;
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
    super.dispose();
  }

  FixedTransaction _series({
    required String account,
    required String category,
    required TransactionType type,
    required String description,
    required DateTime nextTime,
    int? id,
  }) {
    return FixedTransaction(
      id: id,
      startTime: _startDate!,
      endTime: _endDate ?? _openEnd,
      nextTime: nextTime,
      interval: _interval,
      amount: AmountField.parse(_amountController.text)!,
      category: category,
      description: description,
      account: account,
      transactionType: type,
      userid: widget.userid,
    );
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    final navigator = Navigator.of(context);
    final description = _descriptionController.text;

    try {
      if (_isNew) {
        // nextTime = Startdatum: das Repository bucht dann alle schon fälligen Termine nach.
        final series = _kind == EntryKind.transfer
            ? [
                _series(
                  account: _account!,
                  category: kTransferCategory,
                  type: TransactionType.expense,
                  description: description.isEmpty ? 'Umbuchung an $_targetAccount' : description,
                  nextTime: _startDate!,
                ),
                _series(
                  account: _targetAccount!,
                  category: kTransferCategory,
                  type: TransactionType.income,
                  description: description.isEmpty ? 'Umbuchung von $_account' : description,
                  nextTime: _startDate!,
                ),
              ]
            : [
                _series(
                  account: _account!,
                  category: _category!,
                  type: _kind.type!,
                  description: description,
                  nextTime: _startDate!,
                ),
              ];
        await _transactions.createFixedTransactions(series);
      } else {
        // Bereits gebuchte Termine bleiben unverändert; weiter geht es mit dem nächsten künftigen Termin.
        await _transactions.updateFixedTransaction(_series(
          id: widget.fixedtransaction!.id,
          account: _account!,
          category: _category!,
          type: _kind.type!,
          description: description,
          nextTime: _nextFutureOccurrence(),
        ));
      }
      navigator.pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Speichern fehlgeschlagen: ${errorText(e)}')));
    }
  }

  DateTime _nextFutureOccurrence() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    var n = 0;
    var occ = _interval.occurrence(_startDate!, n);
    while (!occ.isAfter(today)) {
      occ = _interval.occurrence(_startDate!, ++n);
    }
    return occ;
  }

  /// Die Liste löscht dann mit „Rückgängig“.
  void _delete() => Navigator.of(context).pop(kDeletedResult);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: ModernAppBar(
        title: _isNew ? 'Wiederkehrende Transaktion hinzufügen' : 'Wiederkehrende Transaktion bearbeiten',
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Form(
            key: _formKey,
            child: Column(children: [
              FormHeader(
                icon: Icons.autorenew,
                title: _isNew ? 'Neue wiederkehrende Transaktion' : 'Wiederkehrende Transaktion bearbeiten',
                subtitle: _isNew ? 'Füge eine neue wiederkehrende Transaktion hinzu' : 'Ändere vorhandene Transaktion',
              ),
              const SizedBox(height: 18),
              if (_isNew)
                EntryKindField(
                  value: _kind,
                  onChanged: (k) => setState(() {
                    _kind = k;
                    _category = null;
                    _targetAccount = null;
                  }),
                ),
              AmountField(controller: _amountController),
              DateField(label: 'Startdatum', value: _startDate, onChanged: (d) => setState(() => _startDate = d)),
              DateField(
                label: 'Enddatum',
                value: _endDate,
                required: false,
                onChanged: (d) => setState(() => _endDate = d),
              ),
              FormFieldCard(
                icon: Icons.repeat,
                label: 'Intervall',
                child: DropdownButtonFormField<RecurrenceInterval>(
                  isExpanded: true,
                  value: _interval,
                  decoration: bareInputDecoration,
                  items: [for (final i in RecurrenceInterval.values) DropdownMenuItem(value: i, child: Text(i.label))],
                  onChanged: (v) => setState(() => _interval = v!),
                ),
              ),
              if (_kind != EntryKind.transfer)
                CategoryField(
                  categories: _categories,
                  type: _kind.type!,
                  value: _category,
                  onChanged: (v) => setState(() => _category = v),
                ),
              DescriptionField(controller: _descriptionController),
              AccountField(accounts: _accounts, value: _account, onChanged: (v) => setState(() => _account = v)),
              if (_kind == EntryKind.transfer)
                AccountField(
                  label: 'Zielkonto',
                  accounts: _accounts,
                  exclude: _account,
                  value: _targetAccount,
                  onChanged: (v) => setState(() => _targetAccount = v),
                ),
              const SizedBox(height: 8),
              FormActions(isNew: _isNew, busy: _saving, onSave: _save, onDelete: _delete),
              const SizedBox(height: 84),
            ]),
          ),
        ),
      ),
    );
  }
}
