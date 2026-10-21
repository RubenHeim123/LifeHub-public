import 'package:flutter/material.dart';
import 'package:frontend/core/ui/app_actions.dart';
import 'package:frontend/core/ui/theme.dart';
import 'package:frontend/core/ui/app_ui.dart';
import 'package:frontend/core/ui/modern_appbar.dart';
import 'package:frontend/features/finance/repositories/account_repository.dart';
import 'package:frontend/features/finance/repositories/financial_goal_repository.dart';
import 'package:provider/provider.dart';
import 'package:frontend/features/finance/models/financial_goal.dart';
import 'package:frontend/features/auth/models/user.dart';
import 'package:frontend/features/finance/models/account.dart';
import 'package:frontend/features/finance/screens/add_update_financial_goal.dart';
import 'package:intl/intl.dart';

class FinancialGoalsView extends StatefulWidget {
  final UserModel user;
  const FinancialGoalsView({super.key, required this.user});

  @override
  State<FinancialGoalsView> createState() => _FinancialGoalsViewState();
}

class _FinancialGoalsViewState extends State<FinancialGoalsView> {
  late final FinancialGoalRepository _goalRepo = context.read<FinancialGoalRepository>();
  List<FinancialGoal> _goals = [];
  List<Account> _accounts = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    if (_goals.isEmpty) setState(() => _isLoading = true);
    final accountRepo = context.read<AccountRepository>();
    final goals = await _goalRepo.getAllGoals(widget.user.uid);
    final accounts = await accountRepo.getAllAccounts(widget.user.uid);
    if (!mounted) return;

    // Sort goals by deadline (soonest first)
    final dateFormat = DateFormat('dd.MM.yyyy');
    goals.sort((a, b) {
      final hasA = a.deadline != null && a.deadline!.isNotEmpty;
      final hasB = b.deadline != null && b.deadline!.isNotEmpty;
      if (!hasA && !hasB) return 0;
      if (!hasA) return 1;
      if (!hasB) return -1;
      final dateA = dateFormat.tryParse(a.deadline!);
      final dateB = dateFormat.tryParse(b.deadline!);
      if (dateA == null || dateB == null) return dateA == null ? 1 : -1;
      return dateA.compareTo(dateB);
    });

    setState(() {
      _goals = goals;
      _accounts = accounts;
      _isLoading = false;
    });
  }

  double _calculateCurrentAmount(FinancialGoal goal) {
    final linkedNames = goal.accountNames;
    double sum = 0;
    for (var acc in _accounts) {
      if (linkedNames.contains(acc.accountName)) {
        sum += acc.accountAmount;
      }
    }
    return sum;
  }

  static Color _goalColor(String hex) {
    final value = int.tryParse(hex.replaceFirst('#', ''), radix: 16);
    return value == null ? const Color(0xFF3498DB) : Color(0xFF000000 | value);
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final t = Theme.of(context).textTheme;
    return Scaffold(
      appBar: const ModernAppBar(title: 'Sparziele'),
      floatingActionButton: AppFab(label: 'Ziel', heroTag: 'goal-fab', onPressed: () => _open()),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _goals.isEmpty
              ? const EmptyState(
                  icon: Icons.flag_outlined,
                  title: 'Noch keine Sparziele',
                  message: 'Leg ein Ziel an und verknüpfe die Konten, auf denen du dafür sparst.',
                )
              : ListView.builder(
                  padding: EdgeInsets.fromLTRB(16, 12, 16, navClearance(context)),
                  itemCount: _goals.length,
                  itemBuilder: (context, index) {
                    final goal = _goals[index];
                    final current = _calculateCurrentAmount(goal);
                    // Ziel 0 € (alte Daten) ergäbe 0/0 = NaN und eine ungültige Balkenbreite
                    final progress = goal.targetAmount <= 0 ? 0.0 : (current / goal.targetAmount).clamp(0.0, 1.0);
                    final percent = (progress * 100).toStringAsFixed(0);
                    final color = _goalColor(goal.colorHex);

                    return Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: SwipeTile(
                        id: 'goal-${goal.id}',
                        onEdit: () => _open(goal),
                        onDelete: () => _delete(goal),
                        child: AppCard(
                          onTap: () => _open(goal),
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Row(children: [
                              Expanded(
                                child: Text(goal.name,
                                    maxLines: 2, overflow: TextOverflow.ellipsis, style: t.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                              ),
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(color: color.withValues(alpha: 0.18), borderRadius: BorderRadius.circular(20)),
                                child: Text('$percent %', style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 12)),
                              ),
                            ]),
                            if (goal.deadline != null && goal.deadline!.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: Text('bis ${goal.deadline}', style: t.bodySmall?.copyWith(color: c.muted)),
                              ),
                            const SizedBox(height: 12),
                            AppProgressBar(value: progress, color: color, height: 10),
                            const SizedBox(height: 12),
                            Row(children: [
                              Expanded(
                                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                  Text('Gespart', style: t.bodySmall?.copyWith(color: c.muted)),
                                  Text(formatEuro(current, decimals: 2), style: t.bodyLarge?.copyWith(fontWeight: FontWeight.bold)),
                                ]),
                              ),
                              Expanded(
                                child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                                  Text('Ziel', style: t.bodySmall?.copyWith(color: c.muted)),
                                  Text(formatEuro(goal.targetAmount, decimals: 2), style: t.bodyLarge?.copyWith(fontWeight: FontWeight.bold)),
                                ]),
                              ),
                            ]),
                          ]),
                        ),
                      ),
                    );
                  },
                ),
    );
  }

  Future<void> _open([FinancialGoal? goal]) async {
    final result = await Navigator.push<Object?>(
      context,
      MaterialPageRoute(builder: (_) => AddUpdateFinancialGoal(user: widget.user, goal: goal)),
    );
    if (!mounted) return;
    if (result == kDeletedResult && goal != null) return _delete(goal);
    _loadData();
  }

  Future<void> _delete(FinancialGoal goal) => deleteWithUndo(
        context,
        label: goal.name,
        delete: () => _goalRepo.deleteGoal(goal.id!),
        restore: () => _goalRepo.restoreGoal(goal.id!),
        onChanged: _loadData,
      );
}
