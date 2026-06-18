import 'dart:convert';
import 'package:http/http.dart' as http;
import 'local_db_service.dart';

class SyncService {
  static const String _supabaseUrl = 'https://dovwkxezwhszhcgeswfk.supabase.co/rest/v1';
  static String get _supabaseKey => utf8.decode(base64.decode('c2Jfc2VjcmV0X2VBWHNOTWxXTkNzcDVSOEI4TWNkR0FfeVRjLVYyMG0='));

  static Map<String, String> _getHeaders() {
    return {
      'apikey': _supabaseKey,
      'Authorization': 'Bearer $_supabaseKey',
      'Content-Type': 'application/json',
    };
  }

  // Generic paginated fetch helper
  static Future<List<Map<String, dynamic>>> fetchTable(String table, {String? filter}) async {
    final List<Map<String, dynamic>> results = [];
    int limit = 1000;
    int offset = 0;

    while (true) {
      String url = '$_supabaseUrl/$table?select=*&limit=$limit&offset=$offset';
      if (filter != null && filter.isNotEmpty) {
        url += '&$filter';
      }

      final response = await http.get(Uri.parse(url), headers: _getHeaders());
      if (response.statusCode != 200) {
        throw Exception('Failed to fetch from Supabase table $table: ${response.body}');
      }

      final List<dynamic> data = json.decode(response.body);
      if (data.isEmpty) break;

      results.addAll(data.cast<Map<String, dynamic>>());
      if (data.length < limit) break;

      offset += limit;
    }

    return results;
  }

  // Push local group assignment to Supabase
  static Future<bool> assignGroupOnSupabase(String productName, String groupName) async {
    final url = '$_supabaseUrl/products';
    final payload = {
      'product_name': productName.trim(),
      'group_name': groupName.trim(),
    };

    try {
      final response = await http.post(
        Uri.parse(url),
        headers: {
          ..._getHeaders(),
          'Prefer': 'resolution=merge-duplicates',
        },
        body: json.encode([payload]),
      );
      return response.statusCode == 200 || response.statusCode == 201;
    } catch (e) {
      print('Failed to push group assignment to Supabase: $e');
      return false;
    }
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
