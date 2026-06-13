import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import '../models/analytics_models.dart';

class ApiService {
  String _baseUrl = 'https://sales-analytics-backend-nuv8.onrender.com';

  String get baseUrl => _baseUrl;

  void setBaseUrl(String url) {
    if (url.endsWith('/')) {
      _baseUrl = url.substring(0, url.length - 1);
    } else {
      _baseUrl = url;
    }
  }

  // Construct URL with query parameters
  Uri _buildUri(String path, [Map<String, String>? queryParams]) {
    final cleanParams = <String, String>{};
    if (queryParams != null) {
      queryParams.forEach((key, value) {
        if (value.isNotEmpty) {
          cleanParams[key] = value;
        }
      });
    }

    // Handle full URLs
    if (_baseUrl.startsWith('https://') || _baseUrl.startsWith('http://')) {
      final baseUri = Uri.parse(_baseUrl);
      return Uri(
        scheme: baseUri.scheme,
        host: baseUri.host,
        port: baseUri.port,
        path: '${baseUri.path}$path',
        queryParameters: cleanParams.isEmpty ? null : cleanParams,
      );
    }

    return Uri.http(_baseUrl, path, cleanParams.isEmpty ? null : cleanParams);
  }

  // Generic helper for GET requests returning a List
  Future<List<T>> _getList<T>(
    String path,
    T Function(Map<String, dynamic>) fromJson, [
    Map<String, String>? queryParams,
  ]) async {
    final uri = _buildUri(path, queryParams);
    try {
      final response = await http.get(uri);
      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        return data.map((item) => fromJson(item as Map<String, dynamic>)).toList();
      } else {
        throw Exception('Failed to load data from $path: Status ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Network error on $path: $e');
    }
  }

  // --- ANALYTICS APIS ---

  Future<List<GroupSales>> getGroupSales({String? startDate, String? endDate, String? party}) async {
    return _getList('/analytics/group-sales', GroupSales.fromJson, {
      if (startDate != null) 'start_date': startDate,
      if (endDate != null) 'end_date': endDate,
      if (party != null) 'party': party,
    });
  }

  Future<List<CustomerSales>> getTopCustomers({int? limit, String? startDate, String? endDate, String? productGroup}) async {
    return _getList('/analytics/top-customers', CustomerSales.fromJson, {
      if (limit != null) 'limit': limit.toString(),
      if (startDate != null) 'start_date': startDate,
      if (endDate != null) 'end_date': endDate,
      if (productGroup != null) 'product_group': productGroup,
    });
  }

  Future<List<CustomerSales>> getTopSellers({int? limit, String? startDate, String? endDate, String? productGroup}) async {
    return _getList('/analytics/top-sellers', CustomerSales.fromJson, {
      if (limit != null) 'limit': limit.toString(),
      if (startDate != null) 'start_date': startDate,
      if (endDate != null) 'end_date': endDate,
      if (productGroup != null) 'product_group': productGroup,
    });
  }

  Future<List<ProductSales>> getTopProducts({int? limit, String? startDate, String? endDate, String? party, String? productGroup}) async {
    return _getList('/analytics/top-products', ProductSales.fromJson, {
      if (limit != null) 'limit': limit.toString(),
      if (startDate != null) 'start_date': startDate,
      if (endDate != null) 'end_date': endDate,
      if (party != null) 'party': party,
      if (productGroup != null) 'product_group': productGroup,
    });
  }

  Future<List<ProductSales>> getTopSalesProducts({int? limit, String? startDate, String? endDate, String? party, String? productGroup}) async {
    return _getList('/analytics/top-sales-products', ProductSales.fromJson, {
      if (limit != null) 'limit': limit.toString(),
      if (startDate != null) 'start_date': startDate,
      if (endDate != null) 'end_date': endDate,
      if (party != null) 'party': party,
      if (productGroup != null) 'product_group': productGroup,
    });
  }

