import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../providers/sales_provider.dart';
import '../widgets/navigation_drawer.dart';
import '../models/analytics_models.dart';

class AdvancedInsightsScreen extends StatefulWidget {
  const AdvancedInsightsScreen({Key? key}) : super(key: key);

  @override
  State<AdvancedInsightsScreen> createState() => _AdvancedInsightsScreenState();
}

class _AdvancedInsightsScreenState extends State<AdvancedInsightsScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final TextEditingController _pricingSearchController = TextEditingController();
  final TextEditingController _crmSearchController = TextEditingController();

  String _pricingSearchQuery = '';
  String _crmSearchQuery = '';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _pricingSearchController.addListener(() {
      setState(() {
        _pricingSearchQuery = _pricingSearchController.text.toLowerCase();
      });
    });
    _crmSearchController.addListener(() {
      setState(() {
        _crmSearchQuery = _crmSearchController.text.toLowerCase();
      });
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    _pricingSearchController.dispose();
    _crmSearchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<SalesProvider>(context);

    return Scaffold(
      backgroundColor: const Color(0xFF0F172A), // Deep Slate
      drawer: const AppNavigationDrawer(activeRoute: 'advanced_insights'),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1E293B),
        title: Text(
          'Advanced Insights',
          style: GoogleFonts.outfit(fontWeight: FontWeight.bold, color: Colors.white),
        ),
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          indicatorColor: const Color(0xFF6366F1),
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white38,
          labelStyle: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 13),
          tabs: const [
            Tab(text: 'Pricing Spread', icon: Icon(Icons.difference_outlined, size: 18)),
            Tab(text: 'Customer CRM', icon: Icon(Icons.people_outline, size: 18)),
            Tab(text: 'Dispatch Planner', icon: Icon(Icons.schedule_outlined, size: 18)),
            Tab(text: 'Miti BS Trends', icon: Icon(Icons.calendar_today_outlined, size: 18)),
          ],
        ),
      ),
      body: provider.isLoading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF6366F1)))
          : TabBarView(
              controller: _tabController,
              children: [
                _buildPricingSpreadTab(provider.pricingConsistency),
                _buildCustomerCrmTab(provider.customerRetention),
                _buildDispatchPlannerTab(provider.weekdaySales),
                _buildMitiTrendsTab(provider.mitiMonthlyTrends),
              ],
            ),
    );
  }

  // --- TAB 1: PRICING SPREAD ---
  Widget _buildPricingSpreadTab(List<PricingConsistency> data) {
    final filtered = data.where((item) => item.productName.toLowerCase().contains(_pricingSearchQuery)).toList();

    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        children: [
          _buildSearchBox(_pricingSearchController, 'Search products...'),
          const SizedBox(height: 16),
          Expanded(
            child: filtered.isEmpty
                ? const Center(child: Text('No pricing discrepancies found.', style: TextStyle(color: Colors.white38)))
                : ListView.builder(
                    itemCount: filtered.length,
                    itemBuilder: (context, index) {
                      final item = filtered[index];
                      final isHighSpread = item.rateSpreadPct > 20.0;
                      return Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1E293B),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: isHighSpread ? Colors.redAccent.withOpacity(0.3) : Colors.white.withOpacity(0.05),
                            width: isHighSpread ? 1.5 : 1.0,
                          ),
                        ),
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Expanded(
                                  child: Text(
                                    item.productName,
                                    style: GoogleFonts.outfit(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 15,
                                    ),
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: isHighSpread ? Colors.redAccent.withOpacity(0.15) : const Color(0xFF6366F1).withOpacity(0.15),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    'Spread: ${item.rateSpreadPct.toStringAsFixed(1)}%',
                                    style: GoogleFonts.outfit(
                                      color: isHighSpread ? Colors.redAccent : const Color(0xFF6366F1),
                                      fontWeight: FontWeight.bold,
                                      fontSize: 12,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                _buildPricingItem('Min Rate', 'Rs. ${item.minRate.toStringAsFixed(0)}'),
                                _buildPricingItem('Max Rate', 'Rs. ${item.maxRate.toStringAsFixed(0)}'),
                                _buildPricingItem('Avg Rate', 'Rs. ${item.avgRate.toStringAsFixed(0)}'),
                                _buildPricingItem('Sales Count', '${item.salesCount} times'),
                              ],
                            ),
                            if (isHighSpread) ...[
                              const SizedBox(height: 10),
                              Row(
                                children: [
                                  const Icon(Icons.warning_amber_rounded, color: Colors.redAccent, size: 14),
                                  const SizedBox(width: 4),
                                  Text(
                                    'High pricing leakage detected (>20% spread)',
                                    style: GoogleFonts.outfit(color: Colors.redAccent.withOpacity(0.8), fontSize: 11),
                                  ),
                                ],
                              ),
                            ],
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildPricingItem(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: GoogleFonts.outfit(color: Colors.white38, fontSize: 11)),
        const SizedBox(height: 2),
        Text(value, style: GoogleFonts.outfit(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w500)),
      ],
    );
  }

  // --- TAB 2: CUSTOMER CRM ---
  Widget _buildCustomerCrmTab(List<CustomerRetention> data) {
    final filtered = data.where((item) => item.party.toLowerCase().contains(_crmSearchQuery)).toList();

    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        children: [
          _buildSearchBox(_crmSearchController, 'Search customers...'),
          const SizedBox(height: 16),
          Expanded(
            child: filtered.isEmpty
                ? const Center(child: Text('No customers found.', style: TextStyle(color: Colors.white38)))
                : ListView.builder(
                    itemCount: filtered.length,
                    itemBuilder: (context, index) {
                      final item = filtered[index];
                      
                      // Churn risk classification
                      Color statusColor = const Color(0xFF10B981); // Active - Green
                      String statusText = 'Active';
                      IconData statusIcon = Icons.check_circle_outline;

                      if (item.inactiveDays >= 60) {
                        statusColor = Colors.redAccent;
                        statusText = 'Churned';
                        statusIcon = Icons.cancel_outlined;
                      } else if (item.inactiveDays >= 30) {
                        statusColor = Colors.orangeAccent;
                        statusText = 'At Risk';
                        statusIcon = Icons.error_outline;
                      }

                      return Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1E293B),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: Colors.white.withOpacity(0.05)),
                        ),
                        padding: const EdgeInsets.all(16),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    item.party,
                                    style: GoogleFonts.outfit(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 15,
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Row(
                                    children: [
                                      Text(
                                        'Inactive: ${item.inactiveDays} days',
                                        style: GoogleFonts.outfit(color: Colors.white38, fontSize: 12),
                                      ),
                                      const SizedBox(width: 12),
                                      Text(
                                        'Orders: ${item.totalOrders}',
                                        style: GoogleFonts.outfit(color: Colors.white38, fontSize: 12),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                              decoration: BoxDecoration(
                                color: statusColor.withOpacity(0.12),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: statusColor.withOpacity(0.3)),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(statusIcon, color: statusColor, size: 14),
                                  const SizedBox(width: 4),
                                  Text(
                                    statusText,
                                    style: GoogleFonts.outfit(
                                      color: statusColor,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  // --- TAB 3: DISPATCH PLANNER ---
  Widget _buildDispatchPlannerTab(List<WeekdaySales> data) {
    if (data.isEmpty) {
      return const Center(child: Text('No weekday sales data.', style: TextStyle(color: Colors.white38)));
    }

    // Days are usually returned as English strings or index. Let's arrange them standard Sunday-Friday
    final daysOrder = ['Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday'];
    final Map<String, WeekdaySales> salesMap = {for (var item in data) item.dayOfWeek: item};

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Weekly Logistics Dispatch Planner',
            style: GoogleFonts.outfit(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 6),
          Text(
            'Logistics capacity recommendation based on historical transaction volumes.',
            style: GoogleFonts.outfit(color: Colors.white38, fontSize: 12),
          ),
          const SizedBox(height: 24),
          ...daysOrder.map((day) {
            final daySales = salesMap[day];
            if (daySales == null) return const SizedBox.shrink();

            bool isPeak = day == 'Sunday';
            bool isValley = day == 'Tuesday';
            bool isOffDay = day == 'Saturday';

            Color color = Colors.white24;
            String recText = 'Standard Dispatch Logistics';
            IconData icon = Icons.check_circle_outline;

            if (isPeak) {
              color = const Color(0xFF6366F1);
              recText = '🔥 Peak Dispatch - Recommend Maximum Warehouse Staffing';
              icon = Icons.local_fire_department_outlined;
            } else if (isValley) {
              color = Colors.amber;
              recText = '💤 Slow Day - Ideal for Inventory Audits & Planning';
              icon = Icons.pause_circle_outline;
            } else if (isOffDay) {
              color = Colors.redAccent;
              recText = '❌ Nepal Weekend - Closed (NPR 0 Sales)';
              icon = Icons.cancel_outlined;
            }

            return Container(
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: const Color(0xFF1E293B),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: isPeak ? const Color(0xFF6366F1).withOpacity(0.3) : Colors.white.withOpacity(0.05)),
              ),
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Icon(icon, color: color, size: 18),
                          const SizedBox(width: 8),
                          Text(
                            day,
                            style: GoogleFonts.outfit(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                        ],
                      ),
                      Text(
                        'Sales: ' + NumberFormat.compactCurrency(symbol: 'Rs. ').format(daySales.totalSales),
                        style: GoogleFonts.outfit(
                          color: isPeak ? const Color(0xFF6366F1) : Colors.white70,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(
                    recText,
                    style: GoogleFonts.outfit(
                      color: isPeak || isValley || isOffDay ? color : Colors.white50,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            );
          }).toList(),
        ],
      ),
    );
  }

  // --- TAB 4: MITI TRENDS ---
  Widget _buildMitiTrendsTab(List<MitiMonthlyTrend> data) {
    if (data.isEmpty) {
      return const Center(child: Text('No Nepali calendar trends available.', style: TextStyle(color: Colors.white38)));
    }

    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4.0, vertical: 8.0),
            child: Text(
              'Nepali Calendar (Bikram Sambat) Monthly Growth',
              style: GoogleFonts.outfit(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ),
          const SizedBox(height: 12),
          Table(
            columnWidths: const {
              0: FlexColumnWidth(1.2),
              1: FlexColumnWidth(1.5),
              2: FlexColumnWidth(1.5),
              3: FlexColumnWidth(1),
            },
            children: [
              TableRow(
                decoration: const BoxDecoration(
                  border: Border(bottom: BorderSide(color: Colors.white10, width: 1)),
                ),
                children: [
                  _tableHeader('Miti BS'),
                  _tableHeader('Sales Value'),
                  _tableHeader('Est. Profit'),
                  _tableHeader('Margin'),
                ],
              ),
            ],
          ),
          Expanded(
            child: SingleChildScrollView(
              child: Table(
                columnWidths: const {
                  0: FlexColumnWidth(1.2),
                  1: FlexColumnWidth(1.5),
                  2: FlexColumnWidth(1.5),
                  3: FlexColumnWidth(1),
                },
                children: data.map((item) {
                  final double margin = item.monthlySales > 0 ? (item.monthlyProfit / item.monthlySales) * 100 : 0.0;
                  return TableRow(
                    children: [
                      _tableCell('${item.monthName} ${item.year}'),
                      _tableCell(NumberFormat.compactCurrency(symbol: 'Rs. ').format(item.monthlySales)),
                      _tableCell(NumberFormat.compactCurrency(symbol: 'Rs. ').format(item.monthlyProfit)),
                      _tableCell('${margin.toStringAsFixed(1)}%', isAccent: true),
                    ],
                  );
                }).toList(),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // --- REUSABLE CARD & WIDGET HELPERS ---
  Widget _buildSearchBox(TextEditingController controller, String hint) {
    return TextField(
      controller: controller,
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: Colors.white24, fontSize: 14),
        prefixIcon: const Icon(Icons.search, color: Colors.white38, size: 18),
        filled: true,
        fillColor: const Color(0xFF1E293B),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        contentPadding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
      ),
    );
  }

  Widget _tableHeader(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: Text(
        text,
        style: GoogleFonts.outfit(color: Colors.white38, fontSize: 12, fontWeight: FontWeight.w500),
      ),
    );
  }

  Widget _tableCell(String text, {bool isAccent = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12.0),
      child: Text(
        text,
        style: GoogleFonts.outfit(
          color: isAccent ? const Color(0xFF10B981) : Colors.white70,
          fontSize: 13,
          fontWeight: isAccent ? FontWeight.w600 : FontWeight.w400,
        ),
      ),
    );
  }
}
