import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import 'package:frontend/core/ui/app_actions.dart';
import 'package:frontend/core/ui/app_ui.dart';
import 'package:frontend/core/ui/modern_appbar.dart';
import 'package:frontend/core/ui/theme.dart';
import 'package:frontend/features/contacts/models/contact.dart';
import 'package:frontend/features/contacts/models/relative_date.dart';
import 'package:frontend/features/contacts/repositories/contact_repository.dart';
import 'package:frontend/features/contacts/screens/contacts_screen.dart';
import 'package:frontend/features/contacts/widgets/contact_widgets.dart';
import 'package:frontend/features/lists/models/lists.dart';
import 'package:frontend/features/lists/repositories/lists_repository.dart';
import 'package:frontend/features/lists/screens/gifts_screen.dart';

/// Eine Person: Angaben, Geburtstag mit Geschenkliste und Notizen – auch kleine mit Datum,
/// die am Tag auf „Heute“ stehen und erinnern.
class ContactScreen extends StatefulWidget {
  final int contactId;
  const ContactScreen({super.key, required this.contactId});

  @override
  State<ContactScreen> createState() => _ContactScreenState();
}

class _ContactScreenState extends State<ContactScreen> {
  late final ContactRepository _repo = context.read<ContactRepository>();
  final _quick = TextEditingController();
  Contact? _contact;
  List<ContactNote> _notes = const [];
  bool _loaded = false;

