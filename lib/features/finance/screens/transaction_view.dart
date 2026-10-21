import 'package:flutter/material.dart';
import 'package:frontend/core/models/dates.dart';
import 'package:frontend/features/receipts/screens/receipt_review_screen.dart';
import 'package:frontend/core/ui/app_actions.dart';
import 'package:intl/intl.dart';
import 'package:frontend/features/finance/models/category.dart';
import 'package:frontend/features/finance/models/transaction.dart' as tr;
import 'package:frontend/features/finance/repositories/category_repository.dart';
import 'package:frontend/features/auth/models/user.dart';
import 'package:frontend/features/finance/screens/add_update_transactions.dart';
import 'package:frontend/core/ui/app_ui.dart';
import 'package:frontend/core/ui/dialogs.dart';
import 'package:frontend/features/finance/repositories/transaction_repository.dart';
import 'package:provider/provider.dart';
import 'package:frontend/core/ui/modern_appbar.dart';
import 'package:frontend/core/ui/theme.dart';

class TransactionView extends StatefulWidget {
  const TransactionView({super.key, required this.user});
  final UserModel user;

  @override
  State<TransactionView> createState() => _TransactionViewState();
}

class _TransactionViewState extends State<TransactionView> {
  AppColors get c => AppColors.of(context);

  late final TransactionRepository _repo = context.read<TransactionRepository>();
  late UserModel _user;

  late Future<List<tr.Transaction>> _transactionsFuture;
  Map<String, Category> _categoriesByName = {};

  @override
  void initState() {
    super.initState();
    _user = widget.user;
    _refreshTransactions();
  }

