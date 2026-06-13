import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../screens/dashboard_screen.dart';
import '../screens/advanced_insights_screen.dart';
import '../screens/inventory_planner_screen.dart';

class AppNavigationDrawer extends StatelessWidget {
  final String activeRoute;

  const AppNavigationDrawer({
    Key? key,
    required this.activeRoute,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Drawer(
      backgroundColor: const Color(0xFF1E293B),
      child: Column(
        children: [
          DrawerHeader(
            decoration: const BoxDecoration(
              color: Color(0xFF0F172A),
              border: Border(bottom: BorderSide(color: Colors.white10, width: 1)),
            ),
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.analytics_outlined, color: Color(0xFF6366F1), size: 40),
                  const SizedBox(height: 10),
                  Text(
                    'Sales Insights',
                    style: GoogleFonts.outfit(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    'v1.1',
                    style: GoogleFonts.outfit(
                      color: Colors.white38,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              children: [
                _buildMenuItem(
                  context,
                  title: 'Dashboard',
                  icon: Icons.dashboard_outlined,
                  route: 'dashboard',
                  destination: const DashboardScreen(),
                ),
                const SizedBox(height: 8),
                _buildMenuItem(
                  context,
                  title: 'Advanced Analytics',
                  icon: Icons.auto_graph_outlined,
                  route: 'advanced_insights',
                  destination: const AdvancedInsightsScreen(),
                ),
                const SizedBox(height: 8),
                _buildMenuItem(
                  context,
                  title: 'China Import Planner',
                  icon: Icons.local_shipping_outlined,
                  route: 'inventory_planner',
                  destination: const InventoryPlannerScreen(),
                ),
              ],
            ),
          ),
          const Divider(color: Colors.white10, height: 1),
          Padding(
            padding: const EdgeInsets.all(20.0),
            child: Text(
              'Nepalese Sales Register Portal',
              style: GoogleFonts.outfit(
                color: Colors.white24,
                fontSize: 11,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMenuItem(
    BuildContext context, {
    required String title,
    required IconData icon,
    required String route,
    required Widget destination,
  }) {
    final isSelected = activeRoute == route;
    return Container(
      decoration: BoxDecoration(
        color: isSelected ? const Color(0xFF6366F1).withOpacity(0.15) : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isSelected ? const Color(0xFF6366F1).withOpacity(0.3) : Colors.transparent,
          width: 1,
        ),
      ),
      child: ListTile(
        leading: Icon(
          icon,
          color: isSelected ? const Color(0xFF6366F1) : Colors.white60,
          size: 20,
        ),
        title: Text(
          title,
          style: GoogleFonts.outfit(
            color: isSelected ? Colors.white : Colors.white70,
            fontSize: 14,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
          ),
        ),
        onTap: () {
          Navigator.pop(context); // Close the drawer
          if (!isSelected) {
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(builder: (context) => destination),
            );
          }
        },
      ),
    );
  }
}
