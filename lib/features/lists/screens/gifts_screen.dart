import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import 'package:frontend/core/ui/app_actions.dart';
import 'package:frontend/core/ui/app_ui.dart';
import 'package:frontend/core/ui/modern_appbar.dart';
import 'package:frontend/core/ui/theme.dart';
import 'package:frontend/features/auth/models/user.dart';
import 'package:frontend/features/lists/models/lists.dart';
import 'package:frontend/features/lists/repositories/lists_repository.dart';

String _countdown(GiftList l) {
  final d = l.daysUntil(DateTime.now());
  if (d == null) return 'ohne Datum';
  if (d == 0) return 'heute';
  if (d == 1) return 'morgen';
  if (d < 0) return 'vorbei';
  return 'in $d Tagen';
}

/// Geschenke-Wunschlisten für andere Personen, z. B. „Schwester · Geburtstag“.
class GiftsScreen extends StatefulWidget {
  final UserModel user;
  const GiftsScreen({super.key, required this.user});

  @override
  State<GiftsScreen> createState() => _GiftsScreenState();
}

class _GiftsScreenState extends State<GiftsScreen> {
  late final ListsRepository _repo = context.read<ListsRepository>();
  List<GiftList>? _lists;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final lists = await _repo.getGiftLists(widget.user.uid);
    if (mounted) setState(() => _lists = lists);
  }

  Future<void> _newList() async {
    final list = await showGiftListDialog(context, userid: widget.user.uid);
    if (list == null || !mounted) return;
    final id = await _repo.saveGiftList(list);
    if (!mounted) return;
    await _open(id);
  }

  Future<void> _open(int id) async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => GiftListScreen(listId: id)));
    _load();
  }

  Future<void> _editList(GiftList list) async {
    final updated = await showGiftListDialog(context, userid: list.userid, list: list);
    if (updated == null || !mounted) return;
    await runGuarded(context, () => _repo.saveGiftList(updated));
    _load();
  }

  Future<void> _deleteList(GiftList list) => deleteWithUndo(
        context,
        label: list.title,
        delete: () => _repo.deleteGiftList(list.id!),
        restore: () => _repo.restoreGiftList(list.id!),
        onChanged: _load,
      );

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final t = Theme.of(context).textTheme;
    final lists = _lists;
    return Scaffold(
      floatingActionButton: AppFab(heroTag: 'gifts-fab', label: 'Liste', onPressed: lists == null ? null : _newList),
      body: lists == null
          ? Center(child: CircularProgressIndicator(color: c.accent))
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: pagePadding(context),
                children: [
                  if (lists.isEmpty)
                    const EmptyState(
                      icon: Icons.card_giftcard_rounded,
                      title: 'Noch keine Geschenkelisten',
                      message: 'Sammle Ideen pro Person und Anlass – z. B. Geburtstag deiner Schwester oder Weihnachten für deinen Bruder.',
                    ),
                  for (final l in lists)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: SwipeTile(
                        id: 'gift-list-${l.id}',
                        onEdit: () => _editList(l),
                        onDelete: () => _deleteList(l),
                        child: AppCard(
                          onTap: () => _open(l.id!),
                          padding: const EdgeInsets.all(14),
                          child: Row(children: [
                            IconTile(icon: _occasionIcon(l.occasion), color: c.accentText),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                Text(l.title, style: t.titleMedium, maxLines: 1, overflow: TextOverflow.ellipsis),
                                Text(
                                  [
                                    if (l.date != null) DateFormat('d. MMMM', 'de_DE').format(l.date!),
                                    _countdown(l),
                                    '${l.openCount} ${l.openCount == 1 ? 'Idee' : 'Ideen'}',
                                    if (l.plannedSum > 0) formatEuro(l.plannedSum, decimals: 2),
                                  ].join(' · '),
                                  style: t.labelMedium?.copyWith(
                                    color: (l.daysUntil(DateTime.now()) ?? 99) <= 14 && (l.daysUntil(DateTime.now()) ?? -1) >= 0
                                        ? c.streak
                                        : null,
                                  ),
                                ),
                              ]),
                            ),
                            const Icon(Icons.chevron_right_rounded),
                          ]),
                        ),
                      ),
                    ),
                ],
              ),
            ),
    );
  }
}

