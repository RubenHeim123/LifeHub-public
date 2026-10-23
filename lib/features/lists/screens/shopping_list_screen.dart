import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:frontend/core/ui/app_actions.dart';
import 'package:frontend/core/ui/app_ui.dart';
import 'package:frontend/core/ui/theme.dart';
import 'package:frontend/features/auth/models/user.dart';
import 'package:frontend/features/lists/models/lists.dart';
import 'package:frontend/features/lists/repositories/lists_repository.dart';
import 'package:frontend/features/lists/widgets/shopping_detail_sheet.dart';
import 'package:frontend/features/lists/widgets/shopping_item_sheet.dart';
import 'package:frontend/features/receipts/widgets/missing_receipt_banner.dart';

/// Einkaufsliste als eine einfache Liste: Artikel mit Menge (z. B. „600 g Magerquark“, „4× Deo“)
/// eintragen und abhaken. Gekauftes lässt sich direkt in Vorrat, Kleiderschrank oder Pflege übernehmen.
class ShoppingListScreen extends StatefulWidget {
  final UserModel user;
  const ShoppingListScreen({super.key, required this.user});

  @override
  State<ShoppingListScreen> createState() => _ShoppingListScreenState();
}

class _ShoppingListScreenState extends State<ShoppingListScreen> {
  late final ListsRepository _repo = context.read<ListsRepository>();
  List<ShoppingItem>? _items;
  bool _showDone = false;

  /// Lässt den Kassenzettel-Hinweis nach jedem Laden neu nachsehen.
  int _revision = 0;

  int get _uid => widget.user.uid;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Map<int, List<double>> _packs = {};

  Future<void> _load() async {
    final items = await _repo.getShopping(_uid);
    final packs = await _repo.packSizes(_uid);
    if (mounted) {
      setState(() {
        _items = items;
        _packs = packs;
        _revision++;
      });
    }
  }

  /// Packungsgrößen des zugeordneten Lebensmittels, wenn die Menge in g/ml angegeben ist.
  List<double> _packsFor(ShoppingItem i) =>
      i.foodId == null || (i.unit != 'g' && i.unit != 'ml') ? const [] : (_packs[i.foodId] ?? const []);

  /// Antippen: Detailansicht (Aufteilung nach Rezepten, Lebensmittel, Packungen).
  Future<void> _open(ShoppingItem item) async {
    final action = await showShoppingDetail(context, item);
    if (!mounted) return;
    switch (action) {
      case ShoppingDetailAction.edit:
        await _edit(item);
      case ShoppingDetailAction.delete:
        await _delete(item);
      case null:
        _load();
    }
  }

  /// Neuer Artikel oder Bearbeiten – dasselbe Formular mit allen Feldern.
  Future<void> _edit([ShoppingItem? item]) async {
    final result = await showShoppingItemSheet(context, userid: _uid, item: item);
    if (result == null || !mounted) return;
    await runGuarded(context, () => _repo.saveShopping(result));
    _load();
  }

  Future<void> _delete(ShoppingItem item) => deleteWithUndo(
        context,
        label: item.name,
        delete: () => _repo.deleteShopping(item.id!),
        restore: () => _repo.restoreShopping(item.id!),
        onChanged: _load,
      );

