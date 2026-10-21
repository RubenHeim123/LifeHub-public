import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:frontend/app/app_tabs.dart';
import 'package:frontend/app/tab_style.dart';
import 'package:frontend/features/receipts/screens/receipt_review_screen.dart';
import 'package:frontend/features/receipts/widgets/missing_receipt_banner.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import 'package:frontend/core/ui/app_actions.dart';
import 'package:frontend/core/ui/app_ui.dart';
import 'package:frontend/core/ui/icon_collection.dart';
import 'package:frontend/core/ui/theme.dart';
import 'package:frontend/features/finance/widgets/category_bar_chart.dart';
import 'package:frontend/features/finance/widgets/category_pie_chart.dart';
import 'package:frontend/features/finance/models/category.dart';
import 'package:frontend/features/finance/models/transaction_type.dart';
import 'package:frontend/features/auth/models/user.dart';
import 'package:frontend/features/finance/repositories/account_repository.dart';
import 'package:frontend/features/finance/repositories/category_repository.dart';
import 'package:frontend/features/finance/repositories/transaction_repository.dart';
import 'package:frontend/features/finance/screens/account_view.dart';
import 'package:frontend/features/finance/screens/category_view.dart';
import 'package:frontend/features/finance/screens/financial_goals_view.dart';
import 'package:frontend/features/finance/screens/fixedtransaction_view.dart';
import 'package:frontend/features/finance/screens/transaction_view.dart';
import 'package:frontend/features/finance/services/budget_plan_service.dart';
import 'package:frontend/features/finance/services/prediction_service.dart';

class FinanceHubScreen extends StatefulWidget {
  final UserModel user;
  const FinanceHubScreen({super.key, required this.user});

  @override
  State<FinanceHubScreen> createState() => _FinanceHubScreenState();
}

class _FinanceHubScreenState extends State<FinanceHubScreen> {
  static const _allAccounts = PredictionService.allAccounts;
  static const _investmentCategory = 'Investition';

  late UserModel _user;
  bool _isLoading = true;

  int _selectedMonth = 0; // 0 = alle (letzte 12 Monate), 1–12 = Monat
  String _selectedAccount = _allAccounts;
  List<String> _accounts = [_allAccounts];

  double _income = 0, _expense = 0, _investments = 0, _monthlyBalance = 0;
  ForecastBreakdown? _forecast;
  // Schlüssel (Name, Typ): „Geschenke“ als Einnahme und als Ausgabe sind zwei Kategorien
  Map<(String, TransactionType), Category> _categoryMap = {};
  Map<(String, TransactionType), List<FlSpot>> _byCategory = {};
  BudgetPlan? _plan;

  /// Lässt den Kassenzettel-Hinweis nach jedem Laden neu nachsehen.
  int _revision = 0;

  @override
  void initState() {
    super.initState();
    _user = widget.user;
    _load();
  }

  /// Lädt alles; ein Fehler (z. B. beschädigte Daten) zeigt eine Meldung statt eines ewigen Ladekreises.
  Future<void> _load() async {
    try {
      await _loadData();
    } catch (e, s) {
      debugPrint('Laden fehlgeschlagen: $e $s');
      if (!mounted) return;
      setState(() => _isLoading = false);
      showAppSnack(context, 'Daten konnten nicht vollständig geladen werden: ${errorText(e)}', error: true);
    }
  }

