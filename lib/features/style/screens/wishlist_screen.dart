import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'package:frontend/core/ui/app_actions.dart';
import 'package:frontend/core/ui/app_ui.dart';
import 'package:frontend/core/ui/form_widgets.dart';
import 'package:frontend/core/ui/modern_appbar.dart';
import 'package:frontend/core/ui/theme.dart';
import 'package:frontend/features/auth/models/user.dart';
import 'package:frontend/features/finance/models/transaction_type.dart';
import 'package:frontend/features/finance/repositories/account_repository.dart';
import 'package:frontend/features/finance/repositories/category_repository.dart';
import 'package:frontend/features/style/models/style.dart';
import 'package:frontend/features/style/repositories/style_repository.dart';
import 'package:frontend/features/style/widgets/style_widgets.dart';

/// Wunschliste mit Budget-Übersicht; „Gekauft“ bucht die Ausgabe und legt das Teil im Kleiderschrank an.
class WishlistScreen extends StatefulWidget {
  final UserModel user;
  const WishlistScreen({super.key, required this.user});

  @override
  State<WishlistScreen> createState() => _WishlistScreenState();
}

class _WishlistScreenState extends State<WishlistScreen> {
  late final StyleRepository _repo = context.read<StyleRepository>();
  List<WishlistItem>? _wishes;
  WishlistBudget? _budget;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final wishes = await _repo.getWishlist(widget.user.uid);
    final budget = await _repo.getBudget(widget.user.uid);
    if (!mounted) return;
    setState(() {
      _wishes = wishes;
      _budget = budget;
    });
  }

  Future<void> _edit([WishlistItem? wish]) async {
    final result = await Navigator.of(context).push<Object?>(
      MaterialPageRoute(builder: (_) => WishEditorScreen(userid: widget.user.uid, wish: wish)),
    );
    if (!mounted) return;
    if (result == kDeletedResult && wish != null) {
      await _delete(wish);
    } else if (result == true) {
      _load();
    }
  }

  Future<void> _buy(WishlistItem wish) async {
    final messenger = ScaffoldMessenger.of(context);
    final bought = await showDialog<bool>(
      context: context,
      builder: (_) => _BuyDialog(userid: widget.user.uid, wish: wish),
    );
    if (bought != true) return;
    messenger.showSnackBar(SnackBar(content: Text('„${wish.name}“ ist jetzt im Kleiderschrank')));
    _load();
  }

  Future<void> _delete(WishlistItem wish) => deleteWithUndo(
        context,
        label: wish.name,
        delete: () => _repo.deleteWish(wish.id!),
        restore: () => _repo.restoreWish(wish.id!),
        onChanged: _load,
      );

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final wishes = _wishes;
    final open = wishes?.where((w) => w.isOpen).toList() ?? const [];
    final bought = wishes?.where((w) => !w.isOpen).toList() ?? const [];
    return Scaffold(
      floatingActionButton: AppFab(
        heroTag: 'wishlist-fab',
        onPressed: wishes == null ? null : () => _edit(),
        label: 'Wunsch',
      ),
      body: wishes == null
          ? Center(child: CircularProgressIndicator(color: c.accent))
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: pagePadding(context),
                children: [
                  _budgetCard(context, _budget!),
                  const SizedBox(height: 20),
                  if (open.isEmpty)
                    const EmptyState(
                      icon: Icons.favorite_border_rounded,
                      title: 'Keine offenen Wünsche',
                      message: 'Sammle, was du dir kaufen möchtest – mit Preis und Link, gegen dein Kleidungsbudget.',
                    )
                  else ...[
                    SectionTitle('Offen', trailing: '${open.length}'),
                    for (final w in open) _wishTile(context, w),
                  ],
                  if (bought.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    SectionTitle('Gekauft', trailing: '${bought.length}'),
                    for (final w in bought) _wishTile(context, w),
                  ],
                ],
              ),
            ),
    );
  }

  Widget _budgetCard(BuildContext context, WishlistBudget b) {
    final c = AppColors.of(context);
    final t = Theme.of(context).textTheme;
    return AppCard(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(child: Text('Offene Wünsche', style: t.labelMedium)),
          Text(formatEuro(b.openSum, decimals: 2), style: t.titleLarge),
        ]),
        const SizedBox(height: 10),
        if (b.hasBudget) ...[
          AppProgressBar(
            value: b.monthlyBudget <= 0 ? 0 : b.spentThisMonth / b.monthlyBudget,
            color: b.remaining < 0 ? c.negative : c.accent,
          ),
          const SizedBox(height: 6),
          Text(
            'Budget „${b.category}“ diesen Monat: ${formatEuro(b.spentThisMonth, decimals: 2)} von ${formatEuro(b.monthlyBudget, decimals: 2)}'
            ' · ${b.remaining >= 0 ? 'noch ${formatEuro(b.remaining, decimals: 2)}' : '${formatEuro(-b.remaining, decimals: 2)} drüber'}',
            style: t.labelMedium?.copyWith(color: b.remaining < 0 ? c.negative : null),
          ),
        ] else
          Text('Tipp: Leg in den Finanzen ein Monatsbudget für „${b.category}“ fest, um es hier zu sehen.',
              style: t.labelMedium),
      ]),
    );
  }

  Widget _wishTile(BuildContext context, WishlistItem w) {
    final c = AppColors.of(context);
    final t = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: SwipeTile(
        id: 'wish-${w.id}',
        startAction: w.isOpen ? SwipeAction(label: 'Gekauft', icon: Icons.shopping_bag_rounded, onPressed: () => _buy(w)) : null,
        onEdit: () => _edit(w),
        onDelete: () => _delete(w),
        child: AppCard(
          onTap: () => _edit(w),
          padding: const EdgeInsets.all(12),
          child: Row(children: [
            StoredImage(path: w.imagePath, fallback: Icons.shopping_bag_outlined, size: 48),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(w.name, style: t.titleMedium, maxLines: 1, overflow: TextOverflow.ellipsis),
                Text(
                  [if (w.price != null) formatEuro(w.price!, decimals: 2), if (w.isOpen) w.priority.label else 'Gekauft'].join(' · '),
                  style: t.labelMedium?.copyWith(color: w.isOpen && w.priority == WishPriority.high ? c.streak : null),
                ),
              ]),
            ),
            if (w.isOpen) TextButton(onPressed: () => _buy(w), child: const Text('Gekauft')),
          ]),
        ),
      ),
    );
  }
}

