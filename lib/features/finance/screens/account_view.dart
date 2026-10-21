import 'package:flutter/material.dart';
import 'package:frontend/core/ui/app_actions.dart';
import 'package:frontend/features/finance/models/account.dart';
import 'package:frontend/features/auth/models/user.dart';
import 'package:frontend/features/finance/screens/add_update_account.dart';
import 'package:frontend/core/ui/app_ui.dart';
import 'package:frontend/features/finance/repositories/account_repository.dart';
import 'package:provider/provider.dart';
import 'package:frontend/core/ui/modern_appbar.dart';
import 'package:frontend/core/ui/theme.dart';

class AccountView extends StatefulWidget {
  const AccountView({super.key, required this.user});
  final UserModel user;

  @override
  State<AccountView> createState() => _AccountViewState();
}

class _AccountViewState extends State<AccountView> {
  AppColors get c => AppColors.of(context);

  late final AccountRepository _repo = context.read<AccountRepository>();
  late UserModel _user;

  late Future<List<Account>> _accountsFuture;

  @override
  void initState() {
    super.initState();
    _user = widget.user;
    _refreshAccounts();
  }

  Future<void> _refreshAccounts() async {
    setState(() {
      _accountsFuture = _repo.getAllAccounts(_user.uid);
    });
    try {
      await _accountsFuture;
    } catch (_) {
      // Der FutureBuilder zeigt den Fehler mit „Erneut versuchen“ an
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return FutureBuilder<List<Account>>(
      future: _accountsFuture,
      builder: (context, snapshot) {
        return Scaffold(
          appBar: ModernAppBar(
            title: 'Konten',
            user: _user,
            showLogout: true,
            onUserUpdated: (u) => setState(() => _user = u),
          ),
          body: snapshot.hasError
              ? EmptyState(
                  icon: Icons.cloud_off_rounded,
                  title: 'Laden fehlgeschlagen',
                  message: errorText(snapshot.error!),
                  action: OutlinedButton(onPressed: _refreshAccounts, child: const Text('Erneut versuchen')),
                )
              : !snapshot.hasData
                  ? const Center(child: CircularProgressIndicator())
                  : snapshot.data!.isEmpty
                      ? _buildEmptyState(theme)
                      : RefreshIndicator(
                          color: c.accentText,
                          onRefresh: _refreshAccounts,
                          child: _buildAccountsList(snapshot.data!, theme),
                        ),
          floatingActionButton: AppFab(label: 'Konto', heroTag: 'account-fab', onPressed: () => _open()),
        );
      },
    );
  }

  Widget _buildEmptyState(ThemeData theme) {
    return const EmptyState(
      icon: Icons.account_balance_wallet_outlined,
      title: 'Noch keine Konten',
      message: 'Leg dein erstes Konto an, z. B. Girokonto oder Bargeld.',
    );
  }

  Widget _buildAccountsList(List<Account> accounts, ThemeData theme) {
    double totalAmount = accounts.fold(0, (sum, a) => sum + a.accountAmount);
    return Column(
      children: [
        // Total wealth card
        Container(
          width: double.infinity,
          margin: const EdgeInsets.all(16),
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(color: c.scoreCard, borderRadius: BorderRadius.circular(AppTheme.radiusCard)),
          child: Column(
            children: [
              Text('Gesamtvermögen', style: TextStyle(fontSize: 14, color: c.onScoreCardMuted)),
              const SizedBox(height: 8),
              Text(
                formatEuro(totalAmount, decimals: 2),
                style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: c.onScoreCard),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 16).copyWith(bottom: 100),
            itemCount: accounts.length,
            itemBuilder: (ctx, i) => _buildAccountCard(accounts[i], theme),
          ),
        ),
      ],
    );
  }

  Widget _buildAccountCard(Account account, ThemeData theme) {
    final isPositive = account.accountAmount >= 0;
    final amountColor = isPositive ? c.positive : c.negative;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      child: SwipeTile(
          id: 'account-${account.id}',
          onEdit: () => _open(account),
          onDelete: () => _delete(account),
        child: InkWell(
          onTap: () => _open(account),
          borderRadius: BorderRadius.circular(16),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: AppTheme.cardDecoration(context),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: c.accent.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    IconData(account.accountCodePoint, fontFamily: account.accountFontFamily),
                    color: c.accentText,
                    size: 26,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(account.accountName, style: theme.textTheme.titleMedium),
                      Text('Kontostand', style: theme.textTheme.labelSmall),
                    ],
                  ),
                ),
                Text(
                  formatEuro(account.accountAmount, decimals: 2),
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: amountColor),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _open([Account? account]) async {
    final result = await Navigator.push<Object?>(
      context,
      MaterialPageRoute(builder: (_) => AddUpdateAccount(userid: _user.uid, account: account)),
    );
    if (!mounted) return;
    if (result == kDeletedResult && account != null) return _delete(account);
    _refreshAccounts();
  }

  Future<void> _delete(Account account) => deleteWithUndo(
        context,
        label: account.accountName,
        delete: () => _repo.deleteAccount(account.id!),
        restore: () => _repo.restoreAccount(account.id!),
        onChanged: _refreshAccounts,
      );
}
