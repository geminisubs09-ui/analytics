import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../models/analytics_models.dart';
import '../utils/formatters.dart';

class SalesTrendChart extends StatelessWidget {
  final List<DailyTrend> trends;

  const SalesTrendChart({Key? key, required this.trends}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    if (trends.isEmpty) {
      return const Center(
        child: Text('No daily sales trend data available.', style: TextStyle(color: Colors.white60)),
      );
    }

    final currencyFormatter = NumberFormat.compact();
    final double maxSales = trends.map((e) => e.dailySales).reduce((a, b) => a > b ? a : b);
    final double maxY = maxSales * 1.2; // Add padding

    // Take at most 30 points for readable chart
    final displayTrends = trends.length > 30 
        ? trends.sublist(trends.length - 30) 
        : trends;

    final List<FlSpot> salesSpots = [];
    final List<FlSpot> profitSpots = [];

    for (int i = 0; i < displayTrends.length; i++) {
      salesSpots.add(FlSpot(i.toDouble(), displayTrends[i].dailySales));
      profitSpots.add(FlSpot(i.toDouble(), displayTrends[i].dailyProfit));
    }

    return LineChart(
      LineChartData(
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          getDrawingHorizontalLine: (value) => FlLine(
            color: Colors.white.withOpacity(0.05),
            strokeWidth: 1.0,
          ),
        ),
        titlesData: FlTitlesData(
          show: true,
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 30,
              interval: 5,
              getTitlesWidget: (value, meta) {
                final int idx = value.toInt();
                if (idx >= 0 && idx < displayTrends.length) {
                  final date = DateTime.tryParse(displayTrends[idx].dateStr);
                  final label = date != null ? DateFormat('MMM dd').format(date) : displayTrends[idx].dateStr;
                  return SideTitleWidget(
                    axisSide: meta.axisSide,
                    space: 8,
                    child: Text(
                      label,
                      style: GoogleFonts.outfit(color: Colors.grey[500], fontSize: 10),
                    ),
                  );
                }
                return const Text('');
              },
            ),
          ),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 40,
              getTitlesWidget: (value, meta) {
                return SideTitleWidget(
                  axisSide: meta.axisSide,
                  space: 8,
                  child: Text(
                    Formatters.formatNepaliCurrency(value),
                    style: GoogleFonts.outfit(color: Colors.grey[500], fontSize: 10),
                  ),
                );
              },
            ),
          ),
        ),
        borderData: FlBorderData(show: false),
        minX: 0,
        maxX: (displayTrends.length - 1).toDouble(),
        minY: 0,
        maxY: maxY,
        lineBarsData: [
          // Sales Line
          LineChartBarData(
            spots: salesSpots,
            isCurved: true,
            color: const Color(0xFF6366F1),
            barWidth: 3,
            isStrokeCapRound: true,
            dotData: const FlDotData(show: false),
            belowBarData: BarAreaData(
              show: true,
              color: const Color(0xFF6366F1).withOpacity(0.1),
            ),
          ),
          // Profit Line
          LineChartBarData(
            spots: profitSpots,
            isCurved: true,
            color: const Color(0xFF10B981),
            barWidth: 3,
            isStrokeCapRound: true,
            dotData: const FlDotData(show: false),
            belowBarData: BarAreaData(
              show: true,
              color: const Color(0xFF10B981).withOpacity(0.1),
            ),
          ),
        ],
        lineTouchData: LineTouchData(
          touchTooltipData: LineTouchTooltipData(
            tooltipBgColor: Colors.grey[900]!.withOpacity(0.9),
            getTooltipItems: (touchedSpots) {
              return touchedSpots.map((spot) {
                final isSales = spot.barIndex == 0;
                final label = isSales ? 'Sales' : 'Profit';
                return LineTooltipItem(
                  '$label: ${Formatters.formatNepaliCurrency(spot.y)}',
                  GoogleFonts.outfit(
                    color: isSales ? const Color(0xFF818CF8) : const Color(0xFF34D399),
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                );
              }).toList();
            },
          ),
        ),
      ),
    );
  }
}

class WeekdaySalesChart extends StatelessWidget {
  final List<WeekdaySales> sales;

