import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:frontend/core/ui/app_actions.dart';
import 'package:frontend/core/ui/app_ui.dart';
import 'package:frontend/core/ui/theme.dart';
import 'package:frontend/features/auth/models/user.dart';
import 'package:frontend/features/learning/models/flash_card.dart';
import 'package:frontend/features/learning/repositories/learning_repository.dart';
import 'package:frontend/features/learning/screens/deck_screen.dart';
import 'package:frontend/features/learning/screens/study_screen.dart';

/// Lernen im Tab „Planen“: Karteikarten-Stapel mit fälligen Karten.
class LearningScreen extends StatefulWidget {
  final UserModel user;
  const LearningScreen({super.key, required this.user});

  @override
  State<LearningScreen> createState() => _LearningScreenState();
}

class _LearningScreenState extends State<LearningScreen> {
  late final LearningRepository _repo = context.read<LearningRepository>();
  List<Deck>? _decks;
  Object? _error;

  int get _uid => widget.user.uid;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final decks = await _repo.getDecks(_uid);
      if (mounted) {
        setState(() {
          _decks = decks;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  Future<void> _newDeck() async {
    final deck = await showDeckSheet(context, userid: _uid);
    if (deck == null || !mounted) return;
    final id = await runGuarded(context, () => _repo.saveDeck(deck));
    if (id == null || !mounted) return;
    await _openDeck(id);
  }

  Future<void> _openDeck(int id) async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => DeckScreen(userid: _uid, deckId: id)));
    _load();
  }

  Future<void> _study({Deck? deck}) async {
    await openStudy(context, userid: _uid, deck: deck);
    _load();
  }

  Future<void> _editDeck(Deck deck) async {
    final updated = await showDeckSheet(context, userid: _uid, deck: deck);
    if (updated == null || !mounted) return;
    await runGuarded(context, () => _repo.saveDeck(updated));
    _load();
  }

  Future<void> _deleteDeck(Deck deck) async {
    String? at;
    await deleteWithUndo(
      context,
      label: deck.name,
      delete: () async => at = await _repo.deleteDeck(deck.id!),
      restore: () => _repo.restoreDeck(deck.id!, at!),
      onChanged: _load,
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final t = Theme.of(context).textTheme;
    final decks = _decks;
    final due = decks?.fold<int>(0, (s, d) => s + d.dueCount) ?? 0;
    return Scaffold(
      floatingActionButton: AppFab(heroTag: 'learning-fab', label: 'Stapel', onPressed: decks == null ? null : _newDeck),
      body: _error != null
          ? EmptyState(
              icon: Icons.cloud_off_rounded,
              title: 'Laden fehlgeschlagen',
              message: errorText(_error!),
              action: OutlinedButton(onPressed: _load, child: const Text('Erneut versuchen')),
            )
          : decks == null
              ? Center(child: CircularProgressIndicator(color: c.accent))
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: pagePadding(context),
                    children: [
                      if (decks.isEmpty)
                        const EmptyState(
                          icon: Icons.style_rounded,
                          title: 'Noch keine Karteikarten',
                          message: 'Leg einen Stapel an, z. B. „Spanisch“, und füg Karten hinzu – einzeln oder viele auf einmal '
                              'als „Vorderseite – Rückseite“ je Zeile. Fällige Karten fragt die App dich in klugen Abständen ab.',
                        )
                      else ...[
                        AppCard(
                          onTap: due == 0 ? null : () => _study(),
                          padding: const EdgeInsets.all(14),
                          child: Row(children: [
                            IconTile(icon: due == 0 ? Icons.check_circle_rounded : Icons.school_rounded, color: due == 0 ? c.positive : c.accentText),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                Text(due == 0 ? 'Alles gelernt' : '$due ${due == 1 ? 'Karte' : 'Karten'} fällig', style: t.titleMedium),
                                Text(due == 0 ? 'Für jetzt ist nichts mehr dran.' : 'Alle Stapel durchgehen', style: t.labelMedium),
                              ]),
                            ),
                            if (due > 0) FilledButton(onPressed: () => _study(), child: const Text('Lernen')),
                          ]),
                        ),
                        const SizedBox(height: 16),
                        const GroupLabel('Stapel'),
                      ],
                      for (final d in decks)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: SwipeTile(
                            id: 'deck-${d.id}',
                            onEdit: () => _editDeck(d),
                            onDelete: () => _deleteDeck(d),
                            child: AppCard(
                              onTap: () => _openDeck(d.id!),
                              padding: const EdgeInsets.all(14),
                              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                Row(children: [
                                  Expanded(
                                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                      Text(d.name, style: t.titleMedium, maxLines: 1, overflow: TextOverflow.ellipsis),
                                      Text(
                                        '${d.dueCount} fällig · ${d.cardCount} ${d.cardCount == 1 ? 'Karte' : 'Karten'}',
                                        style: t.labelMedium?.copyWith(color: d.dueCount > 0 ? c.accentText : null),
                                      ),
                                    ]),
                                  ),
                                  if (d.dueCount > 0)
                                    OutlinedButton(onPressed: () => _study(deck: d), child: const Text('Lernen'))
                                  else
                                    const Icon(Icons.chevron_right_rounded),
                                ]),
                                if (d.cardCount > 0) ...[
                                  const SizedBox(height: 10),
                                  AppProgressBar(value: 1 - d.dueCount / d.cardCount),
                                ],
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

/// Name eines Stapels erfassen oder ändern.
Future<Deck?> showDeckSheet(BuildContext context, {required int userid, Deck? deck}) =>
    showEditorSheet<Deck>(context, (_) => _DeckSheet(userid: userid, deck: deck));

class _DeckSheet extends StatefulWidget {
  final int userid;
  final Deck? deck;
  const _DeckSheet({required this.userid, this.deck});

  @override
  State<_DeckSheet> createState() => _DeckSheetState();
}

class _DeckSheetState extends State<_DeckSheet> {
  final _formKey = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.deck?.name ?? '');

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _save() {
    if (!_formKey.currentState!.validate()) return;
    Navigator.of(context).pop(Deck(id: widget.deck?.id, userid: widget.userid, name: _name.text.trim(), color: widget.deck?.color));
  }

  @override
  Widget build(BuildContext context) => EditorSheet(
        formKey: _formKey,
        title: widget.deck == null ? 'Neuer Stapel' : 'Stapel umbenennen',
        onSave: _save,
        children: [
          TextFormField(
            controller: _name,
            autofocus: true,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(labelText: 'Name', hintText: 'z. B. Spanisch, Anatomie, Hauptstädte'),
            validator: (v) => (v ?? '').trim().isEmpty ? 'Bitte gib dem Stapel einen Namen' : null,
            onFieldSubmitted: (_) => _save(),
          ),
        ],
      );
}