/// Konto und Kategorie für den Kauf wählen.
class _BuyDialog extends StatefulWidget {
  final int userid;
  final WishlistItem wish;
  const _BuyDialog({required this.userid, required this.wish});

  @override
  State<_BuyDialog> createState() => _BuyDialogState();
}

class _BuyDialogState extends State<_BuyDialog> {
  late final _price = TextEditingController(
      text: widget.wish.price == null ? '' : widget.wish.price!.toStringAsFixed(2).replaceAll('.', ','));
  List<String>? _accounts;
  List<String> _categories = [];
  String? _account;
  String? _category;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _price.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final accounts = await context.read<AccountRepository>().getAllAccounts(widget.userid);
    if (!mounted) return;
    final categories = await context.read<CategoryRepository>().getAllCategories(widget.userid);
    if (!mounted) return;
    final names = categories.where((c) => c.transactionType == TransactionType.expense).map((c) => c.categoryName).toSet().toList();
    setState(() {
      _accounts = accounts.map((a) => a.accountName).toSet().toList();
      _account = _accounts!.firstOrNull;
      _categories = names;
      _category = names.contains(StyleRepository.clothingCategory) ? StyleRepository.clothingCategory : names.firstOrNull;
    });
  }

  Future<void> _confirm() async {
    final price = double.tryParse(_price.text.trim().replaceAll(',', '.'));
    if (price != null && price > 0 && (_account == null || _category == null)) {
      setState(() => _error = 'Für die Ausgabe werden Konto und Kategorie gebraucht.');
      return;
    }
    setState(() => _busy = true);
    final navigator = Navigator.of(context);
    await context.read<StyleRepository>().buy(
          widget.wish,
          account: _account ?? '',
          category: _category ?? StyleRepository.clothingCategory,
          price: price ?? 0,
        );
    navigator.pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final accounts = _accounts;
    return AlertDialog(
      title: Text('„${widget.wish.name}“ gekauft'),
      content: accounts == null
          ? const SizedBox(height: 80, child: Center(child: CircularProgressIndicator()))
          : SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                TextField(
                  controller: _price,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: 'Preis (€)', helperText: 'Leer lassen, um nichts zu buchen'),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: _account,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Konto'),
                  items: [for (final a in accounts) DropdownMenuItem(value: a, child: Text(a))],
                  onChanged: (v) => setState(() => _account = v),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: _category,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Kategorie'),
                  items: [for (final c in _categories) DropdownMenuItem(value: c, child: Text(c))],
                  onChanged: (v) => setState(() => _category = v),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 8),
                  Text(_error!, style: TextStyle(color: AppColors.of(context).negative)),
                ],
              ]),
            ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Abbrechen')),
        ElevatedButton(onPressed: accounts == null || _busy ? null : _confirm, child: const Text('Kauf buchen')),
      ],
    );
  }
}

