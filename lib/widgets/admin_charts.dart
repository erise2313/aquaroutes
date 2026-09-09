import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../constants/admin_theme.dart';
import '../services/admin_analytics_service.dart';

/// Titled container every dashboard chart sits in, so they share one frame
/// instead of each inventing its own heading treatment.
///
/// [emptyMessage] is shown *instead of* the chart when there's nothing to
/// plot. An empty chart with axes and no bars looks like a rendering failure;
/// a sentence explaining why it's empty is information.
class AdminChartCard extends StatelessWidget {
  const AdminChartCard({
    super.key,
    required this.title,
    this.subtitle,
    required this.child,
    this.isEmpty = false,
    this.emptyMessage,
    this.footnote,
    this.height = 220,
  });

  final String title;
  final String? subtitle;
  final Widget child;
  final bool isEmpty;
  final String? emptyMessage;

  /// Caveat printed under the chart -- e.g. that some rows predate the column
  /// the trend is built from, so the reader knows what isn't counted.
  final String? footnote;
  final double height;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            if (subtitle != null) ...[
              const SizedBox(height: 2),
              Text(subtitle!, style: TextStyle(color: AdminTheme.inkNavy.withValues(alpha: 0.6), fontSize: 13)),
            ],
            const SizedBox(height: 16),
            SizedBox(
              height: height,
              child: isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: Text(
                          emptyMessage ?? 'Nothing to show yet.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: AdminTheme.inkNavy.withValues(alpha: 0.55)),
                        ),
                      ),
                    )
                  : child,
            ),
            if (footnote != null) ...[
              const SizedBox(height: 8),
              Text(
                footnote!,
                style: TextStyle(fontSize: 12, color: AdminTheme.inkNavy.withValues(alpha: 0.5), fontStyle: FontStyle.italic),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Monthly bar series. Whole-number axis only -- these are counts of permits
/// and stations, so a "2.5" gridline would be meaningless.
class AdminMonthBarChart extends StatelessWidget {
  const AdminMonthBarChart({super.key, required this.buckets, this.color});

  final List<MonthBucket> buckets;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final barColor = color ?? AdminTheme.chartSeries.first;
    final maxCount = buckets.fold<int>(0, (m, b) => b.count > m ? b.count : m);
    // Always leave headroom so the tallest bar doesn't touch the top edge,
    // and never let the axis collapse to zero height on an all-zero series.
    final maxY = (maxCount == 0 ? 1 : maxCount + 1).toDouble();
    final step = maxY <= 5 ? 1.0 : (maxY / 4).ceilToDouble();

    return BarChart(
      BarChartData(
        maxY: maxY,
        minY: 0,
        alignment: BarChartAlignment.spaceAround,
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          horizontalInterval: step,
          getDrawingHorizontalLine: (_) => FlLine(color: AdminTheme.chartGrid, strokeWidth: 1),
        ),
        borderData: FlBorderData(show: false),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              interval: step,
              reservedSize: 32,
              getTitlesWidget: (value, _) => Text(
                value.toInt().toString(),
                style: TextStyle(color: AdminTheme.chartAxis, fontSize: 12),
              ),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 28,
              getTitlesWidget: (value, _) {
                final i = value.toInt();
                if (i < 0 || i >= buckets.length) return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    buckets[i].label,
                    style: TextStyle(color: AdminTheme.chartAxis, fontSize: 12, fontWeight: FontWeight.w600),
                  ),
                );
              },
            ),
          ),
        ),
        barTouchData: BarTouchData(
          touchTooltipData: BarTouchTooltipData(
            getTooltipColor: (_) => AdminTheme.inkNavy,
            getTooltipItem: (group, _, rod, _) {
              final b = buckets[group.x];
              return BarTooltipItem(
                '${b.label} ${b.monthStart.year}\n${rod.toY.toInt()}',
                const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
              );
            },
          ),
        ),
        barGroups: [
          for (var i = 0; i < buckets.length; i++)
            BarChartGroupData(
              x: i,
              barRods: [
                BarChartRodData(
                  toY: buckets[i].count.toDouble(),
                  color: barColor,
                  width: 18,
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

/// Composition donut with an inline legend -- the legend carries the counts,
/// because a slice without a number can only be read as a rough proportion.
class AdminDonutChart extends StatelessWidget {
  const AdminDonutChart({super.key, required this.slices});

  /// Label -> count, in the order they should be coloured and listed.
  final Map<String, int> slices;

  @override
  Widget build(BuildContext context) {
    final entries = slices.entries.where((e) => e.value > 0).toList();
    final total = entries.fold<int>(0, (sum, e) => sum + e.value);
    if (total == 0) return const SizedBox.shrink();

    return Row(
      children: [
        Expanded(
          flex: 2,
          child: PieChart(
            PieChartData(
              sectionsSpace: 2,
              centerSpaceRadius: 40,
              sections: [
                for (var i = 0; i < entries.length; i++)
                  PieChartSectionData(
                    value: entries[i].value.toDouble(),
                    color: AdminTheme.chartSeries[i % AdminTheme.chartSeries.length],
                    title: '${entries[i].value}',
                    radius: 46,
                    titleStyle: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 14),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          flex: 3,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var i = 0; i < entries.length; i++)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      Container(
                        width: 12,
                        height: 12,
                        decoration: BoxDecoration(
                          color: AdminTheme.chartSeries[i % AdminTheme.chartSeries.length],
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          entries[i].key,
                          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Text('${entries[i].value}', style: TextStyle(fontSize: 13, color: AdminTheme.chartAxis)),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
