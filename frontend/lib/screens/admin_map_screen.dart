import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../providers/sales_provider.dart';

class AdminMapScreen extends StatefulWidget {
  const AdminMapScreen({Key? key}) : super(key: key);

  @override
  State<AdminMapScreen> createState() => _AdminMapScreenState();
}

class _AdminMapScreenState extends State<AdminMapScreen> {
  String _searchQuery = '';
  final List<String> _productGroups = [
    'Big Toys',
    'Birthday Item',
    'Fancy Toys',
    'General',
    'Indian Item',
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<SalesProvider>().fetchUngroupedProducts();
    });
  }

  void _showAssignDialog(BuildContext context, String product) {
    String selectedGroup = _productGroups.first;

    showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: const Color(0xFF1E293B),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Text(
            'Assign Product Group',
            style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Product Name:',
                style: GoogleFonts.outfit(color: Colors.white38, fontSize: 12),
              ),
              const SizedBox(height: 4),
              Text(
                product,
                style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 14),
              ),
              const SizedBox(height: 20),
              Text(
                'Choose Category Group:',
                style: GoogleFonts.outfit(color: Colors.white38, fontSize: 12),
              ),
              const SizedBox(height: 8),
              Container(
                decoration: BoxDecoration(
                  color: const Color(0xFF0F172A),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.white.withOpacity(0.05)),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    dropdownColor: const Color(0xFF0F172A),
                    value: selectedGroup,
                    icon: const Icon(Icons.arrow_drop_down, color: Colors.white60),
                    isExpanded: true,
                    style: GoogleFonts.outfit(color: Colors.white, fontSize: 14),
                    items: _productGroups.map((String group) {
                      return DropdownMenuItem<String>(
                        value: group,
                        child: Text(group),
                      );
                    }).toList(),
                    onChanged: (newValue) {
                      if (newValue != null) {
                        setDialogState(() {
                          selectedGroup = newValue;
                        });
                      }
                    },
                  ),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text('Cancel', style: GoogleFonts.outfit(color: Colors.white38)),
            ),
            ElevatedButton(
              onPressed: () async {
                Navigator.pop(dialogContext); // Close dialog
                _executeAssign(product, selectedGroup);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF6366F1),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              child: Text('Assign', style: GoogleFonts.outfit(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _executeAssign(String product, String group) async {
    final provider = context.read<SalesProvider>();
    final success = await provider.assignProductGroup(product, group);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            success 
                ? 'Successfully mapped "$product" to "$group"' 
                : 'Failed to assign group mapping.',
            style: GoogleFonts.outfit(),
          ),
          backgroundColor: success ? const Color(0xFF10B981) : Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<SalesProvider>(context);
    final ungrouped = provider.ungroupedProducts;

    final filteredList = ungrouped
        .where((p) => p.toLowerCase().contains(_searchQuery.toLowerCase()))
        .toList();

    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1E293B),
        elevation: 0,
        title: Text(
          'Product Classification Map',
          style: GoogleFonts.outfit(fontWeight: FontWeight.bold, color: Colors.white),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            // Search Bar
            TextField(
              style: const TextStyle(color: Colors.white),
              onChanged: (val) {
                setState(() {
                  _searchQuery = val;
                });
              },
              decoration: InputDecoration(
                hintText: 'Search unmapped products...',
                hintStyle: const TextStyle(color: Colors.white38, fontSize: 14),
                prefixIcon: const Icon(Icons.search, color: Colors.white24, size: 20),
                filled: true,
                fillColor: const Color(0xFF1E293B),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(vertical: 16),
              ),
            ),
            const SizedBox(height: 20),

            // Main List
            Expanded(
              child: provider.isLoading
                  ? const Center(child: CircularProgressIndicator(color: Color(0xFF6366F1)))
                  : filteredList.isEmpty
                      ? _buildEmptyState(ungrouped.isEmpty)
                      : ListView.builder(
                          itemCount: filteredList.length,
                          itemBuilder: (context, index) {
                            final product = filteredList[index];
                            return Container(
                              margin: const EdgeInsets.only(bottom: 12),
                              decoration: BoxDecoration(
                                color: const Color(0xFF1E293B),
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(color: Colors.white.withOpacity(0.03)),
                              ),
                              child: ListTile(
                                contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
                                title: Text(
                                  product,
                                  style: GoogleFonts.outfit(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w600,
                                    fontSize: 14,
                                  ),
                                ),
                                subtitle: Text(
                                  'Missing Category Grouping',
                                  style: GoogleFonts.outfit(color: Colors.orange[400], fontSize: 11),
                                ),
                                trailing: ElevatedButton.icon(
                                  onPressed: () => _showAssignDialog(context, product),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xFF6366F1).withOpacity(0.15),
                                    foregroundColor: const Color(0xFF818CF8),
                                    elevation: 0,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(10),
                                      side: const BorderSide(color: Color(0xFF6366F1), width: 1.0),
                                    ),
                                  ),
                                  icon: const Icon(Icons.add, size: 14),
                                  label: Text('Assign', style: GoogleFonts.outfit(fontSize: 12, fontWeight: FontWeight.bold)),
                                ),
                              ),
                            );
                          },
                        ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState(bool totalEmpty) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            totalEmpty ? Icons.check_circle_outline : Icons.search_off_outlined,
            color: totalEmpty ? const Color(0xFF10B981) : Colors.white24,
            size: 64,
          ),
          const SizedBox(height: 16),
          Text(
            totalEmpty ? 'All Products Mapped!' : 'No matching results found.',
            style: GoogleFonts.outfit(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 18,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            totalEmpty 
                ? 'Every item in the sales history has been matched to a product group classification.' 
                : 'Try adjusting your search queries to locate missing items.',
            textAlign: TextAlign.center,
            style: GoogleFonts.outfit(
              color: Colors.white38,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }
}