IconData _occasionIcon(String occasion) => switch (occasion) {
      'Geburtstag' => Icons.cake_rounded,
      'Weihnachten' => Icons.park_rounded,
      'Hochzeit' || 'Jahrestag' => Icons.favorite_rounded,
      _ => Icons.card_giftcard_rounded,
    };

/// Person, Anlass, Datum und Notiz einer Geschenkeliste erfassen.
Future<GiftList?> showGiftListDialog(BuildContext context, {required int userid, GiftList? list}) =>
    showEditorSheet<GiftList>(context, (_) => _GiftListSheet(userid: userid, list: list));

class _GiftListSheet extends StatefulWidget {
  final int userid;
  final GiftList? list;
  const _GiftListSheet({required this.userid, this.list});

  @override
  State<_GiftListSheet> createState() => _GiftListSheetState();
}

class _GiftListSheetState extends State<_GiftListSheet> {
  final _formKey = GlobalKey<FormState>();
  late final _person = TextEditingController(text: widget.list?.person ?? '');
  late final _occasion = TextEditingController(text: widget.list?.occasion ?? 'Geburtstag');
  late final _notes = TextEditingController(text: widget.list?.notes ?? '');
  late DateTime? _date = widget.list?.date;

  @override
  void dispose() {
    _person.dispose();
    _occasion.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _date ?? now,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 3),
      helpText: 'Datum des Anlasses',
    );
    if (picked != null) setState(() => _date = picked);
  }

  void _save() {
    if (!_formKey.currentState!.validate()) return;
    Navigator.of(context).pop(GiftList(
      id: widget.list?.id,
      userid: widget.userid,
      person: _person.text.trim(),
      occasion: _occasion.text.trim().isEmpty ? 'Einfach so' : _occasion.text.trim(),
      date: _date,
      notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return EditorSheet(
      formKey: _formKey,
      title: widget.list == null ? 'Neue Geschenkeliste' : 'Liste bearbeiten',
      onSave: _save,
      children: [
        TextFormField(
          controller: _person,
          autofocus: widget.list == null,
          decoration: const InputDecoration(labelText: 'Für wen?', hintText: 'z. B. Schwester'),
          validator: (v) => (v ?? '').trim().isEmpty ? 'Für wen ist die Liste?' : null,
        ),
        const SizedBox(height: 12),
        TextFormField(
          controller: _occasion,
          decoration: const InputDecoration(labelText: 'Anlass'),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final o in giftOccasions) AppChip(label: o, selected: _occasion.text == o, onTap: () => setState(() => _occasion.text = o)),
        ]),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: _pickDate,
          icon: const Icon(Icons.event_rounded),
          label: Text(_date == null ? 'Datum (optional)' : DateFormat('d. MMMM y', 'de_DE').format(_date!)),
        ),
        if (_date != null) TextButton(onPressed: () => setState(() => _date = null), child: const Text('Datum entfernen')),
        const SizedBox(height: 12),
        TextFormField(
          controller: _notes,
          minLines: 1,
          maxLines: 3,
          decoration: const InputDecoration(labelText: 'Notiz (optional)'),
        ),
      ],
    );
  }
}

/// Eine Geschenkidee mit allen Feldern erfassen.
Future<GiftItem?> showGiftSheet(BuildContext context, {required GiftList list, GiftItem? gift}) =>
    showEditorSheet<GiftItem>(context, (_) => _GiftSheet(list: list, gift: gift));

class _GiftSheet extends StatefulWidget {
  final GiftList list;
  final GiftItem? gift;
  const _GiftSheet({required this.list, this.gift});

  @override
  State<_GiftSheet> createState() => _GiftSheetState();
}

