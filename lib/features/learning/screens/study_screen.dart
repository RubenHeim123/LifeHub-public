import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:frontend/core/ui/app_actions.dart';
import 'package:frontend/core/ui/app_ui.dart';
import 'package:frontend/core/ui/modern_appbar.dart';
import 'package:frontend/core/ui/theme.dart';
import 'package:frontend/features/learning/models/flash_card.dart';
import 'package:frontend/features/learning/repositories/learning_repository.dart';

/// Öffnet die Lernrunde über die fälligen Karten von [deck] (oder aller Stapel).
/// Offene Meldungen werden ausgeblendet, damit sie die Bewertungsknöpfe nicht verdecken.
Future<void> openStudy(BuildContext context, {required int userid, Deck? deck}) {
  ScaffoldMessenger.maybeOf(context)?.hideCurrentSnackBar();
  return Navigator.of(context).push(MaterialPageRoute(builder: (_) => StudyScreen(userid: userid, deck: deck)));
}

/// Lernrunde: Vorderseite zeigen, aufdecken, mit „Nochmal / Schwer / Gut / Leicht“ bewerten.
/// „Nochmal“-Karten kommen in derselben Runde am Ende wieder dran.
class StudyScreen extends StatefulWidget {
  final int userid;
  final Deck? deck;
  const StudyScreen({super.key, required this.userid, this.deck});

  @override
  State<StudyScreen> createState() => _StudyScreenState();
}

class _StudyScreenState extends State<StudyScreen> {
  late final LearningRepository _repo = context.read<LearningRepository>();
  List<FlashCard>? _queue;
  bool _revealed = false;
  bool _saving = false;
  int _done = 0;
  int _again = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final cards = await _repo.dueCards(widget.userid, deckId: widget.deck?.id);
    if (mounted) setState(() => _queue = cards);
  }

  Future<void> _rate(Rating rating) async {
    final queue = _queue!;
    if (_saving || queue.isEmpty) return;
    setState(() => _saving = true);
    final next = await runGuarded(context, () => _repo.review(queue.first, rating));
    if (!mounted) return;
    setState(() {
      _saving = false;
      if (next == null) return;
      queue.removeAt(0);
      if (rating == Rating.again) {
        queue.add(next);
        _again++;
      } else {
        _done++;
      }
      _revealed = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final queue = _queue;
    return Scaffold(
      appBar: ModernAppBar(title: widget.deck?.name ?? 'Lernen'),
      body: queue == null
          ? Center(child: CircularProgressIndicator(color: c.accent))
          : queue.isEmpty
              ? _finished(context)
              : _card(context, queue),
    );
  }

  Widget _finished(BuildContext context) => EmptyState(
        icon: Icons.celebration_rounded,
        title: 'Fertig für heute',
        message: _done == 0 && _again == 0
            ? 'Gerade ist keine Karte fällig.'
            : '$_done ${_done == 1 ? 'Karte' : 'Karten'} gelernt'
                '${_again == 0 ? '' : ', $_again× „Nochmal“'}. Die nächsten kommen, wenn sie dran sind.',
        action: FilledButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Zurück')),
      );

  Widget _card(BuildContext context, List<FlashCard> queue) {
    final c = AppColors.of(context);
    final t = Theme.of(context).textTheme;
    final card = queue.first;
    final now = DateTime.now();
    final total = _done + queue.length;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Expanded(child: AppProgressBar(value: total == 0 ? 0 : _done / total)),
            const SizedBox(width: 12),
            Text('${queue.length} übrig', style: t.labelMedium),
          ]),
          const SizedBox(height: 16),
          Expanded(
            child: AppCard(
              onTap: _revealed ? null : () => setState(() => _revealed = true),
              padding: const EdgeInsets.all(20),
              child: SingleChildScrollView(
                child: Column(children: [
                  if (card.isNew)
                    Align(
                      alignment: Alignment.centerRight,
                      child: Text('neu', style: t.labelSmall?.copyWith(color: c.accentText)),
                    ),
                  const SizedBox(height: 24),
                  Text(card.front, textAlign: TextAlign.center, style: t.headlineSmall),
                  if (_revealed) ...[
                    const SizedBox(height: 20),
                    Divider(color: c.line),
                    const SizedBox(height: 20),
                    Text(card.back, textAlign: TextAlign.center, style: t.titleLarge?.copyWith(color: c.accentText)),
                  ],
                ]),
              ),
            ),
          ),
          const SizedBox(height: 16),
          if (!_revealed)
            FilledButton(onPressed: () => setState(() => _revealed = true), child: const Text('Antwort zeigen'))
          else
            Row(children: [
              for (final r in Rating.values) ...[
                if (r != Rating.again) const SizedBox(width: 8),
                Expanded(
                  child: _RateButton(
                    rating: r,
                    hint: nextDueLabel(card, r, now),
                    onPressed: _saving ? null : () => _rate(r),
                  ),
                ),
              ],
            ]),
        ]),
      ),
    );
  }
}

class _RateButton extends StatelessWidget {
  final Rating rating;
  final String hint;
  final VoidCallback? onPressed;
  const _RateButton({required this.rating, required this.hint, this.onPressed});

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final color = switch (rating) {
      Rating.again => c.negative,
      Rating.hard => c.streak,
      Rating.good => c.accentText,
      Rating.easy => c.positive,
    };
    return OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        foregroundColor: color,
        side: BorderSide(color: color.withValues(alpha: 0.6)),
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Text(rating.label, maxLines: 1, overflow: TextOverflow.ellipsis),
        Text(hint, style: Theme.of(context).textTheme.labelSmall?.copyWith(color: color)),
      ]),
    );
  }
}
