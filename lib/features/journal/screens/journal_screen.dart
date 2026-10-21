import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import 'package:frontend/core/models/dates.dart';
import 'package:frontend/core/ui/app_actions.dart';
import 'package:frontend/core/ui/app_ui.dart';
import 'package:frontend/core/ui/theme.dart';
import 'package:frontend/features/auth/models/user.dart';
import 'package:frontend/features/journal/models/journal_entry.dart';
import 'package:frontend/features/journal/repositories/journal_repository.dart';
import 'package:frontend/features/journal/screens/journal_editor_screen.dart';
import 'package:frontend/features/journal/widgets/journal_widgets.dart';

/// Journal im Tab „Planen“: heutiger Eintrag, Stimmung der letzten 30 Tage, Erinnerung,
/// Suche und alle Einträge nach Monat.
class JournalScreen extends StatefulWidget {
  final UserModel user;
  const JournalScreen({super.key, required this.user});

  @override
  State<JournalScreen> createState() => _JournalScreenState();
}

class _JournalScreenState extends State<JournalScreen> {
  late final JournalRepository _repo = context.read<JournalRepository>();
  final _search = TextEditingController();
  List<JournalEntry>? _entries;
  JournalEntry? _today;
  List<(DateTime, Mood?)> _moods = const [];
  (int, int)? _reminder;
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
      final entries = await _repo.getEntries(_uid, search: _search.text);
      final today = await _repo.getEntry(_uid, DateTime.now());
      final moods = await _repo.moodSeries(_uid);
      final reminder = await _repo.getReminder(_uid);
      if (!mounted || loadId != _loadId) return;
      setState(() {
        _entries = entries;
        _today = today;
        _moods = moods;
        _reminder = reminder;
        _error = null;
      });
    } catch (e) {
      if (mounted && loadId == _loadId) setState(() => _error = e);
    }
  }

  Future<void> _open({JournalEntry? entry, DateTime? date}) =>
      openJournalEditor(context, userid: _uid, entry: entry, date: date, onChanged: _load);

  Future<void> _delete(JournalEntry e) => deleteWithUndo(
        context,
        label: 'Journal vom ${DateFormat('d. MMMM', 'de_DE').format(e.date)}',
        delete: () => _repo.deleteEntry(e.id!),
        restore: () => _repo.restoreEntry(e.id!),
        onChanged: _load,
      );

  Future<void> _editReminder() async {
    final current = _reminder;
    final choice = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            leading: const Icon(Icons.schedule_rounded),
            title: Text(current == null ? 'Täglich erinnern …' : 'Uhrzeit ändern'),
            onTap: () => Navigator.pop(ctx, 'time'),
          ),
          if (current != null)
            ListTile(
              leading: const Icon(Icons.notifications_off_outlined),
              title: const Text('Erinnerung ausschalten'),
              onTap: () => Navigator.pop(ctx, 'off'),
            ),
        ]),
      ),
    );
    if (!mounted || choice == null) return;
    if (choice == 'off') {
      await runGuarded(context, () => _repo.setReminder(_uid, null), success: 'Journal-Erinnerung ausgeschaltet');
    } else {
      final picked = await showTimePicker(
        context: context,
        initialTime: current == null ? const TimeOfDay(hour: 21, minute: 0) : TimeOfDay(hour: current.$1, minute: current.$2),
        helpText: 'Täglich erinnern um',
      );
      if (picked == null || !mounted) return;
      await runGuarded(context, () => _repo.setReminder(_uid, (picked.hour, picked.minute)),
          success: 'Erinnerung täglich um ${_time((picked.hour, picked.minute))} Uhr');
    }
    _load();
  }

  static String _time((int, int) t) => '${t.$1.toString().padLeft(2, '0')}:${t.$2.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final entries = _entries;
    return Scaffold(
      floatingActionButton: AppFab(heroTag: 'journal-fab', label: 'Eintrag', onPressed: entries == null ? null : () => _open()),
      body: _error != null
          ? EmptyState(
              icon: Icons.cloud_off_rounded,
              title: 'Laden fehlgeschlagen',
              message: errorText(_error!),
              action: OutlinedButton(onPressed: _load, child: const Text('Erneut versuchen')),
            )
          : entries == null
              ? Center(child: CircularProgressIndicator(color: c.accent))
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: pagePadding(context),
                    children: [
                      JournalTodayCard(today: _today, onTap: () => _open(entry: _today, date: DateTime.now())),
                      const SizedBox(height: 10),
                      _moodCard(context),
                      const SizedBox(height: 10),
                      _reminderCard(context),
                      const SizedBox(height: 16),
                      TextField(
                        controller: _search,
                        onChanged: (_) => _load(),
                        decoration: InputDecoration(
                          hintText: 'Im Journal suchen',
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
                      if (entries.isEmpty)
                        _search.text.trim().isEmpty
                            ? const EmptyState(
                                icon: Icons.auto_stories_rounded,
                                title: 'Noch keine Einträge',
                                message: 'Halte fest, wie dein Tag war – ein paar Sätze reichen. '
                                    'Mit dem Mikrofon über der Tastatur kannst du auch diktieren.',
                              )
                            : EmptyState(icon: Icons.search_off_rounded, title: 'Nichts gefunden', message: 'Kein Eintrag enthält „${_search.text.trim()}“.'),
                      ..._entryList(context, entries),
                    ],
                  ),
                ),
    );
  }

  Widget _moodCard(BuildContext context) {
    final c = AppColors.of(context);
    final t = Theme.of(context).textTheme;
    final rated = _moods.where((d) => d.$2 != null).toList();
    final avg = rated.isEmpty ? null : rated.fold<int>(0, (s, d) => s + d.$2!.value) / rated.length;
    return AppCard(
      padding: const EdgeInsets.all(14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text('Stimmung · 30 Tage', style: t.titleSmall)),
          Text(
            avg == null ? 'noch keine' : 'Ø ${Mood.fromValue(avg.round())!.emoji} · ${rated.length} ${rated.length == 1 ? 'Tag' : 'Tage'}',
            style: t.labelMedium?.copyWith(color: c.muted),
          ),
        ]),
        const SizedBox(height: 10),
        MoodStrip(days: _moods),
      ]),
    );
  }

  Widget _reminderCard(BuildContext context) {
    final c = AppColors.of(context);
    final t = Theme.of(context).textTheme;
    final r = _reminder;
    return AppCard(
      onTap: _editReminder,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(children: [
        Icon(r == null ? Icons.notifications_none_rounded : Icons.notifications_active_rounded, color: r == null ? c.muted : c.accentText),
        const SizedBox(width: 12),
        Expanded(child: Text('Erinnerung', style: t.titleSmall)),
        Text(r == null ? 'aus' : 'täglich ${_time(r)} Uhr', style: t.labelMedium?.copyWith(color: c.muted)),
        const Icon(Icons.chevron_right_rounded),
      ]),
    );
  }

  List<Widget> _entryList(BuildContext context, List<JournalEntry> entries) {
    final c = AppColors.of(context);
    final t = Theme.of(context).textTheme;
    final month = DateFormat('MMMM yyyy', 'de_DE');
    final weekday = DateFormat('E', 'de_DE');
    final widgets = <Widget>[];
    String? group;
    for (final e in entries) {
      final label = month.format(e.date);
      if (label != group) {
        group = label;
        widgets.add(Padding(padding: EdgeInsets.only(top: widgets.isEmpty ? 0 : 8), child: GroupLabel(label)));
      }
      final isToday = daysBetween(e.date, DateTime.now()) == 0;
      widgets.add(Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: SwipeTile(
          id: 'journal-${e.id}',
          onEdit: () => _open(entry: e),
          onDelete: () => _delete(e),
          child: AppCard(
            onTap: () => _open(entry: e),
            padding: const EdgeInsets.all(14),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              SizedBox(
                width: 44,
                child: Column(children: [
                  Text('${e.date.day}', style: t.titleLarge?.copyWith(color: isToday ? c.accentText : null)),
                  Text(weekday.format(e.date), style: t.labelSmall?.copyWith(color: c.muted)),
                ]),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  if (e.mood != null)
                    Row(children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(color: moodColor(c, e.mood), shape: BoxShape.circle),
                      ),
                      const SizedBox(width: 6),
                      Text('${e.mood!.emoji} ${e.mood!.label}', style: t.labelMedium),
                    ]),
                  if (e.preview.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(e.preview, maxLines: 2, overflow: TextOverflow.ellipsis, style: t.bodyMedium),
                  ],
                ]),
              ),
            ]),
          ),
        ),
      ));
    }
    return widgets;
  }
}
