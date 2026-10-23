import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:frontend/core/services/image_store.dart';
import 'package:frontend/core/ui/app_actions.dart';
import 'package:frontend/core/ui/app_ui.dart';
import 'package:frontend/core/ui/theme.dart';
import 'package:frontend/features/auth/models/user.dart';
import 'package:frontend/features/inventory/models/inventory_item.dart';
import 'package:frontend/features/inventory/repositories/inventory_repository.dart';
import 'package:frontend/features/inventory/screens/item_editor_screen.dart';
import 'package:frontend/features/inventory/widgets/inventory_widgets.dart';

/// Inventar zum schnellen Finden und Verwalten – für den Vorrat (Essen, Getränke, Drogerie, Haushalt)
/// und den Kleiderschrank. Suche, Status-Chips mit Zählern, Filter, Sortierung,
/// Liste oder Raster, Wischgesten und Schnell-Hinzufügen.
class InventoryScreen extends StatefulWidget {
  final UserModel user;
  final Set<InventoryKind> kinds;

  /// Art für neue Einträge.
  final InventoryKind addKind;

  /// Wählbare Arten beim Hinzufügen (z. B. Kleidung, Accessoire, Pflege & Duft).
  final List<InventoryKind>? addKinds;
  final bool gridByDefault;

  /// Optional: Barcode scannen und daraus einen Entwurf machen (Vorrat).
  final Future<InventoryItem?> Function()? onScanBarcode;

  /// Kassenzettel fotografieren (Vorrat): Lebensmittel und Buchung erkennen.
  final Future<void> Function(VoidCallback onSaved)? onScanReceipt;

  const InventoryScreen({
    super.key,
    required this.user,
    required this.kinds,
    required this.addKind,
    this.addKinds,
    this.gridByDefault = false,
    this.onScanBarcode,
    this.onScanReceipt,
  });

  bool get isWardrobe => kinds.contains(InventoryKind.clothing);

  @override
  State<InventoryScreen> createState() => _InventoryScreenState();
}

class _InventoryScreenState extends State<InventoryScreen> {
  late final InventoryRepository _repo = context.read<InventoryRepository>();
  late final InventoryImageStore _images = context.read<InventoryImageStore>();
  final _search = TextEditingController();

