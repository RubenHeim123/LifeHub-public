import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:frontend/core/ui/app_ui.dart';
import 'package:frontend/core/ui/theme.dart';
import 'package:frontend/features/journal/models/journal_entry.dart';

/// Farbe einer Stimmung aus den Design-Tokens (hell und dunkel lesbar).
Color moodColor(AppColors c, Mood? mood) => switch (mood) {
      null => c.line,
      Mood.bad => c.negative,
      Mood.meh => c.streak,
      Mood.okay => c.dim,
      Mood.good => c.accent,
      Mood.great => c.positive,
    };

/// Ein Punkt je Tag (ältester links), Farbe nach Stimmung, leer ohne Eintrag.
class MoodStrip extends StatelessWidget {
  final List<(DateTime, Mood?)> days;
  const MoodStrip({super.key, required this.days});

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final fmt = DateFormat('d.M.', 'de_DE');
    return Row(children: [
      for (final (day, mood) in days)
        Expanded(
          child: Semantics(
            label: '${fmt.format(day)}: ${mood?.label ?? 'kein Eintrag'}',
            child: Container(
              height: 18,
              margin: const EdgeInsets.symmetric(horizontal: 1),
              decoration: BoxDecoration(color: moodColor(c, mood), borderRadius: BorderRadius.circular(4)),
            ),
          ),
        ),
    ]);
  }
}

/// „Heute schon geschrieben?“ bzw. Stimmung und Anriss des heutigen Eintrags (Journal und Heute-Screen).
class JournalTodayCard extends StatelessWidget {
  final JournalEntry? today;
  final VoidCallback onTap;
  const JournalTodayCard({super.key, required this.today, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final t = Theme.of(context).textTheme;
    final e = today;
    return AppCard(
      onTap: onTap,
      padding: const EdgeInsets.all(14),
      child: Row(children: [
        e?.mood != null
            ? SizedBox.square(dimension: 44, child: Center(child: Text(e!.mood!.emoji, style: const TextStyle(fontSize: 30))))
            : IconTile(icon: Icons.edit_note_rounded, color: c.accentText),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(e == null ? 'Heute schon geschrieben?' : 'Heute', style: t.titleMedium),
            const SizedBox(height: 2),
            Text(
              e == null ? 'Wie war dein Tag? Tippe hier.' : (e.preview.isEmpty ? e.mood!.label : e.preview),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: t.bodySmall?.copyWith(color: c.muted),
            ),
          ]),
        ),
        Icon(e == null ? Icons.add_rounded : Icons.chevron_right_rounded),
      ]),
    );
  }
}