  /// Abhaken: Ein Dialog fragt, was tatsächlich gekauft wurde (Packung, eigene Menge, Barcode) – danach
  /// liegt der Artikel direkt im Vorrat (Kleidung im Kleiderschrank). Wieder öffnen geht ohne Dialog.
  Future<void> _toggle(ShoppingItem item) async {
    if (item.done) {
      await _repo.toggleShopping(item);
      _load();
      return;
    }
    final result = await askBought(context, item);
    if (result == null || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    final id = await _buy(item, result);
    _load();
    if (id == null) return;
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(SnackBar(
      content: Text('„${item.name}“ ist jetzt im ${item.category.inventoryTarget}'
          '${result.amount == null ? '' : ' – ${formatAmount(result.amount!, result.unit)}'}'),
      action: SnackBarAction(
        label: 'Rückgängig',
        onPressed: () async {
          await _repo.undoMoveToInventory(item, id);
          _load();
        },
      ),
    ));
  }

  /// Abhaken mit dem Ergebnis des Dialogs und in den Vorrat legen. Liefert die Vorrats-ID.
  Future<int?> _buy(ShoppingItem item, BoughtResult r) async {
    int? id;
    await runGuarded(context, () async {
      final updated = await _repo.toggleShopping(item,
          bought: r.amount, boughtUnit: r.amount == null ? null : (r.unit,), barcode: r.barcode, foodId: r.foodId);
      id = await _repo.moveToInventory(updated);
      return true;
    });
    return id;
  }

  Future<void> _moveToInventory(ShoppingItem item) async {
    final messenger = ScaffoldMessenger.of(context);
    int? id;
    final ok = await runGuarded(context, () async {
      id = await _repo.moveToInventory(item);
      return true;
    });
    if (ok != true) return;
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(SnackBar(
        content: Text(id == null
            ? '„${item.name}“ ist schon im ${item.category.inventoryTarget}'
            : '„${item.name}“ ist jetzt im ${item.category.inventoryTarget}')));
    if (mounted) _load();
  }

  Future<void> _clearDone() async {
    final messenger = ScaffoldMessenger.of(context);
    final n = await _repo.clearDone(_uid);
    messenger.showSnackBar(SnackBar(content: Text('$n erledigte Artikel entfernt')));
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final items = _items;
    final open = items?.where((i) => !i.done).toList() ?? const <ShoppingItem>[];
    final done = items?.where((i) => i.done).toList() ?? const <ShoppingItem>[];
    return Scaffold(
      floatingActionButton: AppFab(label: 'Artikel', heroTag: 'shopping-fab', onPressed: () => _edit()),
      body: items == null
          ? Center(child: CircularProgressIndicator(color: c.accent))
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: pagePadding(context),
                children: [
                  MissingReceiptBanner(userid: _uid, revision: _revision),
                  if (open.isEmpty)
                    const EmptyState(
                      icon: Icons.shopping_cart_outlined,
                      title: 'Alles eingekauft',
                      message: 'Füge über „Artikel“ hinzu, was du brauchst – z. B. „600 g Magerquark“ oder „4x Deo“.',
                    ),
                  // Gleiche Lebensmittel als eine Zeile, nach Abteilung in Laufreihenfolge
                  for (final (aisle, groups) in _byAisle(groupShopping(open))) ...[
                    GroupLabel(aisle.label, trailing: '${groups.length}'),
                    AppCard(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      child: Column(children: [
                        for (final g in groups) g.items.length == 1 ? _tile(context, g.items.single) : _groupTile(context, g),
                      ]),
                    ),
                    const SizedBox(height: 12),
                  ],
                  if (done.isNotEmpty) ...[
                    Row(children: [
                      Expanded(
                        child: TextButton.icon(
                          style: TextButton.styleFrom(alignment: Alignment.centerLeft),
                          onPressed: () => setState(() => _showDone = !_showDone),
                          icon: Icon(_showDone ? Icons.expand_less_rounded : Icons.expand_more_rounded),
                          label: Text('Erledigt (${done.length})'),
                        ),
                      ),
                      TextButton(onPressed: _clearDone, child: const Text('Erledigte entfernen')),
                    ]),
                    if (_showDone)
                      AppCard(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        child: Column(children: [for (final i in done) _tile(context, i)]),
                      ),
                  ],
                ],
              ),
            ),
    );
  }

  static List<(ShoppingAisle, List<ShoppingGroup>)> _byAisle(List<ShoppingGroup> groups) {
    final out = <(ShoppingAisle, List<ShoppingGroup>)>[];
    for (final g in groups) {
      if (out.isEmpty || out.last.$1 != g.aisle) out.add((g.aisle, []));
      out.last.$2.add(g);
    }
    return out;
  }

  /// Ein Lebensmittel in mehreren Einheiten („2× + 200 g Zwiebeln“): Abhaken hakt alle ab,
  /// Antippen zeigt die einzelnen Mengen.
  Widget _groupTile(BuildContext context, ShoppingGroup g) {
    final c = AppColors.of(context);
    final t = Theme.of(context).textTheme;
    return SwipeTile(
      id: 'shop-group-${g.key}',
      onDelete: () => deleteWithUndo(
        context,
        label: g.name,
        delete: () async {
          for (final i in g.items) {
            await _repo.deleteShopping(i.id!);
          }
        },
        restore: () async {
          for (final i in g.items) {
            await _repo.restoreShopping(i.id!);
          }
        },
        onChanged: _load,
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 4),
        leading: AppCheck(checked: false, onTap: () => _toggleGroup(g)),
        title: Text.rich(
          TextSpan(children: [
            if (g.quantityLabel != null)
              TextSpan(text: '${g.quantityLabel}  ', style: TextStyle(fontWeight: FontWeight.w700, color: c.accentText)),
            TextSpan(text: g.name),
          ]),
          style: t.bodyLarge,
        ),
        subtitle: Text('${g.items.length} Mengen zusammengefasst', style: t.labelMedium),
        onTap: () => _openGroup(g),
      ),
    );
  }

  /// Gruppe abhaken: der Dialog kommt für jede Menge einzeln („Abbrechen“ hört auf).
  Future<void> _toggleGroup(ShoppingGroup g) async {
    for (final i in g.items.where((i) => !i.done)) {
      if (!mounted) break;
      final result = await askBought(context, i);
      if (result == null || !mounted) break;
      await _buy(i, result);
    }
    _load();
  }

  Future<void> _openGroup(ShoppingGroup g) async {
    final item = await showModalBottomSheet<ShoppingItem>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(title: Text(g.name, style: Theme.of(ctx).textTheme.titleMedium)),
          for (final i in g.items)
            ListTile(
              leading: const Icon(Icons.shopping_basket_outlined),
              title: Text(i.quantityLabel ?? i.name),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () => Navigator.pop(ctx, i),
            ),
        ]),
      ),
    );
    if (item != null && mounted) await _open(item);
  }

  Widget _tile(BuildContext context, ShoppingItem i) {
    final c = AppColors.of(context);
    final t = Theme.of(context).textTheme;
    return SwipeTile(
      id: 'shop-${i.id}',
      startAction: i.done
          ? SwipeAction(label: i.category.inventoryTarget, icon: Icons.move_to_inbox_rounded, onPressed: () => _moveToInventory(i))
          : null,
      onEdit: () => _edit(i),
      onDelete: () => _delete(i),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 4),
        leading: AppCheck(checked: i.done, onTap: () => _toggle(i)),
        title: Text.rich(
          TextSpan(children: [
            if (i.quantityLabel != null)
              TextSpan(
                text: '${i.quantityLabel}  ',
                style: TextStyle(fontWeight: FontWeight.w700, color: i.done ? c.muted : c.accentText),
              ),
            TextSpan(text: i.name),
          ]),
          style: t.bodyLarge?.copyWith(
            decoration: i.done ? TextDecoration.lineThrough : null,
            color: i.done ? c.muted : null,
          ),
        ),
        subtitle: _hint(i) == null ? null : Text(_hint(i)!, style: t.labelMedium),
        onTap: () => _open(i),
      ),
    );
  }

  /// „Packungen: 1× 400 g + 1× 600 g“ bzw. beim Erledigten „Gekauft: 1 kg“.
  String? _hint(ShoppingItem i) {
    if (i.done) return i.boughtAmount == null ? null : 'Gekauft: ${formatAmount(i.boughtAmount!, i.unit)}';
    final packs = _packsFor(i);
    final plan = packs.isEmpty || i.amount == null ? const <(double, int)>[] : packPlan(i.amount!, packs);
    return plan.isEmpty ? null : 'Packungen: ${packPlanLabel(plan, i.unit!)}';
  }
}
