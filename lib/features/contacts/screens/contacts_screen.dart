import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import 'package:frontend/core/ui/app_actions.dart';
import 'package:frontend/core/ui/app_ui.dart';
import 'package:frontend/core/ui/theme.dart';
import 'package:frontend/features/auth/models/user.dart';
import 'package:frontend/features/contacts/models/contact.dart';
import 'package:frontend/features/contacts/repositories/contact_repository.dart';
import 'package:frontend/features/contacts/screens/contact_screen.dart';
import 'package:frontend/features/contacts/widgets/contact_widgets.dart';

/// Kontakte im Tab „Planen“: Personen A–Z mit Suche und anstehenden Geburtstagen.
class ContactsScreen extends StatefulWidget {
  final UserModel user;
  const ContactsScreen({super.key, required this.user});

  @override
  State<ContactsScreen> createState() => _ContactsScreenState();
}

class _ContactsScreenState extends State<ContactsScreen> {
  late final ContactRepository _repo = context.read<ContactRepository>();
  final _search = TextEditingController();
  List<Contact>? _contacts;
  Object? _error;
  int _loadId = 0;

  int get _uid => widget.user.uid;

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
    final loadId = ++_loadId;
    try {
      final contacts = await _repo.getContacts(_uid, search: _search.text);
      if (!mounted || loadId != _loadId) return;
      setState(() {
        _contacts = contacts;
        _error = null;
      });
    } catch (e) {
      if (mounted && loadId == _loadId) setState(() => _error = e);
    }
  }

  Future<void> _new() async {
    final contact = await showContactSheet(context, userid: _uid);
    if (contact == null || !mounted) return;
    final id = await runGuarded(context, () => _repo.saveContact(contact));
    if (id == null || !mounted) return;
    await _open(id);
  }

  Future<void> _open(int id) async {
    await openContact(context, id);
    _load();
  }

  Future<void> _delete(Contact contact) async {
    String? at;
    await deleteWithUndo(
      context,
      label: contact.name,
      delete: () async => at = await _repo.deleteContact(contact.id!),
      restore: () => _repo.restoreContact(contact.id!, at!),
      onChanged: _load,
    );
  }

  Future<void> _edit(Contact contact) async {
    final updated = await showContactSheet(context, userid: _uid, contact: contact);
    if (updated == null || !mounted) return;
    await runGuarded(context, () => _repo.saveContact(updated));
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final contacts = _contacts;
    return Scaffold(
      floatingActionButton: AppFab(heroTag: 'contacts-fab', label: 'Kontakt', onPressed: contacts == null ? null : _new),
      body: _error != null
          ? EmptyState(
              icon: Icons.cloud_off_rounded,
              title: 'Laden fehlgeschlagen',
              message: errorText(_error!),
              action: OutlinedButton(onPressed: _load, child: const Text('Erneut versuchen')),
            )
          : contacts == null
              ? Center(child: CircularProgressIndicator(color: c.accent))
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: pagePadding(context),
                    children: [
                      TextField(
                        controller: _search,
                        onChanged: (_) => _load(),
                        decoration: InputDecoration(
                          hintText: 'Name, Beziehung oder Notiz suchen',
                          prefixIcon: const Icon(Icons.search_rounded),
                          suffixIcon: _search.text.isEmpty
                              ? null
                              : IconButton(
                                  tooltip: 'Suche leeren',
                                  icon: const Icon(Icons.close_rounded),
                                  onPressed: () {
                                    _search.clear();
                                    _load();
                                  },
                                ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      if (contacts.isEmpty)
                        _search.text.trim().isEmpty
                            ? const EmptyState(
                                icon: Icons.people_alt_rounded,
                                title: 'Noch keine Kontakte',
                                message: 'Halte fest, was dir an Menschen wichtig ist – Geburtstag, Vorlieben und Kleinigkeiten '
                                    'wie „hat nächste Woche Mittwoch einen Arzttermin“. Am Tag erinnert dich die App.',
                              )
                            : EmptyState(icon: Icons.search_off_rounded, title: 'Nichts gefunden', message: 'Niemand passt zu „${_search.text.trim()}“.'),
                      ..._list(context, contacts),
                    ],
                  ),
                ),
    );
  }

  List<Widget> _list(BuildContext context, List<Contact> contacts) {
    final c = AppColors.of(context);
    final t = Theme.of(context).textTheme;
    final now = DateTime.now();
    final widgets = <Widget>[];
    String? letter;
    for (final p in contacts) {
      final first = p.initials.substring(0, 1);
      if (first != letter) {
        letter = first;
        widgets.add(Padding(padding: EdgeInsets.only(top: widgets.isEmpty ? 0 : 6), child: GroupLabel(first)));
      }
      final hint = birthdayHint(p, now, within: 14);
      final sub = [if (p.relation != null) p.relation!, if (hint != null) hint].join(' · ');
      widgets.add(Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: SwipeTile(
          id: 'contact-${p.id}',
          onEdit: () => _edit(p),
          onDelete: () => _delete(p),
          child: AppCard(
            onTap: () => _open(p.id!),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Row(children: [
              ContactAvatar(contact: p),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(p.nickname == null ? p.name : '${p.name} (${p.nickname})', style: t.titleMedium, maxLines: 1, overflow: TextOverflow.ellipsis),
                  if (sub.isNotEmpty)
                    Text(sub, style: t.labelMedium?.copyWith(color: hint != null ? c.streak : null), maxLines: 2, overflow: TextOverflow.ellipsis),
                ]),
              ),
              const Icon(Icons.chevron_right_rounded),
            ]),
          ),
        ),
      ));
    }
    return widgets;
  }
}

