import 'package:flutter/material.dart';
import 'package:frontend/core/ui/app_actions.dart';
import 'package:intl/intl.dart';
import 'package:frontend/features/finance/models/fixedtransaction.dart';
import 'package:frontend/features/auth/models/user.dart';
import 'package:frontend/features/finance/screens/add_update_fixedtransaction.dart';
import 'package:frontend/core/ui/app_ui.dart';
import 'package:frontend/features/finance/repositories/transaction_repository.dart';
import 'package:provider/provider.dart';
import 'package:frontend/core/ui/modern_appbar.dart';
import 'package:frontend/core/ui/theme.dart';

class FixedTransactionView extends StatefulWidget {
  const FixedTransactionView({super.key, required this.user});
  final UserModel user;

  @override
  State<FixedTransactionView> createState() => _FixedTransactionViewState();
}

class _FixedTransactionViewState extends State<FixedTransactionView> {
  AppColors get c => AppColors.of(context);

  late final TransactionRepository _repo = context.read<TransactionRepository>();
  late UserModel _user;

  late Future<List<FixedTransaction>> _fixedTransactionsFuture;

  @override
  void initState() {
    super.initState();
    _user = widget.user;
    _refreshList();
  }

  Future<void> _refreshList() async {
    setState(() {
      _fixedTransactionsFuture = _repo.getAllFixedTransactions(_user.uid);
    });
    try {
      await _fixedTransactionsFuture;
    } catch (_) {
      // Der FutureBuilder zeigt den Fehler mit „Erneut versuchen“ an
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return FutureBuilder<List<FixedTransaction>>(
      future: _fixedTransactionsFuture,
      builder: (context, snapshot) {
        return Scaffold(
          appBar: ModernAppBar(
            title: 'Wiederkehrende Transaktionen',
            user: _user,
            showLogout: true,
            onUserUpdated: (u) => setState(() => _user = u),
          ),
          body: snapshot.hasError
              ? EmptyState(
                  icon: Icons.cloud_off_rounded,
                  title: 'Laden fehlgeschlagen',
                  message: errorText(snapshot.error!),
                  action: OutlinedButton(onPressed: _refreshList, child: const Text('Erneut versuchen')),
                )
              : !snapshot.hasData
                  ? const Center(child: CircularProgressIndicator())
                  : snapshot.data!.isEmpty
                      ? _buildEmptyState(theme)
                      : RefreshIndicator(
                          color: c.accentText,
                          onRefresh: _refreshList,
                          child: _buildList(snapshot.data!, theme),
                        ),
          floatingActionButton: AppFab(label: 'Fixkosten', heroTag: 'fixed-fab', onPressed: () => _open()),
        );
      },
    );
  }

  Widget _buildEmptyState(ThemeData theme) {
    return const EmptyState(
      icon: Icons.autorenew_outlined,
      title: 'Noch keine Fixkosten',
      message: 'Miete, Gehalt, Abos – wiederkehrende Buchungen trägt LifeHub dann selbst ein.',
    );
  }

  Widget _buildList(List<FixedTransaction> list, ThemeData theme) {
    Map<String, List<FixedTransaction>> accountGroups = {};
    for (var ft in list) {
      accountGroups.putIfAbsent(ft.account, () => []).add(ft);
    }
    
    var sortedAccounts = accountGroups.keys.toList()..sort();

    return ListView.builder(
      padding: pagePadding(context),
      itemCount: sortedAccounts.length,
      itemBuilder: (ctx, i) {
        String accountName = sortedAccounts[i];
        List<FixedTransaction> accountTxs = accountGroups[accountName]!;
        
        double monthlyIncome = 0;
        double monthlyExpense = 0;
        for (var t in accountTxs) {
          double monthlyAmount = t.interval.monthlyEquivalent(t.amount);
          if (t.transactionType.isExpense) {
            monthlyExpense += monthlyAmount;
          } else {
            monthlyIncome += monthlyAmount;
          }
        }
        double monthlyBalance = monthlyIncome - monthlyExpense;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildAccountSummaryCard(accountName, monthlyIncome, monthlyExpense, monthlyBalance, theme),
            const SizedBox(height: 8),
            ...accountTxs.map((t) => _buildCard(t, theme)),
            const SizedBox(height: 16),
          ],
        );
      },
    );
  }

  Widget _buildAccountSummaryCard(String accountName, double income, double expense, double balance, ThemeData theme) {
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
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Icon(Icons.account_balance_wallet_outlined, color: c.accentText, size: 20),
              const SizedBox(width: 8),
              Text(accountName, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
              const Spacer(),
              Text('(ø pro Monat)', style: theme.textTheme.labelSmall?.copyWith(color: theme.hintColor)),
            ],
          ),
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

  Widget _buildCard(FixedTransaction ft, ThemeData theme) {
    final isExpense = ft.transactionType.isExpense;
    final color = isExpense ? c.negative : c.positive;
    final icon = isExpense ? Icons.arrow_downward_rounded : Icons.arrow_upward_rounded;
    final isOverdue = ft.nextTime.isBefore(DateTime.now());

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      child: SwipeTile(
          id: 'fixed-${ft.id}',
          onEdit: () => _open(ft),
          onDelete: () => _delete(ft),
        child: InkWell(
          onTap: () => _open(ft),
          borderRadius: BorderRadius.circular(16),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: isOverdue
                ? AppTheme.cardDecoration(context).copyWith(
                    border: Border.all(color: c.streak, width: 1.5),
                  )
                : AppTheme.cardDecoration(context),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(icon, color: color, size: 20),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(ft.category, style: theme.textTheme.titleSmall),
                          if (ft.description.isNotEmpty) ...[
                            const SizedBox(height: 2),
                            Text(ft.description, style: theme.textTheme.labelSmall, maxLines: 1, overflow: TextOverflow.ellipsis),
                          ],
                        ],
                      ),
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          formatEuro(isExpense ? -ft.amount : ft.amount, decimals: 2, sign: true),
                          style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: color),
                        ),
                        if (isOverdue)
                          Container(
                            margin: const EdgeInsets.only(top: 4),
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: c.streak.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text('Überfällig', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: c.streak)),
                          ),
                      ],
                    ),
                  ],
                ),
                Divider(color: c.line, height: 20),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    _chip(Icons.calendar_today_outlined, 'Nächste: ${DateFormat('dd.MM.yyyy').format(ft.nextTime)}', c.accentText),
                    _chip(Icons.repeat_outlined, ft.interval.label, c.accentText),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Icon(Icons.account_balance_wallet_outlined, size: 13, color: theme.textTheme.labelSmall?.color),
                    const SizedBox(width: 4),
                    Expanded(child: Text(ft.account, overflow: TextOverflow.ellipsis, style: theme.textTheme.labelSmall)),
                    const SizedBox(width: 8),
                    // Ohne Enddatum speichert die App den 01.01.2300 – das ist „unbegrenzt“
                    Text(ft.endTime.year >= 2300 ? 'unbegrenzt' : 'bis ${DateFormat('dd.MM.yyyy').format(ft.endTime)}',
                        style: theme.textTheme.labelSmall),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _chip(IconData icon, String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 4),
          Text(label, style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }

  Future<void> _open([FixedTransaction? ft]) async {
    final result = await Navigator.push<Object?>(
      context,
      MaterialPageRoute(builder: (_) => AddUpdateFixedTransaction(userid: _user.uid, fixedtransaction: ft)),
    );
    if (!mounted) return;
    if (result == kDeletedResult && ft != null) return _delete(ft);
    _refreshList();
  }

  Future<void> _delete(FixedTransaction ft) => deleteWithUndo(
        context,
        label: ft.description.isNotEmpty ? ft.description : ft.category,
        delete: () => _repo.deleteFixedTransaction(ft.id!),
        restore: () => _repo.restoreFixedTransaction(ft.id!),
        onChanged: _refreshList,
      );
}
