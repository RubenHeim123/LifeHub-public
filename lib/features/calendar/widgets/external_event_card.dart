import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:frontend/core/services/device_calendar_service.dart';
import 'package:frontend/core/ui/app_ui.dart';
import 'package:frontend/core/ui/theme.dart';

/// Handy-Termine nach Kalendertag; mehrtägige erscheinen an jedem Tag (höchstens 31).
Map<DateTime, List<ExternalEvent>> groupExternalByDay(List<ExternalEvent> events) {
  final out = <DateTime, List<ExternalEvent>>{};
  for (final e in events) {
    var day = e.day;
    // Ganztägige enden am Folgetag 0 Uhr (exklusiv), andere am letzten Tag
    final last = e.allDay ? DateTime(e.end.year, e.end.month, e.end.day - 1) : DateTime(e.end.year, e.end.month, e.end.day);
    for (var i = 0; i < 31; i++) {
      out.putIfAbsent(day, () => []).add(e);
      day = DateTime(day.year, day.month, day.day + 1);
      if (day.isAfter(last)) break;
    }
  }
  return out;
}

/// Ein Termin aus dem Handy-Kalender – in der Farbe seines Kalenders, nur zum Ansehen
/// (bearbeitet wird er im jeweiligen Kalender).
class ExternalEventCard extends StatelessWidget {
  final ExternalEvent event;
  const ExternalEventCard({super.key, required this.event});

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final t = Theme.of(context).textTheme;
    final e = event;
    final color = Color(e.color | 0xFF000000);
    final time = DateFormat('HH:mm');
    return AppCard(
      onTap: () => showDetails(context),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: IntrinsicHeight(
        child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Container(width: 4, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2))),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
              Text(e.title.isEmpty ? '(ohne Titel)' : e.title, style: t.titleMedium),
              Text(
                [e.calendarName, if (e.location?.isNotEmpty ?? false) e.location!].join(' · '),
                style: t.labelMedium?.copyWith(color: c.muted),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ]),
          ),
          const SizedBox(width: 12),
          Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
            if (e.allDay) ...[
              Icon(Icons.event_rounded, color: color),
              const SizedBox(height: 2),
              Text('Ganztägig', style: t.labelMedium),
            ] else ...[
              Text(time.format(e.start), style: t.titleMedium),
              const SizedBox(height: 2),
              Text('bis ${time.format(e.end)}', style: t.labelMedium),
            ],
          ]),
        ]),
      ),
    );
  }

  /// Details nur zum Ansehen (Bottom Sheet).
  Future<void> showDetails(BuildContext context) {
    final e = event;
    final t = Theme.of(context).textTheme;
    final when = e.allDay
        ? DateFormat('EEEE, d. MMMM', 'de_DE').format(e.start)
        : '${DateFormat('EEEE, d. MMMM · HH:mm', 'de_DE').format(e.start)} – ${DateFormat('HH:mm').format(e.end)}';
    return showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(e.title.isEmpty ? '(ohne Titel)' : e.title, style: t.titleLarge),
            const SizedBox(height: 6),
            Text(when, style: t.bodyMedium),
            if (e.location?.isNotEmpty ?? false) Text(e.location!, style: t.bodyMedium),
            if (e.description?.isNotEmpty ?? false) ...[
              const SizedBox(height: 8),
              Text(e.description!, style: t.bodySmall),
            ],
            const SizedBox(height: 12),
            Text('Aus deinem Handy-Kalender „${e.calendarName}“ – ändern kannst du ihn dort.',
                style: t.labelMedium?.copyWith(color: AppColors.of(ctx).muted)),
          ]),
        ),
      ),
    );
  }
}