/// Öffnet die Detailseite eines Kontakts.
Future<void> openContact(BuildContext context, int id) =>
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => ContactScreen(contactId: id)));

/// Beziehungen zum schnellen Auswählen.
const contactRelations = ['Familie', 'Freundschaft', 'Partnerschaft', 'Arbeit', 'Nachbarschaft'];

/// Alle Angaben zu einer Person erfassen oder ändern.
Future<Contact?> showContactSheet(BuildContext context, {required int userid, Contact? contact}) =>
    showEditorSheet<Contact>(context, (_) => _ContactSheet(userid: userid, contact: contact));

class _ContactSheet extends StatefulWidget {
  final int userid;
  final Contact? contact;
  const _ContactSheet({required this.userid, this.contact});

  @override
  State<_ContactSheet> createState() => _ContactSheetState();
}

class _ContactSheetState extends State<_ContactSheet> {
  final _formKey = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.contact?.name ?? '');
  late final _nickname = TextEditingController(text: widget.contact?.nickname ?? '');
  late final _relation = TextEditingController(text: widget.contact?.relation ?? '');
  late final _phone = TextEditingController(text: widget.contact?.phone ?? '');
  late final _email = TextEditingController(text: widget.contact?.email ?? '');
  late final _address = TextEditingController(text: widget.contact?.address ?? '');
  late final _notes = TextEditingController(text: widget.contact?.notes ?? '');
  late DateTime? _birthday = widget.contact?.birthday;

  @override
  void dispose() {
    for (final c in [_name, _nickname, _relation, _phone, _email, _address, _notes]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _pickBirthday() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _birthday ?? DateTime(now.year - 30, now.month, now.day),
      initialDatePickerMode: _birthday == null ? DatePickerMode.year : DatePickerMode.day,
      firstDate: DateTime(1900),
      lastDate: now,
      helpText: 'Geburtstag',
    );
    if (picked != null) setState(() => _birthday = picked);
  }

  void _save() {
    if (!_formKey.currentState!.validate()) return;
    final old = widget.contact;
    Navigator.of(context).pop(Contact(
      id: old?.id,
      userid: widget.userid,
      name: _name.text.trim(),
      nickname: _nickname.text,
      relation: _relation.text,
      phone: _phone.text,
      email: _email.text,
      address: _address.text,
      birthday: _birthday,
      notes: _notes.text,
      appointmentId: old?.appointmentId,
    ));
  }

  @override
  Widget build(BuildContext context) {
    return EditorSheet(
      formKey: _formKey,
      title: widget.contact == null ? 'Neuer Kontakt' : 'Kontakt bearbeiten',
      onSave: _save,
      children: [
        TextFormField(
          controller: _name,
          autofocus: widget.contact == null,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(labelText: 'Name'),
          validator: (v) => (v ?? '').trim().isEmpty ? 'Wie heißt die Person?' : null,
        ),
        const SizedBox(height: 12),
        TextFormField(
          controller: _nickname,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(labelText: 'Spitzname (optional)'),
        ),
        const SizedBox(height: 12),
        TextFormField(
          controller: _relation,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(labelText: 'Beziehung (optional)', hintText: 'z. B. Schwester, Kollegin'),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final r in contactRelations) AppChip(label: r, selected: _relation.text == r, onTap: () => setState(() => _relation.text = r)),
        ]),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: _pickBirthday,
          icon: const Icon(Icons.cake_rounded),
          label: Text(_birthday == null ? 'Geburtstag (optional)' : 'Geburtstag: ${DateFormat('d. MMMM y', 'de_DE').format(_birthday!)}'),
        ),
        if (_birthday != null) TextButton(onPressed: () => setState(() => _birthday = null), child: const Text('Geburtstag entfernen')),
        const SizedBox(height: 12),
        TextFormField(controller: _phone, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'Telefon (optional)')),
        const SizedBox(height: 12),
        TextFormField(controller: _email, keyboardType: TextInputType.emailAddress, decoration: const InputDecoration(labelText: 'E-Mail (optional)')),
        const SizedBox(height: 12),
        TextFormField(
          controller: _address,
          minLines: 1,
          maxLines: 3,
          decoration: const InputDecoration(labelText: 'Adresse (optional)'),
        ),
        const SizedBox(height: 12),
        TextFormField(
          controller: _notes,
          minLines: 2,
          maxLines: 6,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(labelText: 'Allgemeines (optional)', hintText: 'Vorlieben, Allergien, Kinder, Lieblingsessen …'),
        ),
      ],
    );
  }
}
