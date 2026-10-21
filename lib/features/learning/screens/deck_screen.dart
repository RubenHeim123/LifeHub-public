import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import 'package:frontend/core/ui/app_actions.dart';
import 'package:frontend/core/ui/app_ui.dart';
import 'package:frontend/core/ui/modern_appbar.dart';
import 'package:frontend/core/ui/theme.dart';
import 'package:frontend/features/learning/models/flash_card.dart';
import 'package:frontend/features/learning/repositories/learning_repository.dart';
import 'package:frontend/features/learning/screens/learning_screen.dart';
import 'package:frontend/features/learning/screens/study_screen.dart';

/// Ein Stapel: Karten suchen, anlegen, bearbeiten, löschen, viele auf einmal importieren und lernen.
class DeckScreen extends StatefulWidget {
  final int userid;
  final int deckId;
  const DeckScreen({super.key, required this.userid, required this.deckId});

  @override
  State<DeckScreen> createState() => _DeckScreenState();
}

class _DeckScreenState extends State<DeckScreen> {
  late final LearningRepository _repo = context.read<LearningRepository>();
  final _search = TextEditingController();
  Deck? _deck;
  List<FlashCard>? _cards;
  int _loadId = 0;

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
    final decks = await _repo.getDecks(widget.userid);
    final cards = await _repo.getCards(widget.deckId, search: _search.text);
    if (!mounted || loadId != _loadId) return;
    setState(() {
      _deck = decks.where((d) => d.id == widget.deckId).firstOrNull;
      _cards = cards;
    });
  }

  Future<void> _editCard([FlashCard? card]) async {
    final result = await showCardSheet(context,
        card: card ?? FlashCard(userid: widget.userid, deckId: widget.deckId, front: '', back: ''), isNew: card == null);
    if (result == null || !mounted) return;
    await runGuarded(context, () => _repo.saveCard(result), success: card == null ? 'Karte angelegt' : null);
    _load();
  }

  Future<void> _deleteCard(FlashCard card) => deleteWithUndo(
        context,
        label: card.front,
        delete: () => _repo.deleteCard(card.id!),
        restore: () => _repo.restoreCard(card.id!),
        onChanged: _load,
      );

  Future<void> _import() async {
    final text = await showEditorSheet<String>(context, (_) => const _ImportSheet());
    if (text == null || !mounted) return;
    final n = await runGuarded(context, () => _repo.importCards(widget.userid, widget.deckId, text));
    if (n == null || !mounted) return;
    showAppSnack(context, n == 0 ? 'Keine Zeile mit „Vorderseite – Rückseite“ gefunden' : '$n ${n == 1 ? 'Karte' : 'Karten'} importiert',
        error: n == 0);
    _load();
  }

  Future<void> _rename() async {
    final updated = await showDeckSheet(context, userid: widget.userid, deck: _deck);
    if (updated == null || !mounted) return;
    await runGuarded(context, () => _repo.saveDeck(updated));
    _load();
  }

  Future<void> _study() async {
    await openStudy(context, userid: widget.userid, deck: _deck);
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final t = Theme.of(context).textTheme;
    final deck = _deck;
    final cards = _cards;
    final now = DateTime.now();
    return Scaffold(
      appBar: ModernAppBar(title: deck?.name ?? 'Stapel', customActions: [
        if (deck != null) ...[
          IconButton(tooltip: 'Viele Karten importieren', icon: const Icon(Icons.playlist_add_rounded), onPressed: _import),
          IconButton(tooltip: 'Stapel umbenennen', icon: const Icon(Icons.edit_outlined), onPressed: _rename),
        ],
      ]),
      floatingActionButton: deck == null ? null : AppFab(heroTag: 'card-fab', label: 'Karte', onPressed: () => _editCard()),
      body: deck == null || cards == null
          ? Center(child: CircularProgressIndicator(color: c.accent))
          : ListView(padding: pagePadding(context), children: [
              AppCard(
                padding: const EdgeInsets.all(14),
                child: Row(children: [
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(deck.dueCount == 0 ? 'Nichts fällig' : '${deck.dueCount} fällig', style: t.titleMedium),
                      Text('${deck.cardCount} ${deck.cardCount == 1 ? 'Karte' : 'Karten'} im Stapel', style: t.labelMedium),
                    ]),
                  ),
                  FilledButton.icon(
                    onPressed: deck.dueCount == 0 ? null : _study,
                    icon: const Icon(Icons.school_rounded),
                    label: const Text('Lernen'),
                  ),
                ]),
              ),
              const SizedBox(height: 12),
              if (deck.cardCount > 0) ...[
                TextField(
                  controller: _search,
                  onChanged: (_) => _load(),
                  decoration: InputDecoration(
                    hintText: 'Karten durchsuchen',
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
                const SizedBox(height: 12),
              ],
              if (cards.isEmpty)
                _search.text.trim().isEmpty
                    ? EmptyState(
                        icon: Icons.style_outlined,
                        title: 'Noch keine Karten',
                        message: 'Leg Karten einzeln an oder importier viele auf einmal.',
                        action: OutlinedButton.icon(onPressed: _import, icon: const Icon(Icons.playlist_add_rounded), label: const Text('Importieren')),
                      )
                    : EmptyState(icon: Icons.search_off_rounded, title: 'Nichts gefunden', message: 'Keine Karte enthält „${_search.text.trim()}“.'),
              for (final card in cards)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: SwipeTile(
                    id: 'card-${card.id}',
                    onEdit: () => _editCard(card),
                    onDelete: () => _deleteCard(card),
                    child: AppCard(
                      onTap: () => _editCard(card),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      child: Row(children: [
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(card.front, style: t.titleSmall, maxLines: 2, overflow: TextOverflow.ellipsis),
                            const SizedBox(height: 2),
                            Text(card.back, style: t.bodyMedium?.copyWith(color: c.muted), maxLines: 2, overflow: TextOverflow.ellipsis),
                          ]),
                        ),
                        const SizedBox(width: 8),
                        Text(_dueText(card, now), style: t.labelSmall?.copyWith(color: card.isDue(now) ? c.accentText : c.muted)),
                      ]),
                    ),
                  ),
                ),
            ]),
    );
  }
}