  List<InventoryItem> _items = [];
  Map<int, File> _imageFiles = {};
  bool _loading = true;
  late bool _grid = widget.gridByDefault;
  late InventoryQuery _query = InventoryQuery(sort: widget.isWardrobe ? InventorySort.name : InventorySort.expiry);

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final images = _images; // vor dem ersten await holen – danach kann der Screen schon weg sein
    final items = await _repo.getItems(widget.user.uid, kinds: widget.kinds);
    if (!mounted) return;
    final files = <int, File>{};
    for (final i in items) {
      final f = await images.resolve(i.imagePath);
      if (f != null) files[i.id!] = f;
    }
    if (!mounted) return;
    setState(() {
      _items = items;
      _imageFiles = files;
      _loading = false;
    });
  }

  void _setQuery(InventoryQuery Function(InventoryQuery q) change) => setState(() => _query = change(_query));

  InventoryQuery _copy({
    String? search,
    Object? kind = _keep,
    Object? category = _keep,
    Object? location = _keep,
    Object? condition = _keep,
    InventoryStatus? status,
    InventorySort? sort,
  }) {
    return InventoryQuery(
      search: search ?? _query.search,
      kind: identical(kind, _keep) ? _query.kind : kind as InventoryKind?,
      category: identical(category, _keep) ? _query.category : category as String?,
      location: identical(location, _keep) ? _query.location : location as String?,
      condition: identical(condition, _keep) ? _query.condition : condition as ItemCondition?,
      status: status ?? _query.status,
      sort: sort ?? _query.sort,
    );
  }

  static const _keep = Object();

  bool get _hasFilters =>
      _query.search.isNotEmpty ||
      _query.kind != null ||
      _query.category != null ||
      _query.location != null ||
      _query.condition != null ||
      _query.status != InventoryStatus.all;

  // ─── Aktionen ──────────────────────────────────────────────────────────

  /// Neu (alle Felder, optional per Barcode) oder Bearbeiten – derselbe Editor.
  Future<void> _openEditor({InventoryItem? item}) async {
    final result = await Navigator.push<Object?>(
      context,
      MaterialPageRoute(
        builder: (_) => ItemEditorScreen(
          userid: widget.user.uid,
          kind: widget.addKind,
          kinds: widget.addKinds,
          item: item,
          onScanBarcode: item == null ? widget.onScanBarcode : null,
        ),
      ),
    );
    if (!mounted) return;
    if (result == ItemEditorScreen.deleted && item != null) {
      await _delete(item);
    } else if (result == true) {
      _load();
    }
  }

  Future<void> _useOrWear(InventoryItem item) async {
    final messenger = ScaffoldMessenger.of(context);
    if (item.kind.isConsumable) {
      final rest = await _repo.consume(item);
      messenger.showSnackBar(SnackBar(
        content: Text(rest == 0 ? '${item.name} aufgebraucht' : '${item.name}: noch ${_fmt(rest)} ${item.unit ?? ''}'.trim()),
      ));
    } else {
      await _repo.markWorn(item.id!);
      messenger.showSnackBar(SnackBar(content: Text('${item.name}: heute getragen')));
    }
    _load();
  }

  Future<void> _delete(InventoryItem item) => deleteWithUndo(
        context,
        label: item.name,
        delete: () => _repo.deleteItem(item.id!),
        restore: () => _repo.restoreItem(item),
        onChanged: _load,
      );

  static String _fmt(double v) => v == v.roundToDouble() ? v.toInt().toString() : v.toString().replaceAll('.', ',');

  // ─── UI ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final visible = _query.apply(_items);
    return Scaffold(
      floatingActionButton: AppFab(onPressed: () => _openEditor(), label: 'Artikel', heroTag: 'inventory-fab'),
      body: _loading
          ? Center(child: CircularProgressIndicator(color: c.accent))
          : RefreshIndicator(
              onRefresh: _load,
              child: CustomScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                slivers: [
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                    sliver: SliverList.list(children: [
                      _searchField(),
                      const SizedBox(height: 10),
                      if (_kindsPresent.length > 1) ...[
                        _kindChips(),
                        const SizedBox(height: 8),
                      ],
                      _statusChips(),
                      const SizedBox(height: 8),
                      _filterRow(),
                      const SizedBox(height: 10),
                      _resultLine(visible.length),
                      const SizedBox(height: 8),
                    ]),
                  ),
                  if (_items.isEmpty)
                    SliverToBoxAdapter(child: _emptyState())
                  else if (visible.isEmpty)
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.all(32),
                        child: Text('Nichts gefunden.', textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodySmall),
                      ),
                    )
                  else if (_grid)
                    SliverPadding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      sliver: SliverGrid.builder(
                        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                          maxCrossAxisExtent: 180,
                          mainAxisSpacing: 10,
                          crossAxisSpacing: 10,
                          childAspectRatio: 0.72,
                        ),
                        itemCount: visible.length,
                        itemBuilder: (_, i) => _gridCard(visible[i]),
                      ),
                    )
                  else
                    SliverPadding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      sliver: SliverList.builder(itemCount: visible.length, itemBuilder: (_, i) => _listTile(visible[i])),
                    ),
                  SliverToBoxAdapter(child: SizedBox(height: navClearance(context))),
                ],
              ),
            ),
    );
  }

  Widget _searchField() {
    final field = TextField(
      controller: _search,
      onChanged: (v) => _setQuery((_) => _copy(search: v)),
      decoration: InputDecoration(
        hintText: widget.isWardrobe ? 'Suchen: Name, Farbe, Marke …' : 'Suchen: Name, Marke, Ort …',
        prefixIcon: const Icon(Icons.search_rounded),
        suffixIcon: _search.text.isEmpty
            ? null
            : IconButton(
                tooltip: 'Suche leeren',
                icon: const Icon(Icons.close_rounded),
                onPressed: () {
                  _search.clear();
                  _setQuery((_) => _copy(search: ''));
                },
              ),
      ),
    );
    final receipt = widget.onScanReceipt;
    if (receipt == null) return field;
    return Row(children: [
      Expanded(child: field),
      const SizedBox(width: 6),
      IconButton.filledTonal(
        tooltip: 'Kassenzettel fotografieren',
        icon: const Icon(Icons.document_scanner_outlined),
        onPressed: () => receipt(_load),
      ),
    ]);
  }

  /// Arten, die im Inventar vorkommen, in fester Reihenfolge.
  List<InventoryKind> get _kindsPresent {
    final present = {for (final i in _items) i.kind};
    return InventoryKind.values.where(present.contains).toList();
  }

  /// Im Vorrat heißt „Pflege & Duft“ wie im Laden „Drogerie & Pflege“; Haushalt steckt in „Sonstiges“.
  String _kindLabel(InventoryKind k) => widget.isWardrobe
      ? k.label
      : switch (k) {
          InventoryKind.drink => 'Getränke',
          InventoryKind.care => 'Drogerie & Pflege',
          InventoryKind.other => 'Haushalt & Sonstiges',
          _ => k.label,
        };

  /// Produktarten als Chips (Alle · Lebensmittel · Getränke · Drogerie & Pflege · …) mit Anzahl.
  Widget _kindChips() {
    final kinds = _kindsPresent;
    return SizedBox(
      height: 36,
      child: ListView(scrollDirection: Axis.horizontal, children: [
        for (final k in <InventoryKind?>[null, ...kinds]) ...[
          AppChip(
            label: k == null ? 'Alle Arten' : _kindLabel(k),
            count: k == null ? _items.length : _items.where((i) => i.kind == k).length,
            selected: _query.kind == k,
            onTap: () => _setQuery((_) => _copy(kind: k)),
          ),
          const SizedBox(width: 8),
        ],
      ]),
    );
  }

  List<InventoryStatus> get _statuses => [
        InventoryStatus.all,
        if (widget.isWardrobe) InventoryStatus.notWornLately,
        if (widget.kinds.any((k) => k.isConsumable)) ...[InventoryStatus.expiringSoon, InventoryStatus.expired],
      ];

  Widget _statusChips() {
    int count(InventoryStatus s) =>
        InventoryQuery(status: s).apply(_items).length;
    return SizedBox(
      height: 36,
      child: ListView(scrollDirection: Axis.horizontal, children: [
        for (final s in _statuses) ...[
          AppChip(
            label: s.label,
            count: count(s),
            selected: _query.status == s,
            onTap: () => _setQuery((_) => _copy(status: s)),
          ),
          const SizedBox(width: 8),
        ],
      ]),
    );
  }

  Widget _filterRow() {
    final categories = {for (final i in _items) if (i.category != null) i.category!}.toList()..sort();
    final locations = {for (final i in _items) if (i.location != null) i.location!}.toList()..sort();
    return SizedBox(
      height: 36,
      child: ListView(scrollDirection: Axis.horizontal, children: [
        _menuChip<String?>(
          label: _query.category ?? 'Kategorie',
          active: _query.category != null,
          options: [null, ...categories],
          optionLabel: (v) => v ?? 'Alle Kategorien',
          onSelected: (v) => _setQuery((_) => _copy(category: v)),
        ),
        _menuChip<String?>(
          label: _query.location ?? 'Ort',
          active: _query.location != null,
          options: [null, ...locations],
          optionLabel: (v) => v ?? 'Alle Orte',
          onSelected: (v) => _setQuery((_) => _copy(location: v)),
        ),
        _menuChip<ItemCondition?>(
          label: _query.condition?.label ?? 'Zustand',
          active: _query.condition != null,
          options: [null, ...ItemCondition.values],
          optionLabel: (v) => v?.label ?? 'Alle Zustände',
          onSelected: (v) => _setQuery((_) => _copy(condition: v)),
        ),
        _menuChip<InventorySort>(
          label: 'Sortierung: ${_query.sort.label}',
          active: false,
          icon: Icons.swap_vert_rounded,
          options: widget.isWardrobe
              ? const [InventorySort.name, InventorySort.lastUsed, InventorySort.age]
              : const [InventorySort.expiry, InventorySort.name, InventorySort.age, InventorySort.lastUsed],
          optionLabel: (v) => v.label,
          onSelected: (v) => _setQuery((_) => _copy(sort: v)),
        ),
        IconButton(
          tooltip: _grid ? 'Als Liste anzeigen' : 'Als Raster anzeigen',
          icon: Icon(_grid ? Icons.view_list_rounded : Icons.grid_view_rounded),
          onPressed: () => setState(() => _grid = !_grid),
        ),
      ]),
    );
  }

  Widget _menuChip<T>({
    required String label,
    required bool active,
    required List<T> options,
    required String Function(T) optionLabel,
    required ValueChanged<T> onSelected,
    IconData icon = Icons.expand_more_rounded,
  }) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: PopupMenuButton<int>(
        tooltip: label,
        onSelected: (i) => onSelected(options[i]),
        itemBuilder: (_) => [for (var i = 0; i < options.length; i++) PopupMenuItem(value: i, child: Text(optionLabel(options[i])))],
        child: IgnorePointer(child: AppChip(label: label, selected: active, trailingIcon: icon)),
      ),
    );
  }

  Widget _resultLine(int count) {
    final t = Theme.of(context).textTheme;
    return Row(children: [
      Expanded(child: Text(count == 1 ? '1 Eintrag' : '$count Einträge', style: t.labelMedium)),
      if (_hasFilters)
        TextButton(
          onPressed: () {
            _search.clear();
            _setQuery((q) => InventoryQuery(sort: q.sort));
          },
          child: const Text('Filter zurücksetzen'),
        ),
    ]);
  }

  Widget _emptyState() => EmptyState(
        icon: widget.isWardrobe ? Icons.checkroom_rounded : Icons.kitchen_rounded,
        title: widget.isWardrobe ? 'Dein Kleiderschrank ist leer' : 'Dein Vorrat ist leer',
        message: widget.isWardrobe
            ? 'Füge Kleidung mit Foto, Größe und Zustand hinzu, um sie schnell wiederzufinden.'
            : 'Hier landet alles, was du einkaufst: Lebensmittel, Getränke, Drogerie und Haushalt – '
                'mit Ablaufdatum erinnert LifeHub dich rechtzeitig.',
      );

  String _subtitle(InventoryItem i) {
    final parts = <String>[
      if (i.kind.isConsumable) '${_fmt(i.quantity)} ${i.unit ?? ''}'.trim(),
      if (i.size != null) 'Gr. ${i.size}',
      if (i.color != null) i.color!,
      if (i.location != null) i.location!,
      if (i.condition != null) i.condition!.label,
      if (!i.kind.isConsumable && i.ageInDays() != null) ageText(i.ageInDays()!),
    ];
    return parts.join(' · ');
  }

  Widget _listTile(InventoryItem item) {
    final t = Theme.of(context).textTheme;
    final consumable = item.kind.isConsumable;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: SwipeTile(
        id: 'inventory-${item.id}',
        startAction: SwipeAction(
          label: consumable ? '−1' : 'Getragen',
          icon: consumable ? Icons.remove_circle_outline : Icons.checkroom_rounded,
          onPressed: () => _useOrWear(item),
        ),
        onEdit: () => _openEditor(item: item),
        onDelete: () => _delete(item),
        child: AppCard(
          padding: const EdgeInsets.all(12),
          onTap: () => _openEditor(item: item),
          child: Row(children: [
            InventoryThumb(item: item, image: _imageFiles[item.id]),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(item.name, style: t.titleMedium, maxLines: 1, overflow: TextOverflow.ellipsis),
                if (_subtitle(item).isNotEmpty)
                  Text(_subtitle(item), style: t.labelMedium, maxLines: 1, overflow: TextOverflow.ellipsis),
              ]),
            ),
            const SizedBox(width: 8),
            if (consumable) ExpiryBadge(item) else if (item.wearCount > 0) Text('${item.wearCount}×', style: t.labelMedium),
          ]),
        ),
      ),
    );
  }

  Widget _gridCard(InventoryItem item) {
    final t = Theme.of(context).textTheme;
    return AppCard(
      padding: EdgeInsets.zero,
      onTap: () => _openEditor(item: item),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Expanded(
          child: LayoutBuilder(
            builder: (_, box) => InventoryThumb(item: item, image: _imageFiles[item.id], size: box.maxWidth),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(item.name, style: t.titleSmall, maxLines: 1, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 2),
            if (item.kind.isConsumable)
              ExpiryBadge(item)
            else
              Text(_subtitle(item), style: t.labelSmall, maxLines: 1, overflow: TextOverflow.ellipsis),
          ]),
        ),
      ]),
    );
  }
}
