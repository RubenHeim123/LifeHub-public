import 'package:flutter/material.dart';
import 'package:frontend/core/ui/app_actions.dart';
import 'package:frontend/core/ui/theme.dart';
import 'package:frontend/core/ui/app_ui.dart';
import 'package:frontend/core/ui/form_widgets.dart';
import 'package:frontend/core/ui/modern_appbar.dart';
import 'package:frontend/features/finance/repositories/account_repository.dart';
import 'package:frontend/features/finance/repositories/financial_goal_repository.dart';
import 'package:provider/provider.dart';
import 'package:frontend/features/finance/models/financial_goal.dart';
import 'package:frontend/features/auth/models/user.dart';
import 'package:frontend/features/finance/models/account.dart';
import 'package:intl/intl.dart';

class AddUpdateFinancialGoal extends StatefulWidget {
  final UserModel user;
  final FinancialGoal? goal;
  const AddUpdateFinancialGoal({super.key, required this.user, this.goal});

  @override
  State<AddUpdateFinancialGoal> createState() => _AddUpdateFinancialGoalState();
}

class _AddUpdateFinancialGoalState extends State<AddUpdateFinancialGoal> {
  late final FinancialGoalRepository _goals = context.read<FinancialGoalRepository>();
  final _formKey = GlobalKey<FormState>();

  late TextEditingController _nameController;
  late TextEditingController _amountController;
  DateTime? _deadline;
  bool _saving = false;

  String _selectedColorHex = '#3498db';
  late final List<String> _selectedAccountNames = [...?widget.goal?.accountNames];
  List<Account> _allAccounts = [];
  List<FinancialGoal> _allExistingGoals = [];
  bool _isLoading = true;