  Future<void> _loadData() async {
    final transactionRepo = context.read<TransactionRepository>();
    final prediction = context.read<PredictionService>();
    final categoryRepo = context.read<CategoryRepository>();
    final accountRepo = context.read<AccountRepository>();
    final uid = _user.uid;
    final now = DateTime.now();

    final categories = await categoryRepo.getAllCategories(uid);
    final accounts = await accountRepo.getAllAccounts(uid);
    _categoryMap = {for (final c in categories) (c.categoryName, c.transactionType): c};
    final accNames = [_allAccounts, ...accounts.map((a) => a.accountName).where((n) => n.trim().isNotEmpty).toSet()];

    final transactions = await transactionRepo.getTransactionsSince(
      uid,
      DateTime(now.year, now.month - 11, 1),
      account: _selectedAccount == _allAccounts ? null : _selectedAccount,
      month: _selectedMonth == 0 ? null : _selectedMonth,
    );

    double income = 0, expense = 0, invest = 0, monthInc = 0, monthExp = 0;
    final sums = <(String, TransactionType), List<double>>{};
    final balanceMonth = _selectedMonth == 0 ? now.month : _selectedMonth;

    for (final t in transactions) {
      if (t.date.isAfter(now) || t.isTransfer) continue;
      final key = (t.category, t.transactionType);
      sums.putIfAbsent(key, () => List<double>.filled(12, 0));
      var amount = t.amount;
      if (t.category == _investmentCategory) {
        invest += t.amount;
      } else if (t.transactionType.isIncome) {
        income += t.amount;
        if (t.date.month == balanceMonth) monthInc += t.amount;
      } else {
        expense += t.amount;
        if (t.date.month == balanceMonth) monthExp += t.amount;
        amount = -amount;
      }
      final diff = (now.year - t.date.year) * 12 + now.month - t.date.month;
      final idx = 11 - diff;
      if (idx >= 0 && idx < 12) sums[key]![idx] += amount;
    }

    final forecast = await prediction.calculateEndOfMonthForecast(uid, accountName: _selectedAccount);

    // Monatsplanung für den gewählten (sonst den aktuellen) Monat – immer über alle Konten
    final planMonth = _selectedMonth == 0
        ? DateTime(now.year, now.month)
        : DateTime(_selectedMonth > now.month ? now.year - 1 : now.year, _selectedMonth);
    final plan = const BudgetPlanService().build(
      month: planMonth,
      categories: categories,
      fixed: await transactionRepo.getAllFixedTransactions(uid),
      transactions: await transactionRepo.getTransactionsSince(uid, planMonth),
    );

    if (!mounted) return;
    setState(() {
      _accounts = accNames;
      if (!_accounts.contains(_selectedAccount)) _selectedAccount = _allAccounts;
      _income = income;
      _expense = expense;
      _investments = invest;
      _monthlyBalance = monthInc - monthExp;
      _forecast = forecast;
      _plan = plan;
      _byCategory = sums.map((k, v) => MapEntry(k, List.generate(12, (i) => FlSpot(i.toDouble(), v[i]))));
      _isLoading = false;
      _revision++;
    });
  }

  String _monthName(int m) => m == 0 ? 'Alle Monate' : DateFormat('MMMM', 'de_DE').format(DateTime(2000, m));

