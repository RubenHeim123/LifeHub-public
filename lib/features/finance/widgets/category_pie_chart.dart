import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:frontend/core/ui/app_ui.dart';
import 'package:frontend/core/ui/theme.dart';

/// Kuchendiagramm der Ausgabenverteilung nach Kategorien.
class CategoryPieChart extends StatelessWidget {
  final Map<String, double> categoryExpenses;

  const CategoryPieChart({super.key, required this.categoryExpenses});

  static const List<Color> _palette = [
    Color(0xFF5ED99E),
    Color(0xFFBDADFF),
    Color(0xFFF2AF48),
    Color(0xFFFF9189),
    Color(0xFF6CB6FF),
    Color(0xFFE58AC8),
    Color(0xFF4FD1C5),
    Color(0xFFD4D46A),
    Color(0xFFA0A0A8),
    Color(0xFFFFB07A),
    Color(0xFF8FA8FF),
    Color(0xFF9BE58A),
  ];

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final t = Theme.of(context).textTheme;

    if (categoryExpenses.isEmpty) {
      return AppCard(
        padding: const EdgeInsets.all(22),
        child: Center(child: Text('Keine Ausgaben vorhanden', style: t.bodySmall)),
      );
    }

    final total = categoryExpenses.values.fold<double>(0.0, (sum, v) => sum + v);
    final sortedEntries = categoryExpenses.entries.toList()..sort((a, b) => b.value.compareTo(a.value));

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const SectionTitle('Ausgabenverteilung'),
      AppCard(
        padding: const EdgeInsets.all(20),
        child: Column(children: [
          SizedBox(
            height: 200,
            child: Stack(alignment: Alignment.center, children: [
              PieChart(
                PieChartData(
                  sectionsSpace: 3,
                  centerSpaceRadius: 62,
                  sections: List.generate(sortedEntries.length, (i) {
                    final entry = sortedEntries[i];
                    return PieChartSectionData(
                      color: _palette[i % _palette.length],
                      value: entry.value,
                      showTitle: false,
                      radius: 22,
                    );
                  }),
                ),
              ),
              Column(mainAxisSize: MainAxisSize.min, children: [
                Text(formatEuro(total), style: t.headlineMedium),
                Text('AUSGABEN', style: TextStyle(color: c.muted, fontSize: 11, fontFamily: 'monospace')),
              ]),
            ]),
          ),
          const SizedBox(height: 16),
          ...List.generate(sortedEntries.length, (i) {
            final entry = sortedEntries[i];
            final pct = entry.value / total * 100;
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 5),
              child: Row(children: [
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(color: _palette[i % _palette.length], shape: BoxShape.circle),
                ),
                const SizedBox(width: 10),
                Expanded(child: Text(entry.key, style: t.bodyMedium, overflow: TextOverflow.ellipsis)),
                Text(formatEuro(entry.value), style: t.bodyMedium),
                SizedBox(
                  width: 52,
                  child: Text('${pct.toStringAsFixed(0)} %', textAlign: TextAlign.right, style: t.labelMedium),
                ),
              ]),
            );
          }),
        ]),
      ),
    ]);
  }
}