  final List<String> _premiumColors = [
    '#3498db', // Blue
    '#2ecc71', // Green
    '#e74c3c', // Red
    '#f1c40f', // Yellow
    '#9b59b6', // Purple
    '#e67e22', // Orange
    '#1abc9c', // Teal
    '#34495e', // Navy
  ];

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.goal?.name ?? '');
    _amountController = TextEditingController(text: widget.goal?.targetAmount.toString() ?? '');
    final deadline = widget.goal?.deadline;
    _deadline = deadline == null || deadline.isEmpty ? null : DateFormat('dd.MM.yyyy').tryParse(deadline);
    if (widget.goal != null) {
      _selectedColorHex = widget.goal!.colorHex;
    }
    _loadData();
  }

  Future<void> _loadData() async {
    final accountRepo = context.read<AccountRepository>();
    final accounts = await accountRepo.getAllAccounts(widget.user.uid);
    final goals = await _goals.getAllGoals(widget.user.uid);
    if (!mounted) return;
    setState(() {
      _allAccounts = accounts;
      _allExistingGoals = goals.where((g) => g.id != widget.goal?.id).toList();
      _isLoading = false;
    });
  }

  @override
  void dispose() {
    _nameController.dispose();
    _amountController.dispose();
    super.dispose();
  }

  String? _getCollisionGoal(String accountName) {
    for (var goal in _allExistingGoals) {
      if (goal.accountNames.contains(accountName)) {
        return goal.name;
      }
    }
    return null;
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedAccountNames.isEmpty) {
      showAppSnack(context, 'Bitte wähle mindestens ein Konto aus.', error: true);
      return;
    }

    final goal = FinancialGoal(
      id: widget.goal?.id,
      name: _nameController.text.trim(),
      targetAmount: double.parse(_amountController.text.trim().replaceAll(',', '.')),
      selectedAccountNames: _selectedAccountNames.join(', '),
      colorHex: _selectedColorHex,
      deadline: _deadline == null ? '' : DateFormat('dd.MM.yyyy').format(_deadline!),
      userid: widget.user.uid,
    );

    final navigator = Navigator.of(context);
    setState(() => _saving = true);
    final ok = await runGuarded(context, () async {
      if (widget.goal == null) {
        await _goals.createGoal(goal);
      } else {
        await _goals.updateGoal(goal);
      }
      return true;
    });
    if (!mounted) return;
    setState(() => _saving = false);
    if (ok == true) navigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final t = Theme.of(context).textTheme;
    final isNew = widget.goal == null;

    return Scaffold(
      appBar: ModernAppBar(title: isNew ? 'Neues Sparziel' : 'Sparziel bearbeiten'),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SafeArea(
              child: Form(
                key: _formKey,
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    FormFieldCard(
                      icon: Icons.flag_rounded,
                      label: 'Name',
                      child: TextFormField(
                        controller: _nameController,
                        autofocus: isNew,
                        decoration: bareInputDecoration.copyWith(hintText: 'z. B. Notgroschen'),
                        validator: (v) => v == null || v.trim().isEmpty ? 'Bitte Namen eingeben' : null,
                      ),
                    ),
                    FormFieldCard(
                      icon: Icons.euro_rounded,
                      label: 'Zielbetrag (€)',
                      child: TextFormField(
                        controller: _amountController,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: bareInputDecoration.copyWith(hintText: 'z. B. 3000'),
                        validator: (v) {
                          if (v == null || v.trim().isEmpty) return 'Bitte Betrag eingeben';
                          final value = double.tryParse(v.trim().replaceAll(',', '.'));
                          if (value == null) return 'Ungültiger Betrag';
                          if (value <= 0) return 'Das Ziel muss größer als 0 € sein';
                          return null;
                        },
                      ),
                    ),
                    DateField(
                      label: 'Ziel-Datum',
                      icon: Icons.event_rounded,
                      value: _deadline,
                      required: false,
                      firstDate: DateTime(2000),
                      onChanged: (d) => setState(() => _deadline = d),
                      onCleared: () => setState(() => _deadline = null),
                    ),
                    const GroupLabel('Farbe'),
                    Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: [
                        for (final hex in _premiumColors)
                          Semantics(
                            button: true,
                            selected: _selectedColorHex == hex,
                            child: GestureDetector(
                              onTap: () => setState(() => _selectedColorHex = hex),
                              child: Container(
                                width: 40,
                                height: 40,
                                decoration: BoxDecoration(
                                  color: Color(int.parse(hex.replaceFirst('#', '0xff'))),
                                  shape: BoxShape.circle,
                                  border: _selectedColorHex == hex ? Border.all(color: c.text, width: 3) : null,
                                ),
                                child: _selectedColorHex == hex ? const Icon(Icons.check, color: Colors.white, size: 20) : null,
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    const GroupLabel('Konten verknüpfen'),
                    Text('Das Guthaben dieser Konten zählt für das Ziel.', style: t.bodySmall?.copyWith(color: c.muted)),
                    const SizedBox(height: 8),
                    if (_allAccounts.isEmpty)
                      AppCard(child: Text('Noch keine Konten – leg zuerst ein Konto an.', style: t.bodySmall)),
                    for (final acc in _allAccounts) _accountTile(context, acc),
                    const SizedBox(height: 24),
                    FormActions(
                      isNew: isNew,
                      busy: _saving,
                      onSave: _save,
                      onDelete: () => Navigator.of(context).pop(kDeletedResult),
                    ),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _accountTile(BuildContext context, Account acc) {
    final c = AppColors.of(context);
    final collisionGoal = _getCollisionGoal(acc.accountName);
    final isSelected = _selectedAccountNames.contains(acc.accountName);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: AppCard(
        padding: EdgeInsets.zero,
        child: Column(children: [
          CheckboxListTile(
            title: Text(acc.accountName),
            subtitle: Text(formatEuro(acc.accountAmount, decimals: 2)),
            value: isSelected,
            activeColor: c.accent,
            onChanged: (val) => setState(() {
              if (val == true) {
                _selectedAccountNames.add(acc.accountName);
              } else {
                _selectedAccountNames.remove(acc.accountName);
              }
            }),
          ),
          if (isSelected && collisionGoal != null)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              color: c.streak.withValues(alpha: 0.12),
              child: Row(children: [
                Icon(Icons.warning_amber_rounded, color: c.streak, size: 16),
                const SizedBox(width: 8),
                Expanded(
                  child: Text('Zählt auch für „$collisionGoal“.',
                      style: TextStyle(color: c.streak, fontSize: 12, fontWeight: FontWeight.bold)),
                ),
              ]),
            ),
        ]),
      ),
    );
  }
}
