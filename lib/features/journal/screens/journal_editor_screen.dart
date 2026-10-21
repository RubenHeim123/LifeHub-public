import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import 'package:frontend/core/models/dates.dart';
import 'package:frontend/core/ui/app_actions.dart';
import 'package:frontend/core/ui/form_widgets.dart';
import 'package:frontend/core/ui/modern_appbar.dart';
import 'package:frontend/core/ui/theme.dart';
import 'package:frontend/features/journal/models/journal_entry.dart';
import 'package:frontend/features/journal/repositories/journal_repository.dart';

/// Öffnet den Journal-Editor für [entry] bzw. den Tag [date] (Standard heute) und kümmert sich
/// um „Löschen“ mit Rückgängig. [onChanged] nach Speichern, Löschen oder Wiederherstellen.
Future<void> openJournalEditor(BuildContext context, {required int userid, JournalEntry? entry, DateTime? date, VoidCallback? onChanged}) async {
  final repo = context.read<JournalRepository>();
  final result = await Navigator.of(context).push<Object>(
    MaterialPageRoute(builder: (_) => JournalEditorScreen(userid: userid, entry: entry, date: date)),
  );
  if (!context.mounted) return;
  if (result is JournalEntry && result.id != null) {
    await deleteWithUndo(
      context,
      label: 'Journal vom ${DateFormat('d. MMMM', 'de_DE').format(result.date)}',
      delete: () => repo.deleteEntry(result.id!),
      restore: () => repo.restoreEntry(result.id!),
      onChanged: onChanged,
    );
  } else if (result == true) {
    onChanged?.call();
  }
}

/// Journal-Eintrag eines Tages: Stimmung, Leitfragen und freier Text. Gibt es für den Tag schon
/// einen Eintrag, wird er geladen und bearbeitet. Liefert `true` nach dem Speichern bzw. den
/// Eintrag selbst bei „Löschen“ (das Löschen mit Rückgängig übernimmt [openJournalEditor]).
class JournalEditorScreen extends StatefulWidget {
  final int userid;
  final JournalEntry? entry;
  final DateTime? date;
  const JournalEditorScreen({super.key, required this.userid, this.entry, this.date});

  @override
  State<JournalEditorScreen> createState() => _JournalEditorScreenState();
}

class _JournalEditorScreenState extends State<JournalEditorScreen> {
  late final JournalRepository _repo = context.read<JournalRepository>();
  JournalEntry? _entry;
  late DateTime _date = dateOnly(widget.entry?.date ?? widget.date ?? DateTime.now());
  Mood? _mood;
  final _answers = [for (final _ in JournalEntry.prompts) TextEditingController()];
  final _text = TextEditingController();
  bool _loading = true;
  bool _saving = false;

  /// Für das gewählte Datum gibt es schon einen anderen Eintrag – Speichern ersetzt ihn.
  bool _replacesOther = false;

  bool get _isNew => _entry?.id == null;

  @override
  void initState() {
    super.initState();
    if (widget.entry != null) {
      _fill(widget.entry!);
      _loading = false;
    } else {
      _loadDay(_date);
    }
  }

  @override
  void dispose() {
    for (final c in _answers) {
      c.dispose();
    }
    _text.dispose();
    super.dispose();
  }

  void _fill(JournalEntry e) {
    _entry = e;
    _date = e.date;
    _mood = e.mood;
    for (var i = 0; i < JournalEntry.prompts.length; i++) {
      _answers[i].text = e.answers[JournalEntry.prompts[i]] ?? '';
    }
    _text.text = e.text;
  }

  bool get _isBlank => _mood == null && _text.text.trim().isEmpty && _answers.every((c) => c.text.trim().isEmpty);

  /// Neuer Eintrag: steht für den Tag schon etwas, wird es geladen (solange noch nichts geschrieben ist).
  Future<void> _loadDay(DateTime day) async {
    final existing = await _repo.getEntry(widget.userid, day);
    if (!mounted) return;
    setState(() {
      _date = day;
      _loading = false;
      if (existing != null && (_isNew && _isBlank)) {
        _fill(existing);
        _replacesOther = false;
      } else {
        _replacesOther = existing != null && existing.id != _entry?.id;
      }
    });
  }

