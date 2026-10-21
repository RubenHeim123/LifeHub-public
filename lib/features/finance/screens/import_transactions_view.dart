import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:frontend/core/ui/app_actions.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:frontend/features/auth/models/user.dart';
import 'package:frontend/features/finance/repositories/account_repository.dart';
import 'package:frontend/features/finance/repositories/transaction_repository.dart';
import 'package:frontend/features/finance/services/import_service.dart';
import 'package:frontend/core/ui/app_ui.dart';
import 'package:frontend/core/ui/modern_appbar.dart';
import 'package:frontend/core/ui/theme.dart';

class ImportTransactionsView extends StatefulWidget {
  final UserModel user;
  const ImportTransactionsView({super.key, required this.user});

  @override
  State<ImportTransactionsView> createState() => _ImportTransactionsViewState();
}

class _ImportTransactionsViewState extends State<ImportTransactionsView> {
  AppColors get c => AppColors.of(context);

  final ImportService _importService = ImportService();
  late final TransactionRepository _transactionRepo = context.read<TransactionRepository>();
  late final AccountRepository _accountRepo = context.read<AccountRepository>();

  List<ImportedTransaction> _importedTransactions = [];
  BankProfile _selectedProfile = BankProfile.ing;
  String _selectedAccount = '';
  List<String> _accountNames = [];
  bool _isLoading = false;
  bool _hasFile = false;

  @override
  void initState() {
    super.initState();
    _loadAccounts();
  }

  Future<void> _loadAccounts() async {
    final accounts = await _accountRepo.getAllAccounts(widget.user.uid);
    if (!mounted) return;
    setState(() {
      _accountNames = accounts.map((a) => a.accountName).toSet().toList();
      if (_accountNames.isNotEmpty) _selectedAccount = _accountNames.first;
    });
  }

  Future<void> _pickAndParseFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['csv'],
    );
    if (result == null || result.files.single.path == null) return;
    setState(() => _isLoading = true);
    try {
      final file = File(result.files.single.path!);
      final transactions = await _importService.parseFile(file, profile: _selectedProfile);
      if (!mounted) return;
      setState(() { _importedTransactions = transactions; _hasFile = true; });
      final skipped = _importService.skippedRows;
      if (skipped > 0) {
        showAppSnack(context, '$skipped ${skipped == 1 ? 'Zeile' : 'Zeilen'} mit unlesbarem Datum oder Betrag übersprungen');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(errorText(e)), backgroundColor: c.negative),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _importTransactions() async {
    if (_importedTransactions.isEmpty || _selectedAccount.isEmpty) return;
    setState(() => _isLoading = true);
    try {
      final all = [for (final imported in _importedTransactions) imported.toTransaction(userid: widget.user.uid, account: _selectedAccount)];
      await _transactionRepo.createTransactions(all);
      final count = all.length;
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$count Transaktionen importiert!'), backgroundColor: c.positive),
        );
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Import fehlgeschlagen – es wurde nichts gebucht: ${errorText(e)}'), backgroundColor: c.negative),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: const ModernAppBar(title: 'CSV Import'),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Bank Format
              _sectionCard(
                context: context, theme: theme,
                icon: Icons.account_balance_outlined,
                title: 'Bank-Format',
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<BankProfile>(
                    value: _selectedProfile,
                    isExpanded: true,
                    items: const [
                      DropdownMenuItem(value: BankProfile.ing, child: Text('ING-DiBa')),
                      DropdownMenuItem(value: BankProfile.dkb, child: Text('DKB')),
                      DropdownMenuItem(value: BankProfile.c24, child: Text('C24 Bank')),
                      DropdownMenuItem(value: BankProfile.generic, child: Text('Generisch (Datum;Betrag;Empfänger;Beschreibung)')),
                    ],
                    onChanged: (v) { if (v != null) setState(() => _selectedProfile = v); },
                  ),
                ),
              ),
              const SizedBox(height: 12),
              // Target account
              if (_accountNames.isNotEmpty) ...[
                _sectionCard(
                  context: context, theme: theme,
                  icon: Icons.account_balance_wallet_outlined,
                  title: 'Ziel-Konto',
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: _selectedAccount,
                      isExpanded: true,
                      items: _accountNames.map((n) => DropdownMenuItem(value: n, child: Text(n))).toList(),
                      onChanged: (v) { if (v != null) setState(() => _selectedAccount = v); },
                    ),
                  ),
                ),
                const SizedBox(height: 12),
              ],
              // Upload button
              ElevatedButton.icon(
                onPressed: _isLoading ? null : _pickAndParseFile,
                icon: const Icon(Icons.upload_file_outlined),
                label: Text(_hasFile ? 'Andere Datei wählen' : 'CSV hochladen'),
              ),
              const SizedBox(height: 20),
              // Results
              if (_isLoading)
                Center(child: CircularProgressIndicator(color: c.accentText))
              else if (_importedTransactions.isNotEmpty) ...[
                _sectionCard(
                  context: context, theme: theme,
                  icon: Icons.preview_outlined,
                  title: 'Vorschau (${_importedTransactions.length} Transaktionen)',
                  child: SizedBox(
                    height: 400,
                    child: ListView.separated(
                      itemCount: _importedTransactions.length,
                      separatorBuilder: (_, __) => Divider(height: 1, color: c.line),
                      itemBuilder: (context, index) {
                        final tx = _importedTransactions[index];
                        final isIncome = tx.transactionType.isIncome;
                        final color = isIncome ? c.positive : c.negative;
                        return ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: Container(
                            width: 36, height: 36,
                            decoration: BoxDecoration(
                              color: color.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Icon(isIncome ? Icons.arrow_downward_rounded : Icons.arrow_upward_rounded, color: color, size: 18),
                          ),
                          title: Text(tx.recipient,
                              style: theme.textTheme.titleSmall, overflow: TextOverflow.ellipsis),
                          subtitle: Text(
                            '${DateFormat('dd.MM.yyyy').format(tx.date)} • ${tx.suggestedCategory}',
                            style: theme.textTheme.labelSmall,
                          ),
                          trailing: Text(
                            formatEuro(isIncome ? tx.amount.abs() : -tx.amount.abs(), decimals: 2, sign: true),
                            style: TextStyle(fontWeight: FontWeight.bold, color: color, fontSize: 13),
                          ),
                        );
                      },
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                ElevatedButton.icon(
                  onPressed: _isLoading ? null : _importTransactions,
                  icon: const Icon(Icons.check_circle_outline),
                  label: Text('${_importedTransactions.length} Transaktionen importieren'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: c.positive,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              ] else if (_hasFile)
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: AppTheme.cardDecoration(context),
                  child: Text('Keine Transaktionen in der Datei gefunden.', style: theme.textTheme.bodySmall, textAlign: TextAlign.center),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sectionCard({
    required BuildContext context,
    required ThemeData theme,
    required IconData icon,
    required String title,
    required Widget child,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: AppTheme.cardDecoration(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(
                  color: c.accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, color: c.accentText, size: 18),
              ),
              const SizedBox(width: 10),
              Text(title, style: theme.textTheme.titleSmall),
            ],
          ),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }
}