  /// Datum der Schnellnotiz: von Hand gewählt, sonst aus dem Text erkannt (außer weggeklickt).
  DateTime? _pickedDate;
  bool _ignoreDetected = false;
  bool _followUp = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _quick.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final contact = await _repo.getContact(widget.contactId);
    final notes = contact == null ? const <ContactNote>[] : await _repo.getNotes(widget.contactId);
    if (!mounted) return;
    setState(() {
      _contact = contact;
      _notes = notes;
      _loaded = true;
    });
  }

  ({DateTime? date, String text}) get _parsed => parseRelativeDate(_quick.text, DateTime.now());

  DateTime? get _quickDate => _pickedDate ?? (_ignoreDetected ? null : _parsed.date);

  Future<void> _pickQuickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _quickDate ?? now,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 5),
      helpText: 'Datum der Notiz',
    );
    if (picked != null) setState(() => _pickedDate = picked);
  }

  Future<void> _addQuick() async {
    final raw = _quick.text.trim();
    if (raw.isEmpty) return;
    final date = _quickDate;
    final detected = _pickedDate == null && !_ignoreDetected && _parsed.date != null;
    final text = detected && _parsed.text.isNotEmpty ? _parsed.text : raw;
    final saved = await runGuarded(
      context,
      () => _repo.saveNote(ContactNote(
        userid: _contact!.userid,
        contactId: _contact!.id!,
        text: text,
        date: date,
        followUp: date != null && _followUp,
        created: DateTime.now(),
      )),
      success: date == null ? 'Notiz gespeichert' : 'Notiz für ${DateFormat('EEEE, d. MMMM', 'de_DE').format(date)} – du wirst erinnert',
    );
    if (saved == null || !mounted) return;
    setState(() {
      _quick.clear();
      _pickedDate = null;
      _ignoreDetected = false;
      _followUp = false;
    });
    FocusScope.of(context).unfocus();
    _load();
  }

  Future<void> _toggle(ContactNote n) async {
    await runGuarded(context, () => _repo.setNoteDone(n, !n.done));
    _load();
  }

  Future<void> _editNote(ContactNote n) async {
    final updated = await showEditorSheet<ContactNote>(context, (_) => _NoteSheet(note: n));
    if (updated == null || !mounted) return;
    await runGuarded(context, () => _repo.saveNote(updated));
    _load();
  }

  Future<void> _deleteNote(ContactNote n) => deleteWithUndo(
        context,
        label: n.text,
        delete: () => _repo.deleteNote(n),
        restore: () => _repo.restoreNote(n),
        onChanged: _load,
      );

  Future<void> _edit() async {
    final updated = await showContactSheet(context, userid: _contact!.userid, contact: _contact);
    if (updated == null || !mounted) return;
    await runGuarded(context, () => _repo.saveContact(updated));
    _load();
  }

  /// Öffnet die Geschenkliste der Person oder legt sie zum nächsten Geburtstag an.
  Future<void> _gifts() async {
    final p = _contact!;
    final lists = context.read<ListsRepository>();
    final navigator = Navigator.of(context);
    final id = await runGuarded(context, () async {
      final existing = (await lists.getGiftLists(p.userid)).where((l) => l.person.trim().toLowerCase() == p.name.trim().toLowerCase());
      if (existing.isNotEmpty) return existing.first.id!;
      return lists.saveGiftList(GiftList(
        userid: p.userid,
        person: p.name.trim(),
        occasion: p.birthday == null ? 'Einfach so' : 'Geburtstag',
        date: p.nextBirthday(DateTime.now()),
      ));
    });
    if (id == null || !mounted) return;
    await navigator.push(MaterialPageRoute(builder: (_) => GiftListScreen(listId: id)));
  }

  Future<void> _copy(String label, String value) async {
    await Clipboard.setData(ClipboardData(text: value));
    if (mounted) showAppSnack(context, '$label kopiert');
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final p = _contact;
    return Scaffold(
      appBar: ModernAppBar(title: p?.name ?? 'Kontakt', customActions: [
        if (p != null) IconButton(tooltip: 'Kontakt bearbeiten', icon: const Icon(Icons.edit_outlined), onPressed: _edit),
      ]),
      body: !_loaded
          ? Center(child: CircularProgressIndicator(color: c.accent))
          : p == null
              ? const EmptyState(icon: Icons.person_off_rounded, title: 'Kontakt nicht gefunden', message: 'Er wurde vielleicht gelöscht.')
              : ListView(padding: pagePadding(context), children: [
                  _header(context, p),
                  if (p.birthday != null) ...[const SizedBox(height: 10), _birthday(context, p)],
                  if (p.phone != null || p.email != null || p.address != null) ...[const SizedBox(height: 10), _details(context, p)],
                  if (p.notes != null) ...[
                    const SizedBox(height: 10),
                    AppCard(
                      onTap: _edit,
                      padding: const EdgeInsets.all(14),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('Allgemeines', style: Theme.of(context).textTheme.labelMedium),
                        const SizedBox(height: 4),
                        Text(p.notes!),
                      ]),
                    ),
                  ],
                  const SizedBox(height: 16),
                  const GroupLabel('Notizen'),
                  _quickNote(context),
                  const SizedBox(height: 10),
                  for (final n in _notes) _noteTile(context, n),
                ]),
    );
  }

  Widget _header(BuildContext context, Contact p) {
    final t = Theme.of(context).textTheme;
    final sub = [if (p.nickname != null) '„${p.nickname}“', if (p.relation != null) p.relation!].join(' · ');
    return AppCard(
      padding: const EdgeInsets.all(14),
      child: Row(children: [
        ContactAvatar(contact: p, size: 52),
        const SizedBox(width: 14),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(p.name, style: t.titleLarge),
            if (sub.isNotEmpty) Text(sub, style: t.labelMedium),
          ]),
        ),
      ]),
    );
  }

  Widget _birthday(BuildContext context, Contact p) {
    final c = AppColors.of(context);
    final t = Theme.of(context).textTheme;
    final now = DateTime.now();
    final days = p.daysUntilBirthday(now)!;
    final age = p.ageAtNextBirthday(now)!;
    return AppCard(
      padding: const EdgeInsets.all(14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          IconTile(icon: Icons.cake_rounded, color: days <= 14 ? c.streak : c.accentText),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(DateFormat('d. MMMM y', 'de_DE').format(p.birthday!), style: t.titleSmall),
              Text(
                [if (age > 0) 'wird $age', relativeDays(days)!].join(' · '),
                style: t.labelMedium?.copyWith(color: days <= 14 ? c.streak : null),
              ),
            ]),
          ),
        ]),
        const SizedBox(height: 10),
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton.icon(onPressed: _gifts, icon: const Icon(Icons.card_giftcard_rounded), label: const Text('Geschenkliste')),
        ),
      ]),
    );
  }

  Widget _details(BuildContext context, Contact p) {
    Widget row(IconData icon, String label, String value) => ListTile(
          contentPadding: const EdgeInsets.only(left: 14, right: 4),
          leading: Icon(icon),
          title: Text(value),
          subtitle: Text(label),
          trailing: IconButton(tooltip: '$label kopieren', icon: const Icon(Icons.copy_rounded, size: 20), onPressed: () => _copy(label, value)),
        );
    return AppCard(
      padding: EdgeInsets.zero,
      child: Column(children: [
        if (p.phone != null) row(Icons.phone_rounded, 'Telefon', p.phone!),
        if (p.email != null) row(Icons.mail_outline_rounded, 'E-Mail', p.email!),
        if (p.address != null) row(Icons.home_outlined, 'Adresse', p.address!),
      ]),
    );
  }

  Widget _quickNote(BuildContext context) {
    final c = AppColors.of(context);
    final t = Theme.of(context).textTheme;
    final date = _quickDate;
    final now = DateTime.now();
    return AppCard(
      padding: const EdgeInsets.all(14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        TextField(
          controller: _quick,
          minLines: 1,
          maxLines: 4,
          textCapitalization: TextCapitalization.sentences,
          onChanged: (_) => setState(() {}),
          decoration: const InputDecoration(
            labelText: 'Neue Notiz',
            hintText: 'z. B. hat nächste Woche Mittwoch einen Arzttermin',
          ),
        ),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
          if (date != null)
            InputChip(
              avatar: Icon(Icons.event_rounded, size: 18, color: c.accentText),
              label: Text(noteDateLabel(date, now)),
              onPressed: _pickQuickDate,
              onDeleted: () => setState(() {
                _pickedDate = null;
                _ignoreDetected = true;
              }),
              deleteButtonTooltipMessage: 'Ohne Datum',
            )
          else
            TextButton.icon(onPressed: _pickQuickDate, icon: const Icon(Icons.event_rounded), label: const Text('Datum')),
        ]),
        if (date != null)
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            controlAffinity: ListTileControlAffinity.leading,
            value: _followUp,
            onChanged: (v) => setState(() => _followUp = v ?? false),
            title: Text('Am Tag danach nachfragen', style: t.bodyMedium),
          ),
        const SizedBox(height: 4),
        FilledButton(onPressed: _quick.text.trim().isEmpty ? null : _addQuick, child: const Text('Notiz hinzufügen')),
      ]),
    );
  }

  Widget _noteTile(BuildContext context, ContactNote n) {
    final c = AppColors.of(context);
    final t = Theme.of(context).textTheme;
    final now = DateTime.now();
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: SwipeTile(
        id: 'contact-note-${n.id}',
        onEdit: () => _editNote(n),
        onDelete: () => _deleteNote(n),
        child: AppCard(
          onTap: () => _editNote(n),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(children: [
            if (n.date != null) ...[
              Semantics(
                checked: n.done,
                label: 'Erledigt',
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => _toggle(n),
                  child: SizedBox(width: 36, height: 36, child: Center(child: AppCheck(checked: n.done, onTap: () => _toggle(n)))),
                ),
              ),
              const SizedBox(width: 8),
            ],
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(n.text,
                    style: t.bodyLarge?.copyWith(
                      color: n.done ? c.dim : c.text,
                      decoration: n.done ? TextDecoration.lineThrough : null,
                    )),
                Row(children: [
                  if (n.date != null) ...[
                    Icon(Icons.event_rounded, size: 13, color: n.done ? c.dim : c.accentText),
                    const SizedBox(width: 4),
                  ],
                  Flexible(
                    child: Text(
                      n.date != null ? noteDateLabel(n.date!, now) : DateFormat('d. MMM y', 'de_DE').format(n.created),
                      style: t.labelMedium?.copyWith(color: n.date != null && !n.done ? c.accentText : c.dim),
                    ),
                  ),
                  if (n.followUp) ...[
                    const SizedBox(width: 6),
                    Icon(Icons.forum_outlined, size: 13, color: c.dim),
                  ],
                ]),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}

class _NoteSheet extends StatefulWidget {
  final ContactNote note;
  const _NoteSheet({required this.note});

  @override
  State<_NoteSheet> createState() => _NoteSheetState();
}

class _NoteSheetState extends State<_NoteSheet> {
  final _formKey = GlobalKey<FormState>();
  late final _text = TextEditingController(text: widget.note.text);
  late DateTime? _date = widget.note.date;
  late bool _followUp = widget.note.followUp;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _pick() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _date ?? now,
      firstDate: DateTime(now.year - 5),
      lastDate: DateTime(now.year + 5),
      helpText: 'Datum der Notiz',
    );
    if (picked != null) setState(() => _date = picked);
  }

  void _save() {
    if (!_formKey.currentState!.validate()) return;
    Navigator.of(context).pop(widget.note.copyWith(
      text: _text.text.trim(),
      date: _date,
      clearDate: _date == null,
      followUp: _date != null && _followUp,
    ));
  }

  @override
  Widget build(BuildContext context) => EditorSheet(
        formKey: _formKey,
        title: 'Notiz bearbeiten',
        onSave: _save,
        children: [
          TextFormField(
            controller: _text,
            minLines: 1,
            maxLines: 5,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(labelText: 'Notiz'),
            validator: (v) => (v ?? '').trim().isEmpty ? 'Die Notiz ist leer' : null,
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _pick,
            icon: const Icon(Icons.event_rounded),
            label: Text(_date == null ? 'Datum (optional)' : DateFormat('EEEE, d. MMMM y', 'de_DE').format(_date!)),
          ),
          if (_date != null) ...[
            TextButton(onPressed: () => setState(() => _date = null), child: const Text('Datum entfernen')),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              value: _followUp,
              onChanged: (v) => setState(() => _followUp = v ?? false),
              title: const Text('Am Tag danach nachfragen'),
            ),
          ],
        ],
      );
}
