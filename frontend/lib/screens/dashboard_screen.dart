import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../providers/sales_provider.dart';
import '../widgets/responsive_grid.dart';
import '../widgets/metric_card.dart';
import '../widgets/sales_chart.dart';
import '../models/analytics_models.dart';
import 'upload_screen.dart';
import 'admin_map_screen.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({Key? key}) : super(key: key);

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  String _selectedYear = 'All Years';
  String _selectedMonth = 'All Months';

  // Sorting State for Products
  String _sortColumn = 'Sales Val';
  bool _sortAscending = false;

  // Local state for filtering top products by volume
  String _selectedProductGroup = 'All';
  List<ProductSales>? _groupFilteredProducts;
  bool _isLoadingGroupProducts = false;

  final List<String> _years = ['All Years', '2024', '2025', '2026'];
  final List<String> _months = [
    'All Months',
    'January', 'February', 'March', 'April', 'May', 'June',
    'July', 'August', 'September', 'October', 'November', 'December'
  ];

  final Map<String, int> _monthMap = {
    'January': 1, 'February': 2, 'March': 3, 'April': 4, 'May': 5, 'June': 6,
    'July': 7, 'August': 8, 'September': 9, 'October': 10, 'November': 11, 'December': 12
  };

  final TextEditingController _partyController = TextEditingController();
  final TextEditingController _groupController = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<SalesProvider>().fetchDashboard();
    });
  }

  @override
  void dispose() {
    _partyController.dispose();
    _groupController.dispose();
    super.dispose();
  }

  void _applyFilters() {
    String start = '';
    String end = '';

    if (_selectedYear != 'All Years') {
      if (_selectedMonth == 'All Months') {
        start = '$_selectedYear-01-01';
        end = '$_selectedYear-12-31';
      } else {
        final m = _monthMap[_selectedMonth]!;
        final mStr = m < 10 ? '0$m' : '$m';
        final lastDay = DateTime(int.parse(_selectedYear), m + 1, 0).day;
        start = '$_selectedYear-$mStr-01';
        end = '$_selectedYear-$mStr-$lastDay';
      }
    } else {
      if (_selectedMonth != 'All Months') {
        final year = DateTime.now().year;
        final m = _monthMap[_selectedMonth]!;
        final mStr = m < 10 ? '0$m' : '$m';
        final lastDay = DateTime(year, m + 1, 0).day;
        start = '$year-$mStr-01';
        end = '$year-$mStr-$lastDay';
      }
    }

    setState(() {
      _selectedProductGroup = 'All';
      _groupFilteredProducts = null;
    });

    context.read<SalesProvider>().setFilters(
      start: start,
      end: end,
      party: _partyController.text,
      group: _groupController.text,
    );
    context.read<SalesProvider>().fetchDashboard();
  }

  void _clearFilters() {
    setState(() {
      _selectedYear = 'All Years';
      _selectedMonth = 'All Months';
      _selectedProductGroup = 'All';
      _groupFilteredProducts = null;
    });
    _partyController.clear();
    _groupController.clear();
    context.read<SalesProvider>().clearFilters();
    context.read<SalesProvider>().fetchDashboard();
  }

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<SalesProvider>(context);

    // Compute aggregate metrics
    double totalRevenue = provider.groupSales.fold(0.0, (sum, item) => sum + item.totalSalesValue);
    double totalProfit = provider.groupSales.fold(0.0, (sum, item) => sum + item.estimatedProfit);
    double avgMargin = totalRevenue > 0 ? (totalProfit / totalRevenue) * 100 : 0.0;
    int activeParties = provider.customerRetention.length;

    final formattedRevenue = NumberFormat.currency(symbol: 'Rs. ', decimalDigits: 0).format(totalRevenue);
    final formattedProfit = NumberFormat.currency(symbol: 'Rs. ', decimalDigits: 0).format(totalProfit);
    final formattedMargin = '${avgMargin.toStringAsFixed(1)}%';

    return Scaffold(
      backgroundColor: const Color(0xFF0F172A), // Deep Slate
      appBar: AppBar(
        backgroundColor: const Color(0xFF1E293B),
        elevation: 0,
        title: Text(
          'Sales Analytics',
          style: GoogleFonts.outfit(fontWeight: FontWeight.bold, color: Colors.white),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.cloud_upload_outlined, color: Colors.white70),
            tooltip: 'Upload Excel Data',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => const UploadScreen()),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.auto_awesome_motion_outlined, color: Colors.white70),
            tooltip: 'Manage Ungrouped Products',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => const AdminMapScreen()),
            ),
          ),
          const SizedBox(width: 12),
        ],
      ),
      body: provider.isLoading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF6366F1)))
          : RefreshIndicator(
              color: const Color(0xFF6366F1),
              onRefresh: () => provider.fetchDashboard(),
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Error view
                    if (provider.errorMessage.isNotEmpty)
                      Container(
                        margin: const EdgeInsets.only(bottom: 16),
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.red[900]!.withOpacity(0.4),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.red[700]!, width: 1),
                        ),
                        child: Text(
                          'Error: ${provider.errorMessage}',
                          style: GoogleFonts.outfit(color: Colors.red[100]),
                        ),
                      ),

                    // Filter Panel widget
                    _buildFilterPanel(),
                    const SizedBox(height: 20),

                    // KPI Grid
                    ResponsiveLayout(
                      mobile: _buildKPIGrid(2, 1.2, formattedRevenue, formattedProfit, formattedMargin, activeParties),
                      desktop: _buildKPIGrid(4, 1.6, formattedRevenue, formattedProfit, formattedMargin, activeParties),
                    ),
                    const SizedBox(height: 24),

                    // Charts layout
                    ResponsiveLayout(
                      mobile: _buildChartsMobile(provider),
                      desktop: _buildChartsDesktop(provider),
                    ),
                    const SizedBox(height: 24),

                    // Lists section
                    ResponsiveLayout(
                      mobile: _buildTablesMobile(provider),
                      desktop: _buildTablesDesktop(provider),
                    ),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildFilterPanel() {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.05)),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.filter_alt_outlined, color: Color(0xFF6366F1), size: 18),
              const SizedBox(width: 8),
              Text(
                'Filter Sales Registry',
                style: GoogleFonts.outfit(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, constraints) {
              final isWide = constraints.maxWidth > 800;
              return isWide ? _buildFiltersRow() : _buildFiltersColumn();
            },
          ),
        ],
      ),
    );
  }

  Widget _buildFiltersRow() {
    return Row(
      children: [
        Expanded(
          child: _buildDropdownField(
            value: _selectedYear,
            items: _years,
            label: 'Year',
            icon: Icons.calendar_today,
            onChanged: (val) {
              if (val != null) {
                setState(() {
                  _selectedYear = val;
                });
              }
            },
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _buildDropdownField(
            value: _selectedMonth,
            items: _months,
            label: 'Month',
            icon: Icons.calendar_month,
            onChanged: (val) {
              if (val != null) {
                setState(() {
                  _selectedMonth = val;
                });
              }
            },
          ),
        ),
        const SizedBox(width: 12),
        Expanded(child: _buildTextField(_partyController, 'Search Customer', Icons.person)),
        const SizedBox(width: 12),
        Expanded(child: _buildTextField(_groupController, 'Search Category', Icons.category)),
        const SizedBox(width: 16),
        ElevatedButton(
          onPressed: _applyFilters,
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF6366F1),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          child: const Text('Apply', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        ),
        const SizedBox(width: 8),
        TextButton(
          onPressed: _clearFilters,
          child: const Text('Clear', style: TextStyle(color: Colors.white60)),
        ),
      ],
    );
  }

  Widget _buildFiltersColumn() {
    return Column(
      children: [
        _buildDropdownField(
          value: _selectedYear,
          items: _years,
          label: 'Year',
          icon: Icons.calendar_today,
          onChanged: (val) {
            if (val != null) {
              setState(() {
                _selectedYear = val;
              });
            }
          },
        ),
        const SizedBox(height: 8),
        _buildDropdownField(
          value: _selectedMonth,
          items: _months,
          label: 'Month',
          icon: Icons.calendar_month,
          onChanged: (val) {
            if (val != null) {
              setState(() {
                _selectedMonth = val;
              });
            }
          },
        ),
        const SizedBox(height: 8),
        _buildTextField(_partyController, 'Search Customer', Icons.person),
        const SizedBox(height: 8),
        _buildTextField(_groupController, 'Search Category', Icons.category),
        const SizedBox(height: 16),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            TextButton(
              onPressed: _clearFilters,
              child: const Text('Clear Filters', style: TextStyle(color: Colors.white60)),
            ),
            const SizedBox(width: 12),
            ElevatedButton(
              onPressed: _applyFilters,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF6366F1),
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              child: const Text('Apply', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            ),
          ],
        )
      ],
    );
  }

  Widget _buildTextField(TextEditingController controller, String label, IconData icon) {
    return TextField(
      controller: controller,
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: Colors.white38, fontSize: 13),
        prefixIcon: Icon(icon, color: Colors.white24, size: 16),
        filled: true,
        fillColor: const Color(0xFF0F172A),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        contentPadding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
      ),
    );
  }

  Widget _buildDropdownField({
    required String value,
    required List<String> items,
    required String label,
    required IconData icon,
    required ValueChanged<String?> onChanged,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A),
        borderRadius: BorderRadius.circular(12),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Row(
        children: [
          Icon(icon, color: Colors.white24, size: 16),
          const SizedBox(width: 10),
          Expanded(
            child: DropdownButtonFormField<String>(
              dropdownColor: const Color(0xFF0F172A),
              value: value,
              icon: const Icon(Icons.arrow_drop_down, color: Colors.white24, size: 18),
              decoration: InputDecoration(
                labelText: label,
                labelStyle: const TextStyle(color: Colors.white38, fontSize: 13),
                border: InputBorder.none,
                contentPadding: EdgeInsets.zero,
              ),
              style: GoogleFonts.outfit(color: Colors.white, fontSize: 13),
              items: items.map((String val) {
                return DropdownMenuItem<String>(
                  value: val,
                  child: Text(val),
                );
              }).toList(),
              onChanged: onChanged,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildKPIGrid(int crossAxisCount, double aspectRatio, String revenue, String profit, String margin, int customers) {
    return GridView.count(
      crossAxisCount: crossAxisCount,
      crossAxisSpacing: 16,
      mainAxisSpacing: 16,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      childAspectRatio: aspectRatio,
      children: [
        MetricCard(
          title: 'Total Revenue',
          value: revenue,
          icon: Icons.payments_outlined,
          accentColor: const Color(0xFF6366F1),
        ),
        MetricCard(
          title: 'Estimated Profit',
          value: profit,
          icon: Icons.paid_outlined,
          accentColor: const Color(0xFF10B981),
        ),
        MetricCard(
          title: 'Profit Margin',
          value: margin,
          icon: Icons.trending_up_outlined,
          accentColor: const Color(0xFFEC4899),
        ),
        MetricCard(
          title: 'Active Customers',
          value: customers.toString(),
          icon: Icons.groups_outlined,
          accentColor: const Color(0xFFF59E0B),
        ),
      ],
    );
  }

  Widget _buildChartsDesktop(SalesProvider provider) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          flex: 2,
          child: _buildCardWrapper('Daily Sales & Profit Trends', SalesTrendChart(trends: provider.dailyTrends), height: 300),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: _buildCardWrapper('Group Sales Share', GroupSalesChart(groups: provider.groupSales), height: 300),
        ),
      ],
    );
  }

  Widget _buildChartsMobile(SalesProvider provider) {
    return Column(
      children: [
        _buildCardWrapper('Daily Sales & Profit Trends', SalesTrendChart(trends: provider.dailyTrends), height: 260),
        const SizedBox(height: 16),
        _buildCardWrapper('Group Sales Share', GroupSalesChart(groups: provider.groupSales), height: 260),
      ],
    );
  }

  Widget _buildTablesDesktop(SalesProvider provider) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: _buildCardWrapper('Sales Channels (Vouchers)', _buildVoucherTypeTable(provider.voucherTypeSales)),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: _buildCardWrapper('Top Products by Volume', _buildProductsTable(provider.topProducts)),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: _buildCardWrapper('High-Margin Customers', _buildMarginCustomersTable(provider.highestMarginCustomers)),
        ),
      ],
    );
  }

  Widget _buildTablesMobile(SalesProvider provider) {
    return Column(
      children: [
        _buildCardWrapper('Sales Channels (Vouchers)', _buildVoucherTypeTable(provider.voucherTypeSales)),
        const SizedBox(height: 16),
        _buildCardWrapper('Top Products by Volume', _buildProductsTable(provider.topProducts)),
        const SizedBox(height: 16),
        _buildCardWrapper('High-Margin Customers', _buildMarginCustomersTable(provider.highestMarginCustomers)),
      ],
    );
  }

  Widget _buildCardWrapper(String title, Widget content, {double? height}) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withOpacity(0.05)),
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: GoogleFonts.outfit(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 16),
          height != null
              ? SizedBox(height: height, child: content)
              : content,
        ],
      ),
    );
  }

  Widget _buildVoucherTypeTable(List<VoucherTypeSales> data) {
    if (data.isEmpty) return const Text('No channel data.', style: TextStyle(color: Colors.white38));
    return Table(
      columnWidths: const {
        0: FlexColumnWidth(2),
        1: FlexColumnWidth(1.2),
        2: FlexColumnWidth(1),
      },
      children: [
        TableRow(
          children: [
            _tableHeader('Voucher Type'),
            _tableHeader('Sales'),
            _tableHeader('Margin'),
          ],
        ),
        ...data.take(5).map((item) => TableRow(
              children: [
                _tableCell(item.vchType),
                _tableCell(NumberFormat.compact().format(item.totalSales)),
                _tableCell('${item.profitMarginPct.toStringAsFixed(1)}%', isAccent: true),
              ],
            )),
      ],
    );
  }

  Widget _buildProductsTable(List<ProductSales> data) {
    final provider = Provider.of<SalesProvider>(context, listen: false);
    final List<String> groups = ['All'] + provider.groupSales.map((g) => g.productGroup).toList();
    final List<ProductSales> productsToShow = _groupFilteredProducts ?? data;

    // Sort data locally
    final List<ProductSales> sortedData = List.from(productsToShow);
    sortedData.sort((a, b) {
      int cmp = 0;
      if (_sortColumn == 'Product') {
        cmp = a.productName.toLowerCase().compareTo(b.productName.toLowerCase());
      } else if (_sortColumn == 'Qty') {
        cmp = a.totalQuantity.compareTo(b.totalQuantity);
      } else if (_sortColumn == 'Sales Val') {
        cmp = a.totalSalesValue.compareTo(b.totalSalesValue);
      }
      return _sortAscending ? cmp : -cmp;
    });

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Category selection buttons
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: groups.map((groupName) {
              final isSelected = _selectedProductGroup == groupName;
              return Padding(
                padding: const EdgeInsets.only(right: 6.0, bottom: 12.0),
                child: ChoiceChip(
                  label: Text(groupName),
                  selected: isSelected,
                  selectedColor: const Color(0xFF6366F1),
                  backgroundColor: const Color(0xFF0F172A),
                  labelStyle: GoogleFonts.outfit(
                    color: isSelected ? Colors.white : Colors.white60,
                    fontSize: 12,
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                  ),
                  onSelected: (selected) async {
                    if (selected) {
                      setState(() {
                        _selectedProductGroup = groupName;
                      });
                      if (groupName == 'All') {
                        setState(() {
                          _groupFilteredProducts = null;
                        });
                      } else {
                        setState(() {
                          _isLoadingGroupProducts = true;
                        });
                        try {
                          final start = provider.startDate.isEmpty ? null : provider.startDate;
                          final end = provider.endDate.isEmpty ? null : provider.endDate;
                          final party = provider.partyFilter.isEmpty ? null : provider.partyFilter;
                          final sales = await provider.apiService.getTopProducts(
                            startDate: start,
                            endDate: end,
                            party: party,
                            productGroup: groupName,
                          );
                          setState(() {
                            _groupFilteredProducts = sales;
                            _isLoadingGroupProducts = false;
                          });
                        } catch (e) {
                          setState(() {
                            _isLoadingGroupProducts = false;
                          });
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('Error loading products: $e')),
                          );
                        }
                      }
                    }
                  },
                ),
              );
            }).toList(),
          ),
        ),
        const SizedBox(height: 4),
        if (_isLoadingGroupProducts)
          const SizedBox(
            height: 250,
            child: Center(
              child: CircularProgressIndicator(color: Color(0xFF6366F1)),
            ),
          )
        else ...[
          if (productsToShow.isEmpty)
            const SizedBox(
              height: 250,
              child: Center(
                child: Text('No products data.', style: TextStyle(color: Colors.white38)),
              ),
            )
          else ...[
            Table(
              columnWidths: const {
                0: FlexColumnWidth(2),
                1: FlexColumnWidth(1),
                2: FlexColumnWidth(1.2),
              },
              children: [
                TableRow(
                  children: [
                    _sortableTableHeader('Product', 'Product'),
                    _sortableTableHeader('Qty', 'Qty'),
                    _sortableTableHeader('Sales Val', 'Sales Val'),
                  ],
                ),
              ],
            ),
            const Divider(color: Colors.white10, height: 8, thickness: 1),
            SizedBox(
              height: 250,
              child: SingleChildScrollView(
                child: Table(
                  columnWidths: const {
                    0: FlexColumnWidth(2),
                    1: FlexColumnWidth(1),
                    2: FlexColumnWidth(1.2),
                  },
                  children: sortedData.map((item) => TableRow(
                        children: [
                          _tableCell(item.productName),
                          _tableCell(item.totalQuantity.toStringAsFixed(0)),
                          _tableCell(NumberFormat.compact().format(item.totalSalesValue)),
                        ],
                      )).toList(),
                ),
              ),
            ),
          ]
        ]
      ],
    );
  }

  Widget _sortableTableHeader(String text, String columnKey) {
    final isActive = _sortColumn == columnKey;
    return GestureDetector(
      onTap: () {
        setState(() {
          if (_sortColumn == columnKey) {
            _sortAscending = !_sortAscending;
          } else {
            _sortColumn = columnKey;
            _sortAscending = true;
          }
        });
      },
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: Padding(
          padding: const EdgeInsets.only(bottom: 8.0),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                text,
                style: GoogleFonts.outfit(
                  color: isActive ? const Color(0xFF6366F1) : Colors.white38,
                  fontSize: 12,
                  fontWeight: isActive ? FontWeight.bold : FontWeight.w500,
                ),
              ),
              if (isActive) ...[
                const SizedBox(width: 4),
                Icon(
                  _sortAscending ? Icons.arrow_upward : Icons.arrow_downward,
                  size: 12,
                  color: const Color(0xFF6366F1),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMarginCustomersTable(List<HighMarginCustomer> data) {
    if (data.isEmpty) return const Text('No customers data.', style: TextStyle(color: Colors.white38));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Table(
          columnWidths: const {
            0: FlexColumnWidth(2),
            1: FlexColumnWidth(1.2),
            2: FlexColumnWidth(1),
          },
          children: [
            TableRow(
              children: [
                _tableHeader('Customer'),
                _tableHeader('Total Sales'),
                _tableHeader('Margin'),
              ],
            ),
          ],
        ),
        const Divider(color: Colors.white10, height: 8, thickness: 1),
        SizedBox(
          height: 250,
          child: SingleChildScrollView(
            child: Table(
              columnWidths: const {
                0: FlexColumnWidth(2),
                1: FlexColumnWidth(1.2),
                2: FlexColumnWidth(1),
              },
              children: data.map((item) => TableRow(
                    children: [
                      _tableCell(item.party),
                      _tableCell(NumberFormat.compact().format(item.totalSales)),
                      _tableCell('${item.profitMarginPct.toStringAsFixed(1)}%', isAccent: true),
                    ],
                  )).toList(),
            ),
          ),
        ),
      ],
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
      padding: const EdgeInsets.symmetric(vertical: 6.0),
      child: Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: GoogleFonts.outfit(
          color: isAccent ? const Color(0xFF10B981) : Colors.white70,
          fontSize: 13,
          fontWeight: isAccent ? FontWeight.w600 : FontWeight.w400,
        ),
      ),
    );
  }
}