  Future<void> _refreshTransactions() async {
    final categoryRepo = context.read<CategoryRepository>();
    setState(() {
      _transactionsFuture = _repo.getAllTransactions(_user.uid);
    });
    try {
      final categories = await categoryRepo.getAllCategories(_user.uid);
      if (mounted) setState(() => _categoriesByName = {for (final c in categories) c.categoryName: c});
    } catch (_) {
      // Ohne Kategorien fehlen nur die Icons
    }
    try {
      await _transactionsFuture;
    } catch (_) {
      // Der FutureBuilder zeigt den Fehler mit „Erneut versuchen“ an
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return FutureBuilder<List<tr.Transaction>>(
      future: _transactionsFuture,
      builder: (context, snapshot) {
        return Scaffold(
          appBar: ModernAppBar(
            title: 'Transaktionen',
            user: _user,
            showLogout: true,
            onUserUpdated: (u) => setState(() => _user = u),
            customActions: [
              IconButton(
                icon: const Icon(Icons.document_scanner_outlined),
                tooltip: 'Kassenzettel fotografieren',
                onPressed: () => scanReceipt(context, userid: _user.uid, onSaved: _refreshTransactions),
              ),
              IconButton(
                icon: const Icon(Icons.delete_sweep_outlined),
                tooltip: 'Alle löschen',
                onPressed: _confirmDeleteAll,
              ),
            ],
          ),
          body: snapshot.hasError
              ? EmptyState(
                  icon: Icons.cloud_off_rounded,
                  title: 'Laden fehlgeschlagen',
                  message: errorText(snapshot.error!),
                  action: OutlinedButton(onPressed: _refreshTransactions, child: const Text('Erneut versuchen')),
                )
              : !snapshot.hasData
                  ? const Center(child: CircularProgressIndicator())
                  : snapshot.data!.isEmpty
                      ? _buildEmptyState(theme)
                      : RefreshIndicator(
                          color: c.accentText,
                          onRefresh: _refreshTransactions,
                          child: _buildTransactionList(snapshot.data!, theme),
                        ),
          floatingActionButton: AppFab(
            label: 'Buchung',
            heroTag: 'transaction-fab',
            onPressed: () => _navigateToAddUpdateTransaction(context, null),
          ),
        );
      },
    );
  }

  Widget _buildEmptyState(ThemeData theme) {
    return const EmptyState(
      icon: Icons.receipt_long_outlined,
      title: 'Noch keine Buchungen',
      message: 'Trag deine erste Einnahme oder Ausgabe ein.',
    );
  }

  Widget _buildTransactionList(List<tr.Transaction> transactions, ThemeData theme) {
    Map<String, List<tr.Transaction>> monthlyGroups = {};
    for (var t in transactions) {
      String monthKey = DateFormat('yyyy-MM').format(t.date);
      monthlyGroups.putIfAbsent(monthKey, () => []).add(t);
    }
    
    var sortedMonths = monthlyGroups.keys.toList()..sort((a, b) => b.compareTo(a));

    return ListView.builder(
      padding: pagePadding(context),
      itemCount: sortedMonths.length,
      itemBuilder: (context, monthIndex) {
        String monthKey = sortedMonths[monthIndex];
        List<tr.Transaction> monthTransactions = monthlyGroups[monthKey]!;
        
        double monthlyIncome = 0;
        double monthlyExpense = 0;
        for (var t in monthTransactions) {
          if (t.isTransfer) continue;
          if (t.transactionType.isExpense) {
            monthlyExpense += t.amount;
          } else {
            monthlyIncome += t.amount;
          }
        }
        double monthlyBalance = monthlyIncome - monthlyExpense;

        Map<String, List<tr.Transaction>> dailyGroups = {};
        for (var t in monthTransactions) {
          String dayKey = DateFormat('yyyy-MM-dd').format(t.date);
          dailyGroups.putIfAbsent(dayKey, () => []).add(t);
        }
        var sortedDays = dailyGroups.keys.toList()..sort((a, b) => b.compareTo(a));

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildMonthlySummaryCard(monthKey, monthlyIncome, monthlyExpense, monthlyBalance, theme),
            const SizedBox(height: 8),
            ...sortedDays.map((dayKey) {
              List<tr.Transaction> dayTxs = dailyGroups[dayKey]!;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                    child: Text(_formatDateHeader(dayKey), style: theme.textTheme.labelMedium),
                  ),
                  ...dayTxs.map((t) => _buildTransactionCard(t, theme)),
                  const SizedBox(height: 4),
                ],
              );
            }),
            const SizedBox(height: 16),
          ],
        );
      },
    );
  }

  Widget _buildMonthlySummaryCard(String monthKey, double income, double expense, double balance, ThemeData theme) {
    final DateTime monthDate = DateTime.parse('$monthKey-01');
    final String monthName = DateFormat('MMMM yyyy', 'de_DE').format(monthDate);
    final isPositive = balance >= 0;
    
    return Container(
      padding: const EdgeInsets.all(16),
      margin: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: theme.scaffoldBackgroundColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: theme.dividerColor.withValues(alpha: 0.5)),
        boxShadow: [BoxShadow(color: c.text.withValues(alpha: 0.03), blurRadius: 10, offset: const Offset(0, 4))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Übersicht $monthName', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _buildSummaryStat('Einnahmen', income, c.positive),
              _buildSummaryStat('Ausgaben', expense, c.negative),
              _buildSummaryStat('Bilanz', balance, isPositive ? c.positive : c.negative),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryStat(String label, double amount, Color color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(fontSize: 12, color: c.muted)),
        const SizedBox(height: 4),
        Text(formatEuro(amount, decimals: 2), style: TextStyle(fontWeight: FontWeight.bold, color: color)),
      ],
    );
  }

  String _formatDateHeader(String dateKey) {
    DateTime date = DateTime.parse(dateKey);
    DateTime now = DateTime.now();
    DateTime today = DateTime(now.year, now.month, now.day);
    DateTime yesterday = addDays(today, -1);
    if (date == today) return 'Heute';
    if (date == yesterday) return 'Gestern';
    return DateFormat('EEEE, d. MMMM yyyy', 'de_DE').format(date);
  }

  Widget _buildTransactionCard(tr.Transaction transaction, ThemeData theme) {
    final isExpense = transaction.transactionType.isExpense;
    final color = isExpense ? c.negative : c.positive;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      child: SwipeTile(
          id: 'transaction-${transaction.id}',
          onEdit: () => _navigateToAddUpdateTransaction(context, transaction),
          onDelete: () => _delete(transaction),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () => _navigateToAddUpdateTransaction(context, transaction),
            borderRadius: BorderRadius.circular(16),
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: AppTheme.cardDecoration(context),
              child: Row(
                children: [
                  Builder(builder: (context) {
                    final cat = _categoriesByName[transaction.category];
                    final icon = cat == null
                        ? Icons.category_outlined
                        : IconData(cat.categoryCodePoint, fontFamily: cat.categoryFontFamily);
                    return Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(icon, color: color, size: 22),
                    );
                  }),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(transaction.category, style: theme.textTheme.titleSmall),
                        if (transaction.description.isNotEmpty) ...[
                          const SizedBox(height: 3),
                          Text(
                            transaction.description,
                            style: theme.textTheme.labelSmall,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                        const SizedBox(height: 3),
                        Text(transaction.account, style: theme.textTheme.labelSmall),
                         if (transaction.imagePath != null) ...[
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              Icon(Icons.image_outlined, size: 12, color: theme.hintColor),
                              const SizedBox(width: 4),
                              Text('Bild angehängt', style: theme.textTheme.labelSmall?.copyWith(color: theme.hintColor, fontSize: 10)),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                  Text(
                    formatEuro(transaction.signedAmount, decimals: 2, sign: true),
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: color),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _delete(tr.Transaction transaction) => deleteWithUndo(
        context,
        label: transaction.description.isNotEmpty ? transaction.description : transaction.category,
        delete: () => _repo.deleteTransaction(transaction.id!),
        restore: () => _repo.restoreTransaction(transaction.id!),
        onChanged: _refreshTransactions,
      );

  Future<void> _navigateToAddUpdateTransaction(BuildContext context, tr.Transaction? transaction) async {
    final result = await Navigator.of(context).push<Object?>(
      MaterialPageRoute(builder: (_) => AddUpdateTransaction(userid: _user.uid, transaction: transaction)),
    );
    if (!mounted) return;
    if (result == kDeletedResult && transaction != null) return _delete(transaction);
    if (result != null) _refreshTransactions();
  }

  Future<void> _confirmDeleteAll() async {
    final deleted = await confirmAndDelete(
      context,
      title: 'Alle löschen',
      message: 'Wirklich ALLE Buchungen löschen? Die Kontostände werden entsprechend zurückgerechnet.',
      action: () => _repo.deleteAllTransactions(_user.uid),
      successMessage: 'Alle Transaktionen gelöscht',
    );
    if (deleted) _refreshTransactions();
  }
}