  Future<List<DailyTrend>> getDailyTrends({String? startDate, String? endDate, String? party, String? productGroup}) async {
    return _getList('/analytics/daily-trends', DailyTrend.fromJson, {
      if (startDate != null) 'start_date': startDate,
      if (endDate != null) 'end_date': endDate,
      if (party != null) 'party': party,
      if (productGroup != null) 'product_group': productGroup,
    });
  }

  Future<List<PricingConsistency>> getPricingConsistency({int? minSales, String? startDate, String? endDate, String? party, String? productGroup}) async {
    return _getList('/analytics/pricing-consistency', PricingConsistency.fromJson, {
      if (minSales != null) 'min_sales': minSales.toString(),
      if (startDate != null) 'start_date': startDate,
      if (endDate != null) 'end_date': endDate,
      if (party != null) 'party': party,
      if (productGroup != null) 'product_group': productGroup,
    });
  }

  Future<List<WeekdaySales>> getWeekdaySales({String? startDate, String? endDate, String? party, String? productGroup}) async {
    return _getList('/analytics/weekday-sales', WeekdaySales.fromJson, {
      if (startDate != null) 'start_date': startDate,
      if (endDate != null) 'end_date': endDate,
      if (party != null) 'party': party,
      if (productGroup != null) 'product_group': productGroup,
    });
  }