class _GiftSheetState extends State<_GiftSheet> {
  final _formKey = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.gift?.name ?? '');
  late final _price = TextEditingController(text: widget.gift?.price?.toStringAsFixed(2).replaceAll('.', ',') ?? '');
  late final _url = TextEditingController(text: widget.gift?.url ?? '');
  late final _notes = TextEditingController(text: widget.gift?.notes ?? '');
  late GiftStatus _status = widget.gift?.status ?? GiftStatus.idea;

  @override
  void dispose() {
    for (final c in [_name, _price, _url, _notes]) {
      c.dispose();
    }
    super.dispose();
  }

  String? _opt(TextEditingController c) => c.text.trim().isEmpty ? null : c.text.trim();

  void _save() {
    if (!_formKey.currentState!.validate()) return;
    Navigator.of(context).pop(GiftItem(
      id: widget.gift?.id,
      listId: widget.list.id!,
      userid: widget.list.userid,
      name: _name.text.trim(),
      price: double.tryParse(_price.text.trim().replaceAll(',', '.')),
      url: _opt(_url),
      notes: _opt(_notes),
      status: _status,
    ));
  }

  @override
  Widget build(BuildContext context) {
    return EditorSheet(
      formKey: _formKey,
      title: widget.gift == null ? 'Neue Geschenkidee' : 'Idee bearbeiten',
      onSave: _save,
      children: [
        TextFormField(
          controller: _name,
          autofocus: widget.gift == null,
          decoration: const InputDecoration(labelText: 'Idee'),
          validator: (v) => (v ?? '').trim().isEmpty ? 'Bitte eine Idee eingeben' : null,
        ),
        const SizedBox(height: 12),
        TextFormField(
          controller: _price,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(labelText: 'Preis in € (optional)'),
          validator: (v) {
            final text = (v ?? '').trim();
            return text.isEmpty || double.tryParse(text.replaceAll(',', '.')) != null ? null : 'Bitte eine Zahl eingeben';
          },
        ),
        const SizedBox(height: 12),
        TextFormField(
          controller: _url,
          keyboardType: TextInputType.url,
          decoration: const InputDecoration(labelText: 'Link (optional)'),
        ),
        const SizedBox(height: 12),
        TextFormField(
          controller: _notes,
          minLines: 1,
          maxLines: 3,
          decoration: const InputDecoration(labelText: 'Notiz (optional)'),
        ),
        const SizedBox(height: 12),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final st in GiftStatus.values) AppChip(label: st.label, selected: st == _status, onTap: () => setState(() => _status = st)),
        ]),
      ],
    );
  }
}

/// Eine Geschenkeliste: Ideen sammeln, als gekauft/verschenkt markieren, auf die Einkaufsliste setzen.
class GiftListScreen extends StatefulWidget {
  final int listId;
  const GiftListScreen({super.key, required this.listId});

  @override
  State<GiftListScreen> createState() => _GiftListScreenState();
}