  Future<void> _save() async {
    final entry = JournalEntry(
      id: _entry?.id,
      userid: widget.userid,
      date: _date,
      mood: _mood,
      text: _text.text,
      answers: {for (var i = 0; i < JournalEntry.prompts.length; i++) JournalEntry.prompts[i]: _answers[i].text},
    );
    if (entry.isEmpty) {
      showAppSnack(context, 'Schreib etwas oder wähle eine Stimmung.', error: true);
      return;
    }
    setState(() => _saving = true);
    final navigator = Navigator.of(context);
    final ok = await runGuarded(context, () async {
      await _repo.saveEntry(entry);
      return true;
    });
    if (!mounted) return;
    setState(() => _saving = false);
    if (ok == true) navigator.pop(true);
  }

  static const _promptIcons = [Icons.favorite_outline_rounded, Icons.thumb_up_alt_outlined, Icons.flag_outlined];

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final t = Theme.of(context).textTheme;
    return Scaffold(
      appBar: ModernAppBar(title: _isNew ? 'Neuer Eintrag' : 'Eintrag bearbeiten'),
      body: SafeArea(
        child: _loading
            ? Center(child: CircularProgressIndicator(color: c.accent))
            : SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  FormHeader(
                    icon: Icons.auto_stories_rounded,
                    title: DateFormat('EEEE, d. MMMM', 'de_DE').format(_date),
                    subtitle: 'Wie war dein Tag? Tippe oder diktiere mit dem Mikrofon über der Tastatur.',
                  ),
                  const SizedBox(height: 18),
                  DateField(label: 'Tag', value: _date, onChanged: (d) => _loadDay(dateOnly(d))),
                  if (_replacesOther)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(4, 0, 4, 12),
                      child: Text('Für diesen Tag gibt es schon einen Eintrag – Speichern ersetzt ihn.',
                          style: t.bodySmall?.copyWith(color: c.streak)),
                    ),
                  FormFieldCard(
                    icon: Icons.mood_rounded,
                    label: 'Stimmung',
                    child: Row(children: [
                      for (final m in Mood.values)
                        Expanded(
                          child: _MoodChoice(
                            mood: m,
                            selected: _mood == m,
                            onTap: () => setState(() => _mood = _mood == m ? null : m),
                          ),
                        ),
                    ]),
                  ),
                  for (var i = 0; i < JournalEntry.prompts.length; i++)
                    FormFieldCard(
                      icon: _promptIcons[i],
                      label: JournalEntry.prompts[i],
                      child: TextFormField(
                        controller: _answers[i],
                        minLines: 1,
                        maxLines: 6,
                        textCapitalization: TextCapitalization.sentences,
                        decoration: bareInputDecoration.copyWith(hintText: 'Optional'),
                      ),
                    ),
                  FormFieldCard(
                    icon: Icons.edit_note_rounded,
                    label: 'Freie Gedanken',
                    child: TextFormField(
                      controller: _text,
                      minLines: 4,
                      maxLines: 14,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: bareInputDecoration.copyWith(hintText: 'Was geht dir durch den Kopf?'),
                    ),
                  ),
                  const SizedBox(height: 12),
                  FormActions(
                    isNew: _isNew,
                    busy: _saving,
                    onSave: _save,
                    onDelete: _isNew ? null : () => Navigator.of(context).pop(_entry),
                  ),
                ]),
              ),
      ),
    );
  }
}

class _MoodChoice extends StatelessWidget {
  final Mood mood;
  final bool selected;
  final VoidCallback onTap;
  const _MoodChoice({required this.mood, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Semantics(
      button: true,
      selected: selected,
      label: mood.label,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          margin: const EdgeInsets.symmetric(horizontal: 2),
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: selected ? c.accent.withValues(alpha: 0.22) : null,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: selected ? c.accent : Colors.transparent),
          ),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(mood.emoji, style: const TextStyle(fontSize: 24)),
            const SizedBox(height: 2),
            FittedBox(child: Text(mood.label, style: TextStyle(fontSize: 11, color: selected ? c.text : c.muted))),
          ]),
        ),
      ),
    );
  }
}
