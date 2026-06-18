import 'dart:convert';
import 'package:http/http.dart' as http;
import 'local_db_service.dart';

class SyncService {
  static const String _backendUrl = 'https://sales-analytics-backend-nuv8.onrender.com';

  // Generic paginated fetch helper calling our FastAPI backend securely
  static Future<List<Map<String, dynamic>>> fetchTable(String table, {String? filter}) async {
    String url = '$_backendUrl/raw/$table';
    if (filter != null && filter.isNotEmpty) {
      url += '?filter=${Uri.encodeComponent(filter)}';
    }

    final response = await http.get(Uri.parse(url));
    if (response.statusCode != 200) {
      throw Exception('Failed to fetch from backend table $table: ${response.body}');
    }

    final List<dynamic> data = json.decode(response.body);
    return data.cast<Map<String, dynamic>>();
  }


  // Execute sync
  static Future<void> sync() async {
    final localDb = LocalDbService();
    final maxDateStr = await localDb.getMaxTransactionDate();

    if (maxDateStr == null) {
      // Database is empty, full sync
      print('SyncService: Local DB empty. Starting full sync...');
      
      final products = await fetchTable('products');
      await localDb.bulkInsertProducts(products);

      final vouchers = await fetchTable('vouchers');
      await localDb.bulkInsertVouchers(vouchers);

      final salesItems = await fetchTable('sales_items');
      await localDb.bulkInsertSalesItems(salesItems);

      print('SyncService: Full sync complete.');
    } else {
      // Incremental sync
      print('SyncService: Local DB max transaction date = $maxDateStr. Starting incremental sync...');
      
      final maxDate = DateTime.parse(maxDateStr.split(' ')[0]);
      final cutoffDate = maxDate.subtract(const Duration(days: 7));
      final cutoffDateStr = cutoffDate.toIso8601String().split('T')[0];

      print('SyncService: Deleting local records from $cutoffDateStr...');
      await localDb.deleteRecordsFromDate(cutoffDateStr);

      print('SyncService: Fetching incremental vouchers...');
      final vouchers = await fetchTable('vouchers', filter: 'date=gte.$cutoffDateStr');
      await localDb.bulkInsertVouchers(vouchers);

      print('SyncService: Fetching incremental sales items...');
      final salesItems = await fetchTable('sales_items', filter: 'date=gte.$cutoffDateStr');
      await localDb.bulkInsertSalesItems(salesItems);

      // Always fully sync products mapping to ensure mappings are up to date
      print('SyncService: Fetching all products...');
      final products = await fetchTable('products');
      await localDb.bulkInsertProducts(products);

      print('SyncService: Incremental sync complete.');
    }
  }
}
