import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:frontend/core/ui/app_ui.dart';
import 'package:frontend/core/ui/modern_appbar.dart';
import 'package:frontend/core/ui/theme.dart';

/// A bar chart widget showing monthly sums over the last 12 months
/// for a single category.
class CategoryBarChart extends StatelessWidget {
  final List<FlSpot> data;
  final String selectedCategory;
  final Color barColor;
  final dynamic user;

  const CategoryBarChart({
    super.key,
    required this.data,
    required this.selectedCategory,
    required this.user,
    this.barColor = AppTheme.primary,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final labelColor = theme.textTheme.bodySmall?.color ?? Colors.grey;
    final DateTime now = DateTime.now();
    final List<String> monthNames = List.generate(12, (index) {
      final DateTime date = DateTime(now.year, now.month - 11 + index);
      return "${date.month}/${date.year % 100}";
    });

    // Aggregate FlSpot list into monthly totals
    final Map<int, double> monthly = {for (var i = 0; i < 12; i++) i: 0.0};
    for (final s in data) {
      final idx = s.x.toInt().clamp(0, 11);
      monthly[idx] = (monthly[idx] ?? 0) + s.y;
    }

    final double totalSum = monthly.values.fold<double>(0.0, (prev, e) => prev + e);
    final String formattedTotal = formatEuro(totalSum, decimals: 2);

    double minValue = monthly.values.fold<double>(0.0, (prev, n) => n < prev ? n : prev);
    double maxValue = monthly.values.fold<double>(0.0, (prev, n) => n > prev ? n : prev);
    if (minValue == 0 && maxValue == 0) { minValue = -1; maxValue = 1; }
    final double range = maxValue - minValue;
    final double padding = range * 0.12;
    minValue -= padding;
    maxValue += padding;

    return Scaffold(
      appBar: ModernAppBar(title: selectedCategory),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            const SizedBox(height: 8),
            // ─── Summary Card ─────────────────────────────────────────────
            Container(
              decoration: AppTheme.cardDecoration(context),
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(selectedCategory, style: theme.textTheme.titleMedium),
                        const SizedBox(height: 4),
                        Text('Monatliche Summen (12 Monate)', style: theme.textTheme.labelSmall),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(formattedTotal, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: barColor)),
                      Text('Summe gesamt', style: theme.textTheme.labelSmall),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            // ─── Bar Chart ────────────────────────────────────────────────
            Container(
              decoration: AppTheme.cardDecoration(context),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 18),
              child: Column(
                children: [
                  SizedBox(
                    height: 320,
                    child: BarChart(
                      BarChartData(
                        minY: minValue,
                        maxY: maxValue,
                        barGroups: List.generate(12, (i) {
                          final val = monthly[i] ?? 0.0;
                          return BarChartGroupData(
                            x: i,
                            barsSpace: 6,
                            barRods: [
                              BarChartRodData(
                                toY: val,
                                color: barColor,
                                width: 18,
                                borderRadius: BorderRadius.circular(6),
                                backDrawRodData: BackgroundBarChartRodData(
                                  show: true,
                                  toY: maxValue,
                                  color: labelColor.withValues(alpha: 0.06),
                                ),
                              ),
                            ],
                          );
                        }),
                        gridData: FlGridData(
                          show: true,
                          horizontalInterval: (maxValue - minValue) / 4,
                          getDrawingHorizontalLine: (value) => FlLine(
                              color: labelColor.withValues(alpha: 0.12), strokeWidth: 1),
                          drawVerticalLine: false,
                        ),
                        titlesData: FlTitlesData(
                          bottomTitles: AxisTitles(
                            sideTitles: SideTitles(
                              showTitles: true,
                              reservedSize: 36,
                              getTitlesWidget: (value, meta) {
                                final idx = value.toInt();
                                if (idx < 0 || idx >= monthNames.length) return const SizedBox.shrink();
                                if (idx % 3 != 0) return const SizedBox.shrink();
                                return SideTitleWidget(
                                  meta: meta,
                                  space: 8.0,
                                  child: Transform.rotate(
                                    angle: -0.2,
                                    child: Text(monthNames[idx],
                                        style: TextStyle(color: labelColor, fontSize: 11)),
                                  ),
                                );
                              },
                            ),
                          ),
                          leftTitles: AxisTitles(
                            sideTitles: SideTitles(
                              showTitles: true,
                              reservedSize: 44,
                              interval: (maxValue - minValue) / 4,
                              getTitlesWidget: (value, meta) {
                                return Text(value.toStringAsFixed(0),
                                    style: TextStyle(color: labelColor, fontSize: 12));
                              },
                            ),
                          ),
                          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                        ),
                        borderData: FlBorderData(
                          show: true,
                          border: Border(
                            bottom: BorderSide(color: labelColor.withValues(alpha: 0.2)),
                            left: const BorderSide(color: Colors.transparent),
                            right: const BorderSide(color: Colors.transparent),
                            top: const BorderSide(color: Colors.transparent),
                          ),
                        ),
                        barTouchData: BarTouchData(
                          enabled: true,
                          touchTooltipData: BarTouchTooltipData(
                            getTooltipItem: (group, groupIndex, rod, rodIndex) {
                              final monthLabel = monthNames[group.x.toInt()];
                              final value = rod.toY;
                              return BarTooltipItem(
                                '$monthLabel\n${value.toStringAsFixed(2)}',
                                const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                              );
                            },
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Datenpunkte: ${data.length}', style: theme.textTheme.labelSmall),
                      Text('Stand: ${now.day}.${now.month}.${now.year}', style: theme.textTheme.labelSmall),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}
