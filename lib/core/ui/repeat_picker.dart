import 'package:flutter/material.dart';

import 'package:frontend/core/models/repeat.dart';
import 'package:frontend/core/ui/app_ui.dart';
import 'package:frontend/core/ui/form_widgets.dart';

const _weekdays = ['Mo', 'Di', 'Mi', 'Do', 'Fr', 'Sa', 'So'];

/// Wiederholung wählen: einmalig, täglich, wöchentlich (an Wochentagen), monatlich, jährlich –
/// jeweils „alle N …“. [start] ist das erste Datum (Vorgabe für den Wochentag).
class RepeatPicker extends StatelessWidget {
  final Repeat value;
  final DateTime? start;
  final ValueChanged<Repeat> onChanged;
  final List<RepeatFreq> options;

  const RepeatPicker({
    super.key,
    required this.value,
    required this.onChanged,
    this.start,
    this.options = RepeatFreq.values,
  });

  String _unit(RepeatFreq f, int n) => switch (f) {
        RepeatFreq.daily => n == 1 ? 'Tag' : 'Tage',
        RepeatFreq.weekly => n == 1 ? 'Woche' : 'Wochen',
        RepeatFreq.monthly => n == 1 ? 'Monat' : 'Monate',
        RepeatFreq.yearly => n == 1 ? 'Jahr' : 'Jahre',
        RepeatFreq.none => '',
      };

  static String _freqLabel(RepeatFreq f) => switch (f) {
        RepeatFreq.none => 'Einmalig',
        RepeatFreq.daily => 'Täglich',
        RepeatFreq.weekly => 'Wöchentlich',
        RepeatFreq.monthly => 'Monatlich',
        RepeatFreq.yearly => 'Jährlich',
      };

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final n = value.interval < 1 ? 1 : value.interval;
    final days = value.weekdays.isEmpty && start != null ? {start!.weekday} : value.weekdays;
    return FormFieldCard(
      icon: Icons.repeat_rounded,
      label: 'Wiederholung',
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Wrap(spacing: 6, runSpacing: 6, children: [
          for (final f in options)
            AppChip(
              label: _freqLabel(f),
              selected: value.freq == f,
              onTap: () => onChanged(Repeat(f, interval: f == RepeatFreq.none ? 1 : n)),
            ),
        ]),
        if (!value.isNone) ...[
          const SizedBox(height: 8),
          Row(children: [
            Text('Alle', style: t.bodyMedium),
            IconButton(
              tooltip: 'Kürzerer Abstand',
              visualDensity: VisualDensity.compact,
              onPressed: n <= 1 ? null : () => onChanged(Repeat(value.freq, interval: n - 1, weekdays: value.weekdays)),
              icon: const Icon(Icons.remove_circle_outline),
            ),
            Text('$n', style: t.titleMedium),
            IconButton(
              tooltip: 'Längerer Abstand',
              visualDensity: VisualDensity.compact,
              onPressed: n >= 52 ? null : () => onChanged(Repeat(value.freq, interval: n + 1, weekdays: value.weekdays)),
              icon: const Icon(Icons.add_circle_outline),
            ),
            Flexible(child: Text(_unit(value.freq, n), style: t.bodyMedium)),
          ]),
          if (value.freq == RepeatFreq.weekly)
            Wrap(spacing: 6, runSpacing: 6, children: [
              for (var d = 1; d <= 7; d++)
                AppChip(
                  label: _weekdays[d - 1],
                  selected: days.contains(d),
                  onTap: () {
                    final next = {...days};
                    next.contains(d) ? next.remove(d) : next.add(d);
                    if (next.isEmpty) return; // mindestens ein Tag
                    onChanged(Repeat(RepeatFreq.weekly, interval: n, weekdays: next));
                  },
                ),
            ]),
          const SizedBox(height: 6),
          Text(value.label(start), style: t.labelMedium),
        ],
      ]),
    );
  }
}