  const WeekdaySalesChart({Key? key, required this.sales}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    if (sales.isEmpty) {
      return const Center(
        child: Text('No weekday sales data available.', style: TextStyle(color: Colors.white60)),
      );
    }

    final double maxSales = sales.map((e) => e.totalSales).reduce((a, b) => a > b ? a : b);
    final double maxY = maxSales * 1.15;
    final currencyFormatter = NumberFormat.compact();

    // Map order for days
    final List<String> weekDaysOrder = [
      'Sunday',
      'Monday',
      'Tuesday',
      'Wednesday',
      'Thursday',
      'Friday',
      'Saturday'
    ];

    final Map<String, WeekdaySales> dayMap = {
      for (var s in sales) s.dayOfWeek: s
    };

    final List<BarChartGroupData> barGroups = [];
    for (int i = 0; i < weekDaysOrder.length; i++) {
      final String day = weekDaysOrder[i];
      final double val = dayMap[day]?.totalSales ?? 0.0;

      // Color coding: Sunday (peak dispatch) indigo, Tuesday (slow day) orange, others greyish
      Color barColor = const Color(0xFF4B5563);
      if (day == 'Sunday') {
        barColor = const Color(0xFF6366F1); // Indigo
      } else if (day == 'Tuesday') {
        barColor = const Color(0xFFF59E0B); // Amber
      } else if (day == 'Saturday') {
        barColor = Colors.red[900]!.withOpacity(0.4); // Closed/low
      } else if (val > 0) {
        barColor = const Color(0xFF818CF8); // Secondary blue
      }

      barGroups.add(
        BarChartGroupData(
          x: i,
          barRods: [
            BarChartRodData(
              toY: val,
              color: barColor,
              width: 14,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(4),
                topRight: Radius.circular(4),
              ),
              backDrawRodData: BackgroundBarChartRodData(
                show: true,
                toY: maxY,
                color: Colors.white.withOpacity(0.02),
              ),
            ),
          ],
        ),
      );
    }

    return BarChart(
      BarChartData(
        gridData: const FlGridData(show: false),
        borderData: FlBorderData(show: false),
        maxY: maxY,
        titlesData: FlTitlesData(
          show: true,
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 30,
              getTitlesWidget: (value, meta) {
                final int idx = value.toInt();
                if (idx >= 0 && idx < weekDaysOrder.length) {
                  final String day = weekDaysOrder[idx];
                  return SideTitleWidget(
                    axisSide: meta.axisSide,
                    space: 8,
                    child: Text(
                      day.substring(0, 3),
                      style: GoogleFonts.outfit(
                        color: Colors.grey[500],
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  );
                }
                return const Text('');
              },
            ),
          ),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 40,
              getTitlesWidget: (value, meta) {
                return SideTitleWidget(
                  axisSide: meta.axisSide,
                  space: 8,
                  child: Text(
                    Formatters.formatNepaliCurrency(value),
                    style: GoogleFonts.outfit(color: Colors.grey[500], fontSize: 10),
                  ),
                );
              },
            ),
          ),
        ),
        barTouchData: BarTouchData(
          touchTooltipData: BarTouchTooltipData(
            tooltipBgColor: Colors.grey[900]!.withOpacity(0.9),
            getTooltipItem: (group, groupIndex, rod, rodIndex) {
              final String day = weekDaysOrder[group.x.toInt()];
              return BarTooltipItem(
                '$day\n${Formatters.formatNepaliCurrency(rod.toY)}',
                GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
              );
            },
          ),
        ),
        barGroups: barGroups,
      ),
    );
  }
}

class GroupSalesChart extends StatelessWidget {
  final List<GroupSales> groups;

  const GroupSalesChart({Key? key, required this.groups}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    if (groups.isEmpty) {
      return const Center(
        child: Text('No group sales data available.', style: TextStyle(color: Colors.white60)),
      );
    }

    final sortedGroups = List<GroupSales>.from(groups)
      ..sort((a, b) => b.totalSalesValue.compareTo(a.totalSalesValue));

    // Limit to top 5 groups for chart clarity
    final displayGroups = sortedGroups.take(5).toList();

    return PieChart(
      PieChartData(
        sectionsSpace: 4,
        centerSpaceRadius: 40,
        sections: List.generate(displayGroups.length, (i) {
          final group = displayGroups[i];
          final double val = group.totalSalesValue;
          final List<Color> sliceColors = [
            const Color(0xFF6366F1), // Indigo
            const Color(0xFF10B981), // Emerald
            const Color(0xFFF59E0B), // Amber
            const Color(0xFFEC4899), // Pink
            const Color(0xFF3B82F6), // Blue
          ];

          return PieChartSectionData(
            color: sliceColors[i % sliceColors.length],
            value: val,
            title: '${group.productGroup}\n${Formatters.formatNepaliCurrency(val)}',
            radius: 50,
            titleStyle: GoogleFonts.outfit(
              color: Colors.white,
              fontSize: 10,
              fontWeight: FontWeight.w600,
            ),
          );
        }),
      ),
    );
  }
}