/// Wunsch anlegen/bearbeiten. Gibt `true` zurück, wenn gespeichert/gelöscht.
class WishEditorScreen extends StatefulWidget {
  final int userid;
  final WishlistItem? wish;
  const WishEditorScreen({super.key, required this.userid, this.wish});

  @override
  State<WishEditorScreen> createState() => _WishEditorScreenState();
}

class _WishEditorScreenState extends State<WishEditorScreen> {
  final _formKey = GlobalKey<FormState>();
  late final StyleRepository _repo = context.read<StyleRepository>();
  late final _name = TextEditingController(text: widget.wish?.name ?? '');
  late final _price = TextEditingController(
      text: widget.wish?.price == null ? '' : widget.wish!.price!.toStringAsFixed(2).replaceAll('.', ','));
  late final _url = TextEditingController(text: widget.wish?.url ?? '');
  late WishPriority _priority = widget.wish?.priority ?? WishPriority.medium;
  late String? _imagePath = widget.wish?.imagePath;
  bool _saving = false;

  bool get _isNew => widget.wish == null;

  @override
  void dispose() {
    _name.dispose();
    _price.dispose();
    _url.dispose();
    super.dispose();
  }

  static double? _parse(String s) => double.tryParse(s.trim().replaceAll(',', '.'));

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    final navigator = Navigator.of(context);
    final old = widget.wish;
    await _repo.saveWish(WishlistItem(
      id: old?.id,
      userid: widget.userid,
      name: _name.text.trim(),
      price: _parse(_price.text),
      url: _url.text.trim().isEmpty ? null : _url.text.trim(),
      imagePath: _imagePath,
      priority: _priority,
      status: old?.status ?? WishStatus.open,
      boughtItemId: old?.boughtItemId,
    ));
    navigator.pop(true);
  }

  void _delete() => Navigator.of(context).pop(kDeletedResult);

  Future<void> _pickImage() async {
    final path = await pickStyleImage(context);
    if (path != null) setState(() => _imagePath = path);
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Scaffold(
      appBar: ModernAppBar(title: _isNew ? 'Neuer Wunsch' : 'Wunsch bearbeiten'),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(padding: const EdgeInsets.all(16), children: [
            Center(
              child: GestureDetector(
                onTap: _pickImage,
                child: StoredImage(path: _imagePath, fallback: Icons.add_a_photo_outlined, size: 96),
              ),
            ),
            const SizedBox(height: 16),
            FormFieldCard(
              icon: Icons.shopping_bag_outlined,
              label: 'Name',
              child: TextFormField(
                controller: _name,
                decoration: bareInputDecoration,
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Name erforderlich' : null,
              ),
            ),
            FormFieldCard(
              icon: Icons.euro_rounded,
              label: 'Preis',
              child: TextFormField(
                controller: _price,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: bareInputDecoration.copyWith(hintText: 'Optional'),
                validator: (v) => (v == null || v.trim().isEmpty || _parse(v) != null) ? null : 'Zahl eingeben',
              ),
            ),
            FormFieldCard(
              icon: Icons.link_rounded,
              label: 'Link',
              child: Row(children: [
                Expanded(
                  child: TextFormField(
                    controller: _url,
                    keyboardType: TextInputType.url,
                    decoration: bareInputDecoration.copyWith(hintText: 'Optional'),
                  ),
                ),
                IconButton(
                  tooltip: 'Link kopieren',
                  icon: const Icon(Icons.copy_rounded, size: 18),
                  onPressed: () => Clipboard.setData(ClipboardData(text: _url.text.trim())),
                ),
              ]),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 4, 4, 8),
              child: Text('Priorität', style: t.titleSmall),
            ),
            Wrap(spacing: 6, runSpacing: 6, children: [
              for (final p in WishPriority.values)
                AppChip(label: p.label, selected: _priority == p, onTap: () => setState(() => _priority = p)),
            ]),
            const SizedBox(height: 20),
            FormActions(isNew: _isNew, busy: _saving, onSave: _save, onDelete: _isNew ? null : _delete),
            const SizedBox(height: 24),
          ]),
        ),
      ),
    );
  }
}