  // ─── UI ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: _isLoading
            ? Center(child: CircularProgressIndicator(color: c.accent))
            : RefreshIndicator(
                color: c.accent,
                onRefresh: _load,
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: pagePadding(context),
                  children: [
                    _header(context),
                    const SizedBox(height: 18),
                    _balanceHero(context),
                    const SizedBox(height: 18),
                    _forecastCard(context),
                    const SizedBox(height: 10),
                    _stats(context),
                    const SizedBox(height: 24),
                    _expensePie(),
                    const SizedBox(height: 24),
                    _monthPlan(context),
                    const SizedBox(height: 24),
                    _categories(context),
                    const SizedBox(height: 24),
                    _manage(context),
                  ],
                ),
              ),
      ),
    );
  }

  Widget _header(BuildContext context) {
    return ScreenHeader(
      title: 'Finanzen',
      icon: AppTab.money.style.activeIcon,
      iconColor: AppTab.money.style.toneOf(context),
      actions: [
        PopupMenuButton<int>(
          tooltip: 'Monat',
          onSelected: (m) {
            setState(() => _selectedMonth = m);
            _load();
          },
          itemBuilder: (_) => List.generate(13, (i) => PopupMenuItem(value: i, child: Text(_monthName(i)))),
          child: IgnorePointer(child: AppChip(label: _monthName(_selectedMonth), trailingIcon: Icons.expand_more_rounded)),
        ),
        PopupMenuButton<String>(
          tooltip: 'Konto',
          onSelected: (a) {
            setState(() => _selectedAccount = a);
            _load();
          },
          itemBuilder: (_) =>
              _accounts.map((a) => PopupMenuItem(value: a, child: Text(a == _allAccounts ? 'Alle Konten' : a))).toList(),
          child: IgnorePointer(
            child: AppChip(
              label: _selectedAccount == _allAccounts ? 'Alle Konten' : _selectedAccount,
              trailingIcon: Icons.expand_more_rounded,
            ),
          ),
        ),
      ],
    );
  }

  Widget _balanceHero(BuildContext context) {
    final c = AppColors.of(context);
    final t = Theme.of(context).textTheme;
    final balance = _forecast?.currentBalance ?? 0;
    final full = formatEuro(balance, decimals: 2); // "8.412,50 €"
    final comma = full.lastIndexOf(',');
    final positive = _monthlyBalance >= 0;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('Gesamtbilanz', style: t.bodySmall),
      const SizedBox(height: 6),
      Text.rich(
        TextSpan(children: [
          TextSpan(text: comma > 0 ? full.substring(0, comma) : full),
          if (comma > 0) TextSpan(text: full.substring(comma), style: TextStyle(color: c.dim)),
        ]),
        style: t.displayLarge?.copyWith(height: 1, color: balance < 0 ? c.negative : c.text),
      ),
      const SizedBox(height: 8),
      Row(children: [
        Icon(positive ? Icons.trending_up_rounded : Icons.trending_down_rounded, size: 18, color: positive ? c.positive : c.negative),
        const SizedBox(width: 6),
        Text(
          '${formatEuro(_monthlyBalance, sign: true)} ${_selectedMonth == 0 ? 'diesen Monat' : 'im ${_monthName(_selectedMonth)}'}',
          style: TextStyle(fontSize: 13, color: positive ? c.positive : c.negative),
        ),
      ]),
    ]);
  }

  Widget _forecastCard(BuildContext context) {
    final c = AppColors.of(context);
    final t = Theme.of(context).textTheme;
    final f = _forecast;
    if (f == null) return const SizedBox.shrink();
    final plus = f.remainingFixedIncome + f.estimatedVariableIncome;
    final minus = f.remainingFixedExpenses + f.estimatedVariableExpenses;
    final base = f.currentBalance.abs();
    final sum = base + plus + minus;
    int flex(double v) => sum <= 0 ? 1 : ((v / sum) * 1000).round().clamp(1, 1000);
    final neutral = Theme.of(context).brightness == Brightness.dark ? const Color(0xFF3A3B40) : const Color(0xFFD9D9D5);

    Widget legend(Color col, String label) => Row(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 8, height: 8, decoration: BoxDecoration(color: col, shape: BoxShape.circle)),
          const SizedBox(width: 6),
          Text(label, style: t.labelMedium),
        ]);

    return AppCard(
      onTap: () => _showForecastDetails(context),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text('Prognose bis ${DateFormat('dd.MM.').format(f.targetDate)}', style: t.titleSmall)),
          Text(formatEuro(f.totalForecast), style: t.titleMedium),
          const SizedBox(width: 4),
          Icon(Icons.info_outline_rounded, size: 16, color: c.dim),
        ]),
        const SizedBox(height: 14),
        ClipRRect(
          borderRadius: BorderRadius.circular(5),
          child: SizedBox(
            height: 10,
            child: Row(children: [
              Expanded(flex: flex(base), child: ColoredBox(color: neutral)),
              const SizedBox(width: 3),
              Expanded(flex: flex(plus), child: ColoredBox(color: c.positive)),
              const SizedBox(width: 3),
              Expanded(flex: flex(minus), child: ColoredBox(color: c.negative)),
            ]),
          ),
        ),
        const SizedBox(height: 14),
        Wrap(spacing: 16, runSpacing: 6, children: [
          legend(neutral, 'Aktuell'),
          legend(c.positive, '+ Einnahmen ${formatEuro(plus)}'),
          legend(c.negative, '− Ausgaben ${formatEuro(minus)}'),
        ]),
      ]),
    );
  }

  Widget _stats(BuildContext context) {
    final c = AppColors.of(context);
    final t = Theme.of(context).textTheme;
    Widget stat(IconData icon, Color col, String label, double v) => Expanded(
          child: AppCard(
            radius: 20,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(icon, size: 20, color: col),
              const SizedBox(height: 8),
              Text(label, style: t.labelMedium?.copyWith(fontSize: 11)),
              const SizedBox(height: 4),
              FittedBox(fit: BoxFit.scaleDown, child: Text(formatEuro(v), style: t.titleMedium?.copyWith(fontSize: 16))),
            ]),
          ),
        );
    return Row(children: [
      stat(Icons.south_west_rounded, c.positive, 'Einnahmen', _income),
      const SizedBox(width: 8),
      stat(Icons.north_east_rounded, c.negative, 'Ausgaben', _expense),
      const SizedBox(width: 8),
      stat(Icons.savings_rounded, c.event, 'Investiert', _investments),
    ]);
  }

  Widget _expensePie() {
    final expenses = <String, double>{};
    _byCategory.forEach((key, spots) {
      if (key.$2 != TransactionType.expense) return;
      final total = spots.fold<double>(0, (sum, s) => sum + s.y.abs());
      if (total > 0) expenses[key.$1] = total;
    });
    return CategoryPieChart(categoryExpenses: expenses);
  }

  Widget _categories(BuildContext context) {
    final c = AppColors.of(context);
    final t = Theme.of(context).textTheme;
    final budgeted = {
      for (final b in _plan?.budgets ?? const <BudgetLine>[]) (b.category.categoryName, b.category.transactionType)
    };
    final names = _byCategory.keys.where((k) => !budgeted.contains(k)).toList()
      ..sort((a, b) {
        final ba = (_categoryMap[a]?.monthlyBudget ?? 0) > 0 ? 0 : 1;
        final bb = (_categoryMap[b]?.monthlyBudget ?? 0) > 0 ? 0 : 1;
        if (ba != bb) return ba.compareTo(bb);
        final byName = a.$1.compareTo(b.$1);
        return byName != 0 ? byName : a.$2.index.compareTo(b.$2.index);
      });

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const SectionTitle('Weitere Kategorien'),
      AppCard(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        child: names.isEmpty
            ? Padding(padding: const EdgeInsets.symmetric(vertical: 14), child: Text('Keine Kategorien verfügbar', style: t.bodySmall))
            : Column(
                children: names.asMap().entries.map((e) {
                  final key = e.value;
                  final name = key.$1;
                  final cat = _categoryMap[key];
                  final spots = _byCategory[key]!;
                  final thisMonth = spots[11].y.abs();
                  final budget = cat?.monthlyBudget ?? 0;
                  final isExpense = key.$2 == TransactionType.expense;
                  final ratio = budget > 0 ? thisMonth / budget : 0.0;
                  final bad = budget > 0 && (isExpense ? thisMonth > budget : thisMonth < budget);
                  final icon = iconCollection[cat?.categoryIconName] ?? Icons.category_outlined;
                  final barColor = bad ? c.negative : c.accentText;

                  return InkWell(
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => CategoryBarChart(
                          data: spots,
                          selectedCategory: name,
                          user: _user,
                          barColor: isExpense ? c.negative : c.positive,
                        ),
                      ),
                    ),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      decoration: BoxDecoration(border: e.key == 0 ? null : Border(top: BorderSide(color: c.line.withValues(alpha: 0.5)))),
                      child: Row(children: [
                        Hero(tag: 'cat_icon_${key.$2.dbValue}_$name', child: IconTile(icon: icon, color: c.text, background: c.cardAlt, iconSize: 20)),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Row(children: [
                              Expanded(child: Text(name, style: t.bodyLarge)),
                              Text.rich(
                                TextSpan(children: [
                                  TextSpan(text: formatEuro(thisMonth).replaceAll(' €', ''), style: TextStyle(color: bad ? c.negative : c.text)),
                                  TextSpan(text: budget > 0 ? ' / ${formatEuro(budget)}' : ' €', style: TextStyle(color: c.dim)),
                                ]),
                                style: const TextStyle(fontSize: 14),
                              ),
                            ]),
                            if (budget > 0) ...[
                              const SizedBox(height: 8),
                              AppProgressBar(value: ratio, color: barColor),
                            ] else
                              Text((isExpense ? TransactionType.expense : TransactionType.income).label, style: t.labelMedium?.copyWith(color: c.dim)),
                          ]),
                        ),
                      ]),
                    ),
                  );
                }).toList(),
              ),
      ),
    ]);
  }

  /// Monatsplanung: Was fest reinkommt und rausgeht, welche Budgets noch offen sind –
  /// und ob Budgets und Fixausgaben die Fixeinnahmen übersteigen.
  Widget _monthPlan(BuildContext context) {
    final c = AppColors.of(context);
    final t = Theme.of(context).textTheme;
    final plan = _plan;
    if (plan == null) return const SizedBox.shrink();
    final now = DateTime.now();
    final title = 'Monatsplanung ${DateFormat('MMMM', 'de_DE').format(plan.month)}';
    if (plan.isEmpty) {
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        SectionTitle(title),
        AppCard(
          child: Text('Lege Fixeinnahmen/-ausgaben und Monatsbudgets für Kategorien an – dann siehst du hier, '
              'was im Monat frei verfügbar bleibt.', style: t.bodySmall),
        ),
      ]);
    }

    Widget row(String label, double value, {Color? color, bool bold = false}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(children: [
            Expanded(child: Text(label, style: bold ? t.titleMedium : t.bodyMedium)),
            Text(formatEuro(value, decimals: 2, sign: !bold),
                style: (bold ? t.titleMedium : t.bodyMedium)?.copyWith(color: color, fontWeight: bold ? FontWeight.w700 : null)),
          ]),
        );

    Widget fixedList(String label, List<FixedLine> lines, bool income) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          GroupLabel(label, trailing: formatEuro(lines.fold(0.0, (s, l) => s + l.monthly), decimals: 2)),
          AppCard(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
            child: Column(children: [
              if (lines.isEmpty) Padding(padding: const EdgeInsets.symmetric(vertical: 12), child: Text('Keine', style: t.bodySmall)),
              for (final (i, l) in lines.indexed)
                Container(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  decoration: BoxDecoration(border: i == 0 ? null : Border(top: BorderSide(color: c.line.withValues(alpha: 0.5)))),
                  child: Row(children: [
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(l.name, style: t.bodyLarge, maxLines: 1, overflow: TextOverflow.ellipsis),
                        Text(
                          [
                            l.fixed.interval.label,
                            if (l.nextDue(now) != null) 'fällig am ${DateFormat('d.M.').format(l.nextDue(now)!)}'
                            else if (l.dueThisMonth.isNotEmpty) income ? 'eingegangen' : 'bezahlt',
                          ].join(' · '),
                          style: t.labelMedium,
                        ),
                      ]),
                    ),
                    Text(formatEuro(l.monthly, decimals: 2),
                        style: t.titleSmall?.copyWith(color: income ? c.positive : c.text)),
                  ]),
                ),
            ]),
          ),
          const SizedBox(height: 14),
        ]);

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      SectionTitle(title),
      AppCard(
        color: plan.overcommitted ? c.negative.withValues(alpha: 0.10) : null,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          row('Fixeinnahmen', plan.fixedIncomeTotal, color: c.positive),
          row('Fixausgaben', -plan.fixedExpenseTotal),
          row('Budgets', -plan.variableBudgetTotal),
          Divider(color: c.line),
          row('Frei verfügbar', plan.available, color: plan.overcommitted ? c.negative : c.positive, bold: true),
          if (plan.overcommitted) ...[
            const SizedBox(height: 8),
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(Icons.warning_amber_rounded, color: c.negative, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Budgets und Fixausgaben übersteigen deine Fixeinnahmen um ${formatEuro(-plan.available, decimals: 2)}.',
                  style: t.bodyMedium?.copyWith(color: c.negative),
                ),
              ),
            ]),
          ],
          if (plan.budgets.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text('Von den Budgets noch offen: ${formatEuro(plan.openBudgets, decimals: 2)}', style: t.labelMedium),
          ],
        ]),
      ),
      const SizedBox(height: 16),
      fixedList('Fixeinnahmen', plan.fixedIncome, true),
      fixedList('Fixausgaben', plan.fixedExpenses, false),
      GroupLabel('Budgets diesen Monat', trailing: 'offen ${formatEuro(plan.openBudgets, decimals: 2)}'),
      AppCard(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
        child: Column(children: [
          if (plan.budgets.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text('Noch keine Budgets – unter „Kategorien“ ein Monatsbudget festlegen.', style: t.bodySmall),
            ),
          for (final (i, b) in plan.budgets.indexed)
            InkWell(
              onTap: _byCategory[(b.category.categoryName, b.category.transactionType)] == null
                  ? null
                  : () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => CategoryBarChart(
                            data: _byCategory[(b.category.categoryName, b.category.transactionType)]!,
                            selectedCategory: b.category.categoryName,
                            user: _user,
                            barColor: c.negative,
                          ),
                        ),
                      ),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(border: i == 0 ? null : Border(top: BorderSide(color: c.line.withValues(alpha: 0.5)))),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Row(children: [
                    Expanded(child: Text(b.category.categoryName, style: t.bodyLarge)),
                    Text('${formatEuro(b.spent)} / ${formatEuro(b.planned)}',
                        style: t.bodyMedium?.copyWith(color: b.over ? c.negative : null)),
                  ]),
                  const SizedBox(height: 6),
                  AppProgressBar(value: b.planned <= 0 ? 0 : b.spent / b.planned, color: b.over ? c.negative : c.accentText),
                  const SizedBox(height: 4),
                  Text(
                    [
                      b.over ? '${formatEuro(-b.open, decimals: 2)} drüber' : 'noch offen: ${formatEuro(b.open, decimals: 2)}',
                      if (b.fixed > 0) 'davon fix ${formatEuro(b.fixed, decimals: 2)}',
                    ].join(' · '),
                    style: t.labelMedium?.copyWith(color: b.over ? c.negative : null),
                  ),
                ]),
              ),
            ),
        ]),
      ),
    ]);
  }

  Widget _manage(BuildContext context) {
    final c = AppColors.of(context);
    final t = Theme.of(context).textTheme;
    final items = <(IconData, String, String, Widget Function())>[
      (Icons.receipt_long_outlined, 'Transaktionen', 'Einnahmen und Ausgaben erfassen', () => TransactionView(user: _user)),
      (Icons.account_balance_outlined, 'Konten', 'Bankkonten und Bargeld', () => AccountView(user: _user)),
      (Icons.category_outlined, 'Kategorien', 'Budgets festlegen', () => CategoryView(user: _user)),
      (Icons.autorenew_rounded, 'Wiederkehrende Zahlungen', 'Abos und Daueraufträge', () => FixedTransactionView(user: _user)),
      (Icons.flag_outlined, 'Finanzielle Ziele', 'Sparziele planen', () => FinancialGoalsView(user: _user)),
    ];
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const SectionTitle('Verwalten'),
      AppCard(
        onTap: () => scanReceipt(context, userid: _user.uid, onSaved: _load),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(children: [
          IconTile(icon: Icons.document_scanner_outlined, color: c.accentText, iconSize: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Kassenzettel fotografieren', style: t.bodyLarge),
              Text('Buchung und Vorrat automatisch erkennen', style: t.labelMedium),
            ]),
          ),
          Icon(Icons.chevron_right_rounded, color: c.dim),
        ]),
      ),
      const SizedBox(height: 10),
      MissingReceiptBanner(userid: _user.uid, revision: _revision, onChanged: _load, bottomSpacing: 10),
      AppCard(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        child: Column(
          children: items.asMap().entries.map((e) {
            final (icon, title, sub, page) = e.value;
            return InkWell(
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => page())).then((_) => _load()),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(border: e.key == 0 ? null : Border(top: BorderSide(color: c.line.withValues(alpha: 0.5)))),
                child: Row(children: [
                  IconTile(icon: icon, color: c.text, background: c.cardAlt, iconSize: 20),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(title, style: t.bodyLarge),
                      Text(sub, style: t.labelMedium),
                    ]),
                  ),
                  Icon(Icons.chevron_right_rounded, color: c.dim),
                ]),
              ),
            );
          }).toList(),
        ),
      ),
    ]);
  }

  // ─── Prognose-Details (aus home.dart übernommen, neu gestylt) ───────────────

  void _showForecastDetails(BuildContext context) {
    final f = _forecast;
    if (f == null) return;
    final c = AppColors.of(context);
    final t = Theme.of(context).textTheme;

    Widget row(String label, double v, {bool bold = false, double size = 14, Color? color}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 5),
          child: Row(children: [
            Expanded(child: Text(label, style: TextStyle(fontSize: size, fontWeight: bold ? FontWeight.w600 : FontWeight.w400, color: c.text))),
            Text(formatEuro(v, decimals: 2, sign: true),
                style: TextStyle(fontSize: size, fontWeight: FontWeight.w600, color: color ?? (v >= 0 ? c.positive : c.negative))),
          ]),
        );

    String tip;
    if (f.totalForecast > f.currentBalance) {
      tip = 'Dein voraussichtliches Ergebnis liegt über deiner aktuellen Bilanz. Vielleicht möchtest du den Überschuss investieren?';
    } else if (f.totalForecast < f.currentBalance) {
      tip = 'Dein voraussichtliches Ergebnis liegt unter deiner aktuellen Bilanz. Prüfe deine variablen Ausgaben.';
    } else {
      tip = 'Erhöhe deine Fix-Einnahmen oder reduziere variable Kosten, um dein Ergebnis zu verbessern.';
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Center(
              child: Container(width: 40, height: 4, margin: const EdgeInsets.only(bottom: 20), decoration: BoxDecoration(color: c.line, borderRadius: BorderRadius.circular(2))),
            ),
            Text('So entsteht die Prognose', style: t.headlineMedium),
            const SizedBox(height: 8),
            Text(
              'Voraussichtlicher Stand zum ${DateFormat('d. MMMM', 'de_DE').format(f.targetDate)}. Variable Werte basieren auf deinem Durchschnitt der letzten 12 Monate.',
              style: t.bodySmall,
            ),
            const SizedBox(height: 20),
            row('Aktuelle Gesamtbilanz', f.currentBalance, bold: true, color: c.text),
            Divider(height: 24, color: c.line),
            row('Anstehende Fix-Einnahmen', f.remainingFixedIncome),
            row('Anstehende Fix-Ausgaben', -f.remainingFixedExpenses),
            row('Geschätzte variable Einnahmen', f.estimatedVariableIncome),
            row('Geschätzte variable Ausgaben', -f.estimatedVariableExpenses),
            Divider(height: 28, color: c.line),
            row('Voraussichtliches Ergebnis', f.totalForecast, bold: true, size: 17),
            const SizedBox(height: 20),
            AppCard(
              color: c.card,
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Icon(Icons.lightbulb_outline_rounded, size: 20, color: c.streak),
                const SizedBox(width: 12),
                Expanded(child: Text(tip, style: t.bodySmall?.copyWith(height: 1.4))),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}