String _dueText(FlashCard card, DateTime now) {
  if (card.isNew) return 'neu';
  if (card.isDue(now)) return 'fällig';
  return DateFormat('d. MMM', 'de_DE').format(card.due!);
}

/// Vorder- und Rückseite einer Karte erfassen.
Future<FlashCard?> showCardSheet(BuildContext context, {required FlashCard card, bool isNew = false}) =>
    showEditorSheet<FlashCard>(context, (_) => _CardSheet(card: card, isNew: isNew));

class _CardSheet extends StatefulWidget {
  final FlashCard card;
  final bool isNew;
  const _CardSheet({required this.card, required this.isNew});

  @override
  State<_CardSheet> createState() => _CardSheetState();
}

class _CardSheetState extends State<_CardSheet> {
  final _formKey = GlobalKey<FormState>();
  late final _front = TextEditingController(text: widget.card.front);
  late final _back = TextEditingController(text: widget.card.back);

  @override
  void dispose() {
    _front.dispose();
    _back.dispose();
    super.dispose();
  }

  void _save() {
    if (!_formKey.currentState!.validate()) return;
    Navigator.of(context).pop(widget.card.copyWith(front: _front.text.trim(), back: _back.text.trim()));
  }

  @override
  Widget build(BuildContext context) => EditorSheet(
        formKey: _formKey,
        title: widget.isNew ? 'Neue Karte' : 'Karte bearbeiten',
        onSave: _save,
        children: [
          TextFormField(
            controller: _front,
            autofocus: widget.isNew,
            minLines: 1,
            maxLines: 4,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(labelText: 'Vorderseite', hintText: 'Frage oder Begriff'),
            validator: (v) => (v ?? '').trim().isEmpty ? 'Was steht vorne?' : null,
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _back,
            minLines: 2,
            maxLines: 6,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(labelText: 'Rückseite', hintText: 'Antwort'),
            validator: (v) => (v ?? '').trim().isEmpty ? 'Was steht hinten?' : null,
          ),
        ],
      );
}

class _ImportSheet extends StatefulWidget {
  const _ImportSheet();

  @override
  State<_ImportSheet> createState() => _ImportSheetState();
}

class _ImportSheetState extends State<_ImportSheet> {
  final _text = TextEditingController();

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final n = parseCardLines(_text.text).length;
    return EditorSheet(
      title: 'Karten importieren',
      saveLabel: n == 0 ? 'Importieren' : '$n ${n == 1 ? 'Karte' : 'Karten'} importieren',
      onSave: () => Navigator.of(context).pop(_text.text),
      children: [
        Text(
          'Eine Karte je Zeile: „Vorderseite – Rückseite“. Statt des Strichs gehen auch „;“, „=“ oder ein Tab – '
          'so lassen sich Listen aus Tabellen einfügen.',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppColors.of(context).muted),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _text,
          autofocus: true,
          minLines: 6,
          maxLines: 12,
          onChanged: (_) => setState(() {}),
          decoration: const InputDecoration(hintText: 'el perro – der Hund\nla casa – das Haus'),
        ),
      ],
    );
  }
}