  Future<ParetoAnalysis> getParetoAnalysis({String? startDate, String? endDate}) async {
    final uri = _buildUri('/analytics/pareto', {
      if (startDate != null) 'start_date': startDate,
      if (endDate != null) 'end_date': endDate,
    });

    try {
      final response = await http.get(uri);
      if (response.statusCode == 200) {
        return ParetoAnalysis.fromJson(json.decode(response.body));
      } else {
        throw Exception('Failed to load Pareto details: Status ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Network error on Pareto: $e');
    }
  }

  Future<List<MitiDailyTrend>> getMitiDailyTrends({String? startDate, String? endDate, String? party, String? productGroup}) async {
    return _getList('/analytics/miti-daily-trends', MitiDailyTrend.fromJson, {
      if (startDate != null) 'start_date': startDate,
      if (endDate != null) 'end_date': endDate,
      if (party != null) 'party': party,
      if (productGroup != null) 'product_group': productGroup,
    });
  }

  Future<List<MitiMonthlyTrend>> getMitiMonthlyTrends({String? startDate, String? endDate, String? party, String? productGroup}) async {
    return _getList('/analytics/miti-monthly-trends', MitiMonthlyTrend.fromJson, {
      if (startDate != null) 'start_date': startDate,
      if (endDate != null) 'end_date': endDate,
      if (party != null) 'party': party,
      if (productGroup != null) 'product_group': productGroup,
    });
  }

  Future<List<CustomerRetention>> getCustomerRetention({String? startDate, String? endDate}) async {
    return _getList('/analytics/customer-retention', CustomerRetention.fromJson, {
      if (startDate != null) 'start_date': startDate,
      if (endDate != null) 'end_date': endDate,
    });
  }

  Future<List<VoucherTypeSales>> getSalesByVoucherType({String? startDate, String? endDate, String? party}) async {
    return _getList('/analytics/sales-by-voucher-type', VoucherTypeSales.fromJson, {
      if (startDate != null) 'start_date': startDate,
      if (endDate != null) 'end_date': endDate,
      if (party != null) 'party': party,
    });
  }

  Future<List<HighMarginProduct>> getHighestMarginProducts({int? limit, String? startDate, String? endDate, String? productGroup}) async {
    return _getList('/analytics/highest-margin-products', HighMarginProduct.fromJson, {
      if (limit != null) 'limit': limit.toString(),
      if (startDate != null) 'start_date': startDate,
      if (endDate != null) 'end_date': endDate,
      if (productGroup != null) 'product_group': productGroup,
    });
  }

  Future<List<HighMarginCustomer>> getHighestMarginCustomers({int? limit, String? startDate, String? endDate}) async {
    return _getList('/analytics/highest-margin-customers', HighMarginCustomer.fromJson, {
      if (limit != null) 'limit': limit.toString(),
      if (startDate != null) 'start_date': startDate,
      if (endDate != null) 'end_date': endDate,
    });
  }

  Future<List<ImportForecast>> getImportForecast({int? days}) async {
    return _getList('/analytics/import-forecast', ImportForecast.fromJson, {
      if (days != null) 'days': days.toString(),
    });
  }

  Future<List<MarketBasketPair>> getMarketBasket({String? startDate, String? endDate, String? party, String? productGroup, int? minSupport, int? topN}) async {
    return _getList('/analytics/market-basket', MarketBasketPair.fromJson, {
      if (startDate != null) 'start_date': startDate,
      if (endDate != null) 'end_date': endDate,
      if (party != null) 'party': party,
      if (productGroup != null) 'product_group': productGroup,
      if (minSupport != null) 'min_support': minSupport.toString(),
      if (topN != null) 'top_n': topN.toString(),
    });
  }

  Future<List<CustomerCLV>> getCustomerCLV({String? startDate, String? endDate, String? party}) async {
    return _getList('/analytics/customer-clv', CustomerCLV.fromJson, {
      if (startDate != null) 'start_date': startDate,
      if (endDate != null) 'end_date': endDate,
      if (party != null) 'party': party,
    });
  }

  Future<List<SlowMovingProduct>> getSlowMovingStock({String? startDate, String? endDate, String? party, String? productGroup, int? thresholdDays}) async {
    return _getList('/analytics/slow-moving-stock', SlowMovingProduct.fromJson, {
      if (startDate != null) 'start_date': startDate,
      if (endDate != null) 'end_date': endDate,
      if (party != null) 'party': party,
      if (productGroup != null) 'product_group': productGroup,
      if (thresholdDays != null) 'threshold_days': thresholdDays.toString(),
    });
  }

  Future<List<SalesForecast>> getSalesForecast({String? startDate, String? endDate, String? party, int? forecastDays}) async {
    return _getList('/analytics/sales-forecast', SalesForecast.fromJson, {
      if (startDate != null) 'start_date': startDate,
      if (endDate != null) 'end_date': endDate,
      if (party != null) 'party': party,
      if (forecastDays != null) 'forecast_days': forecastDays.toString(),
    });
  }

  // --- UNGROUPED PRODUCTS & GROUP MAPPING ---

  Future<List<String>> getUngroupedProducts() async {
    final uri = _buildUri('/products/ungrouped');
    try {
      final response = await http.get(uri);
      if (response.statusCode == 200) {
        final Map<String, dynamic> data = json.decode(response.body);
        final List<dynamic> list = data['ungrouped_products'] ?? [];
        return list.map((item) => item.toString()).toList();
      } else {
        throw Exception('Failed to load ungrouped products');
      }
    } catch (e) {
      throw Exception('Network error on ungrouped: $e');
    }
  }

  Future<bool> assignGroup(String productName, String groupName) async {
    final uri = _buildUri('/products/assign-group');
    try {
      final response = await http.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'product_name': productName,
          'group_name': groupName,
        }),
      );
      return response.statusCode == 200;
    } catch (e) {
      throw Exception('Network error on mapping: $e');
    }
  }

  // --- EXCEL FILE UPLOAD APIS ---

  Future<Map<String, dynamic>> uploadExcelFile(String path, List<int> fileBytes, String fileName) async {
    final uri = _buildUri(path);
    try {
      final request = http.MultipartRequest('POST', uri);
      
      final multipartFile = http.MultipartFile.fromBytes(
        'file',
        fileBytes,
        filename: fileName,
        contentType: MediaType('application', 'vnd.openxmlformats-officedocument.spreadsheetml.sheet'),
      );
      request.files.add(multipartFile);

      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode == 200) {
        return json.decode(response.body) as Map<String, dynamic>;
      } else {
        throw Exception('Failed to upload file. Server responded with: ${response.body}');
      }
    } catch (e) {
      throw Exception('Upload error: $e');
    }
  }
}
