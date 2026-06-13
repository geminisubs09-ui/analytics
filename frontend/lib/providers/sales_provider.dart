import 'package:flutter/material.dart';
import '../models/analytics_models.dart';
import '../services/api_service.dart';

class SalesProvider with ChangeNotifier {
  final ApiService _apiService = ApiService();

  // Filters
  String _startDate = '';
  String _endDate = '';
  String _partyFilter = '';
  String _productGroupFilter = '';

  // Loading States
  bool _isLoading = false;
  String _errorMessage = '';

  // Data Cache
  List<GroupSales> _groupSales = [];
  List<CustomerSales> _topCustomers = [];
  List<CustomerSales> _topSellers = [];
  List<ProductSales> _topProducts = [];
  List<ProductSales> _topSalesProducts = [];
  List<DailyTrend> _dailyTrends = [];
  List<PricingConsistency> _pricingConsistency = [];
  List<WeekdaySales> _weekdaySales = [];
  ParetoAnalysis? _paretoAnalysis;
  List<MitiDailyTrend> _mitiDailyTrends = [];
  List<MitiMonthlyTrend> _mitiMonthlyTrends = [];
  List<CustomerRetention> _customerRetention = [];
  List<VoucherTypeSales> _voucherTypeSales = [];
  List<HighMarginProduct> _highestMarginProducts = [];
  List<HighMarginCustomer> _highestMarginCustomers = [];
  List<ImportForecast> _importForecasts = [];

  // Ungrouped
  List<String> _ungroupedProducts = [];

  // Getters
  ApiService get apiService => _apiService;
  String get startDate => _startDate;
  String get endDate => _endDate;
  String get partyFilter => _partyFilter;
  String get productGroupFilter => _productGroupFilter;
  bool get isLoading => _isLoading;
  String get errorMessage => _errorMessage;

  List<GroupSales> get groupSales => _groupSales;
  List<CustomerSales> get topCustomers => _topCustomers;
  List<CustomerSales> get topSellers => _topSellers;
  List<ProductSales> get topProducts => _topProducts;
  List<ProductSales> get topSalesProducts => _topSalesProducts;
  List<DailyTrend> get dailyTrends => _dailyTrends;
  List<PricingConsistency> get pricingConsistency => _pricingConsistency;
  List<WeekdaySales> get weekdaySales => _weekdaySales;
  ParetoAnalysis? get paretoAnalysis => _paretoAnalysis;
  List<MitiDailyTrend> get mitiDailyTrends => _mitiDailyTrends;
  List<MitiMonthlyTrend> get mitiMonthlyTrends => _mitiMonthlyTrends;
  List<CustomerRetention> get customerRetention => _customerRetention;
  List<VoucherTypeSales> get voucherTypeSales => _voucherTypeSales;
  List<HighMarginProduct> get highestMarginProducts => _highestMarginProducts;
  List<HighMarginCustomer> get highestMarginCustomers => _highestMarginCustomers;
  List<ImportForecast> get importForecasts => _importForecasts;
  List<String> get ungroupedProducts => _ungroupedProducts;

  // Set Filters
  void setFilters({String? start, String? end, String? party, String? group}) {
    if (start != null) _startDate = start;
    if (end != null) _endDate = end;
    if (party != null) _partyFilter = party;
    if (group != null) _productGroupFilter = group;
    notifyListeners();
  }

  void clearFilters() {
    _startDate = '';
    _endDate = '';
    _partyFilter = '';
    _productGroupFilter = '';
    notifyListeners();
  }