class _GiftListScreenState extends State<GiftListScreen> {
  late final ListsRepository _repo = context.read<ListsRepository>();
  GiftList? _list;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final list = await _repo.getGiftList(widget.listId);
    if (mounted) setState(() => _list = list);
  }

  Future<void> _editGift([GiftItem? gift]) async {
    final result = await showGiftSheet(context, list: _list!, gift: gift);
    if (result == null || !mounted) return;
    await runGuarded(context, () => _repo.saveGift(result));
    _load();
  }

  Future<void> _deleteGift(GiftItem gift) => deleteWithUndo(
        context,
        label: gift.name,
        delete: () => _repo.deleteGift(gift.id!),
        restore: () => _repo.restoreGift(gift.id!),
        onChanged: _load,
      );

  Future<void> _advance(GiftItem gift) async {
    await runGuarded(context, () => _repo.setGiftStatus(gift, gift.status.next));
    _load();
  }

  Future<void> _editList() async {
    final updated = await showGiftListDialog(context, userid: _list!.userid, list: _list);
    if (updated == null || !mounted) return;
    await runGuarded(context, () => _repo.saveGiftList(updated));
    _load();
  }

  Future<void> _toShopping(GiftItem gift) => runGuarded(
        context,
        () => _repo.giftToShopping(gift, _list!),
        success: '„${gift.name}“ steht auf der Einkaufsliste',
      );

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final t = Theme.of(context).textTheme;
    final list = _list;
    return Scaffold(
      appBar: ModernAppBar(title: list?.title ?? 'Geschenke', customActions: [
        if (list != null) IconButton(tooltip: 'Liste bearbeiten', icon: const Icon(Icons.edit_outlined), onPressed: _editList),
      ]),
      floatingActionButton: list == null ? null : AppFab(label: 'Idee', heroTag: 'gift-fab', onPressed: () => _editGift()),
      body: list == null
          ? Center(child: CircularProgressIndicator(color: c.accent))
          : ListView(padding: pagePadding(context), children: [
              AppCard(
                padding: const EdgeInsets.all(14),
                child: Row(children: [
                  IconTile(icon: _occasionIcon(list.occasion), color: c.accentText),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(list.occasion, style: t.titleMedium),
                      Text(
                        [
                          if (list.date != null) DateFormat('EEEE, d. MMMM y', 'de_DE').format(list.date!),
                          _countdown(list),
                        ].join(' · '),
                        style: t.labelMedium,
                      ),
                    ]),
                  ),
                  if (list.plannedSum > 0) Text(formatEuro(list.plannedSum, decimals: 2), style: t.titleMedium),
                ]),
              ),
              const SizedBox(height: 16),
              if (list.items.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  child: Text('Noch keine Ideen – tippe auf „Idee“.',
                      textAlign: TextAlign.center, style: t.bodyMedium?.copyWith(color: c.muted)),
                ),
              for (final status in GiftStatus.values)
                if (list.items.any((i) => i.status == status)) ...[
                  SectionTitle(status == GiftStatus.idea ? 'Ideen' : status.label),
                  for (final g in list.items.where((i) => i.status == status)) _giftTile(context, g),
                  const SizedBox(height: 8),
                ],
            ]),
    );
  }

  Widget _giftTile(BuildContext context, GiftItem g) {
    final t = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: SwipeTile(
        id: 'gift-${g.id}',
        startAction: SwipeAction(
          label: switch (g.status) {
            GiftStatus.idea => 'Gekauft',
            GiftStatus.bought => 'Verschenkt',
            GiftStatus.given => 'Zurück',
          },
          icon: Icons.redeem_rounded,
          onPressed: () => _advance(g),
        ),
        onEdit: () => _editGift(g),
        onDelete: () => _deleteGift(g),
        child: AppCard(
          onTap: () => _editGift(g),
          padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
          child: Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(g.name, style: t.titleSmall?.copyWith(decoration: g.status == GiftStatus.given ? TextDecoration.lineThrough : null)),
                if (g.price != null || g.notes != null)
                  Text([if (g.price != null) formatEuro(g.price!, decimals: 2), if (g.notes != null) g.notes!].join(' · '),
                      style: t.labelMedium),
              ]),
            ),
            if (g.url != null)
              IconButton(
                tooltip: 'Link kopieren',
                icon: const Icon(Icons.link_rounded, size: 20),
                onPressed: () => Clipboard.setData(ClipboardData(text: g.url!)),
              ),
            if (g.status == GiftStatus.idea)
              IconButton(
                tooltip: 'Auf die Einkaufsliste',
                icon: const Icon(Icons.add_shopping_cart_rounded, size: 20),
                onPressed: () => _toShopping(g),
              ),
            TextButton(
              onPressed: () => _advance(g),
              child: Text(switch (g.status) {
                GiftStatus.idea => 'Gekauft',
                GiftStatus.bought => 'Verschenkt',
                GiftStatus.given => 'Zurück',
              }),
            ),
          ]),
        ),
      ),
    );
  }
}
