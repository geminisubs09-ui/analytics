import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../providers/sales_provider.dart';
import '../widgets/navigation_drawer.dart';
import '../models/analytics_models.dart';

class InventoryPlannerScreen extends StatefulWidget {
  const InventoryPlannerScreen({Key? key}) : super(key: key);

  @override
  State<InventoryPlannerScreen> createState() => _InventoryPlannerScreenState();
}

class _InventoryPlannerScreenState extends State<InventoryPlannerScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  String _selectedGroup = 'All';

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() {
      setState(() {
        _searchQuery = _searchController.text.toLowerCase();
      });
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<SalesProvider>(context);

    // Extract unique product groups for the filter chips
    final List<String> groups = ['All'] + provider.groupSales.map((g) => g.productGroup).toList();

    // Filter forecasts
    final filteredForecasts = provider.importForecasts.where((item) {
      final matchesSearch = item.productName.toLowerCase().contains(_searchQuery);
      final matchesGroup = _selectedGroup == 'All' || item.groupName.toLowerCase() == _selectedGroup.toLowerCase();
      return matchesSearch && matchesGroup;
    }).toList();

    return Scaffold(
      backgroundColor: const Color(0xFF0F172A), // Deep Slate
      drawer: const AppNavigationDrawer(activeRoute: 'inventory_planner'),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1E293B),
        title: Text(
          'China Import Planner',
          style: GoogleFonts.outfit(fontWeight: FontWeight.bold, color: Colors.white),
        ),
      ),
      body: provider.isLoading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF6366F1)))
          : Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Explanation Header Card
                  _buildHeaderCard(),
                  const SizedBox(height: 16),
                  
                  // Search Bar
                  _buildSearchBox(),
                  const SizedBox(height: 12),

                  // Category Filter Chips
                  _buildCategoryFilterChips(groups),
                  const SizedBox(height: 12),

                  // Products suggested list
                  Expanded(
                    child: filteredForecasts.isEmpty
                        ? const Center(child: Text('No import suggestions found.', style: TextStyle(color: Colors.white38)))
                        : _buildForecastList(filteredForecasts),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _buildHeaderCard() {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF6366F1).withOpacity(0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFF6366F1).withOpacity(0.3)),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.local_shipping, color: Color(0xFF818CF8), size: 22),
              const SizedBox(width: 8),
              Text(
                'China Import Logic (3-Month Lead Time)',
                style: GoogleFonts.outfit(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Suggested order quantities are calculated by taking the past 90-day monthly sales velocity and projecting a 3-month import shipping lead-time demand, including a 25% safety stock buffer.',
            style: GoogleFonts.outfit(
              color: Colors.white70,
              fontSize: 12,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchBox() {
    return TextField(
      controller: _searchController,
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        hintText: 'Search products by name...',
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

  Widget _buildCategoryFilterChips(List<String> groups) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: groups.map((groupName) {
          final isSelected = _selectedGroup.toLowerCase() == groupName.toLowerCase();
          return Padding(
            padding: const EdgeInsets.only(right: 8.0),
            child: ChoiceChip(
              label: Text(groupName),
              selected: isSelected,
              selectedColor: const Color(0xFF6366F1),
              backgroundColor: const Color(0xFF1E293B),
              labelStyle: GoogleFonts.outfit(
                color: isSelected ? Colors.white : Colors.white60,
                fontSize: 12,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              ),
              onSelected: (selected) {
                if (selected) {
                  setState(() {
                    _selectedGroup = groupName;
                  });
                }
              },
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildForecastList(List<ImportForecast> forecasts) {
    return ListView.builder(
      itemCount: forecasts.length,
      itemBuilder: (context, index) {
        final item = forecasts[index];
        final isHighOrder = item.suggestedOrderQty >= 100;
        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
            color: const Color(0xFF1E293B),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isHighOrder ? const Color(0xFF6366F1).withOpacity(0.3) : Colors.white.withOpacity(0.05),
              width: 1.0,
            ),
          ),
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.productName,
                      style: GoogleFonts.outfit(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.08),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            item.groupName,
                            style: GoogleFonts.outfit(color: Colors.white60, fontSize: 11),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Text(
                          '90d sold: ${item.totalQuantity.toStringAsFixed(0)} pcs',
                          style: GoogleFonts.outfit(color: Colors.white38, fontSize: 12),
                        ),
                        const SizedBox(width: 12),
                        Text(
                          'Monthly run: ${item.monthlyRunRate.toStringAsFixed(0)}/mo',
                          style: GoogleFonts.outfit(color: Colors.white38, fontSize: 12),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    'Order Suggestion',
                    style: GoogleFonts.outfit(color: Colors.white38, fontSize: 11),
                  ),
                  const SizedBox(height: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: isHighOrder ? const Color(0xFF6366F1).withOpacity(0.18) : Colors.white.withOpacity(0.06),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: isHighOrder ? const Color(0xFF6366F1).withOpacity(0.4) : Colors.white10,
                        width: 1.0,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (isHighOrder) ...[
                          const Icon(Icons.shopping_bag_outlined, color: Color(0xFF818CF8), size: 14),
                          const SizedBox(width: 4),
                        ],
                        Text(
                          '${item.suggestedOrderQty} units',
                          style: GoogleFonts.outfit(
                            color: isHighOrder ? const Color(0xFF818CF8) : Colors.white70,
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}