  // API Call Wrapper
  Future<void> fetchDashboard() async {
    _isLoading = true;
    _errorMessage = '';
    notifyListeners();

    try {
      final start = _startDate.isEmpty ? null : _startDate;
      final end = _endDate.isEmpty ? null : _endDate;
      final party = _partyFilter.isEmpty ? null : _partyFilter;
      final group = _productGroupFilter.isEmpty ? null : _productGroupFilter;

      // Execute APIs in parallel
      final results = await Future.wait([
        _apiService.getGroupSales(startDate: start, endDate: end, party: party),
        _apiService.getTopCustomers(limit: 10, startDate: start, endDate: end, productGroup: group),
        _apiService.getTopSellers(limit: 10, startDate: start, endDate: end, productGroup: group),
        _apiService.getTopProducts(startDate: start, endDate: end, party: party, productGroup: group),
        _apiService.getTopSalesProducts(startDate: start, endDate: end, party: party, productGroup: group),
        _apiService.getDailyTrends(startDate: start, endDate: end, party: party, productGroup: group),
        _apiService.getPricingConsistency(minSales: 5, startDate: start, endDate: end, party: party, productGroup: group),
        _apiService.getWeekdaySales(startDate: start, endDate: end, party: party, productGroup: group),
        _apiService.getParetoAnalysis(startDate: start, endDate: end),
        _apiService.getMitiDailyTrends(startDate: start, endDate: end, party: party, productGroup: group),
        _apiService.getMitiMonthlyTrends(startDate: start, endDate: end, party: party, productGroup: group),
        _apiService.getCustomerRetention(startDate: start, endDate: end),
        _apiService.getSalesByVoucherType(startDate: start, endDate: end, party: party),
        _apiService.getHighestMarginProducts(limit: 10, startDate: start, endDate: end, productGroup: group),
        _apiService.getHighestMarginCustomers(startDate: start, endDate: end),
        _apiService.getImportForecast(),
      ]);

      _groupSales = results[0] as List<GroupSales>;
      _topCustomers = results[1] as List<CustomerSales>;
      _topSellers = results[2] as List<CustomerSales>;
      _topProducts = results[3] as List<ProductSales>;
      _topSalesProducts = results[4] as List<ProductSales>;
      _dailyTrends = results[5] as List<DailyTrend>;
      _pricingConsistency = results[6] as List<PricingConsistency>;
      _weekdaySales = results[7] as List<WeekdaySales>;
      _paretoAnalysis = results[8] as ParetoAnalysis;
      _mitiDailyTrends = results[9] as List<MitiDailyTrend>;
      _mitiMonthlyTrends = results[10] as List<MitiMonthlyTrend>;
      _customerRetention = results[11] as List<CustomerRetention>;
      _voucherTypeSales = results[12] as List<VoucherTypeSales>;
      _highestMarginProducts = results[13] as List<HighMarginProduct>;
      _highestMarginCustomers = results[14] as List<HighMarginCustomer>;
      _importForecasts = results[15] as List<ImportForecast>;

      // Load ungrouped products separately
      await fetchUngroupedProducts();
    } catch (e) {
      _errorMessage = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> fetchUngroupedProducts() async {
    try {
      _ungroupedProducts = await _apiService.getUngroupedProducts();
    } catch (e) {
      debugPrint('Error loading ungrouped products: $e');
    }
  }

  Future<bool> assignProductGroup(String productName, String groupName) async {
    try {
      final success = await _apiService.assignGroup(productName, groupName);
      if (success) {
        await fetchUngroupedProducts();
        notifyListeners();
        return true;
      }
      return false;
    } catch (e) {
      _errorMessage = e.toString();
      notifyListeners();
      return false;
    }
  }

  Future<Map<String, dynamic>> uploadSalesSheet(List<int> bytes, String name) async {
    _isLoading = true;
    _errorMessage = '';
    notifyListeners();

    try {
      final result = await _apiService.uploadExcelFile('/upload/sales', bytes, name);
      await fetchDashboard();
      return result;
    } catch (e) {
      _errorMessage = e.toString();
      _isLoading = false;
      notifyListeners();
      rethrow;
    }
  }

  Future<Map<String, dynamic>> uploadProductsSheet(List<int> bytes, String name) async {
    _isLoading = true;
    _errorMessage = '';
    notifyListeners();

    try {
      final result = await _apiService.uploadExcelFile('/upload/products', bytes, name);
      await fetchDashboard();
      return result;
    } catch (e) {
      _errorMessage = e.toString();
      _isLoading = false;
      notifyListeners();
      rethrow;
    }
  }
}
