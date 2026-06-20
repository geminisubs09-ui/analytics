import 'package:flutter/foundation.dart';
import '../models/analytics_models.dart';
import '../services/api_service.dart';
import '../services/local_db_service.dart';
import '../services/sync_service.dart';
import '../services/client_compute_service.dart';

class SalesProvider with ChangeNotifier {
  final ApiService _apiService = ApiService();
  final LocalDbService _localDbService = LocalDbService();
  final ClientComputeService _clientComputeService = ClientComputeService();

  bool get isAndroid => !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  // Filters
  String _startDate = '';
  String _endDate = '';
  String _partyFilter = '';
  String _productGroupFilter = '';

  // Loading States
  bool _isLoading = false;
  String _errorMessage = '';
  bool _webDataLoaded = false;

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
  List<MarketBasketPair> _marketBasket = [];
  List<CustomerCLV> _customerCLV = [];
  List<SlowMovingProduct> _slowMovingStock = [];
  List<SalesForecast> _salesForecast = [];

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
  List<MarketBasketPair> get marketBasket => _marketBasket;
  List<CustomerCLV> get customerCLV => _customerCLV;
  List<SlowMovingProduct> get slowMovingStock => _slowMovingStock;
  List<SalesForecast> get salesForecast => _salesForecast;
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

      if (isAndroid) {
        // Run sync before querying SQLite
        try {
          await SyncService.sync();
        } catch (syncError) {
          debugPrint('Sync failed, falling back to cached local DB: $syncError');
        }

        // Execute queries locally in parallel
        final results = await Future.wait([
          _localDbService.getGroupSales(startDate: start, endDate: end, party: party),
          _localDbService.getTopCustomers(limit: 10, startDate: start, endDate: end, productGroup: group),
          _localDbService.getTopSellers(limit: 10, startDate: start, endDate: end, productGroup: group),
          _localDbService.getTopProducts(startDate: start, endDate: end, party: party, productGroup: group),
          _localDbService.getTopSalesProducts(startDate: start, endDate: end, party: party, productGroup: group),
          _localDbService.getDailyTrends(startDate: start, endDate: end, party: party, productGroup: group),
          _localDbService.getPricingConsistency(minSales: 5, startDate: start, endDate: end, party: party, productGroup: group),
          Future.value(<WeekdaySales>[]), // Removed WeekdaySales calculation
          _localDbService.getParetoAnalysis(startDate: start, endDate: end),
          _localDbService.getMitiDailyTrends(startDate: start, endDate: end, party: party, productGroup: group),
          _localDbService.getMitiMonthlyTrends(startDate: start, endDate: end, party: party, productGroup: group),
          _localDbService.getCustomerRetention(startDate: start, endDate: end),
          _localDbService.getSalesByVoucherType(startDate: start, endDate: end, party: party),
          _localDbService.getHighestMarginProducts(limit: 10, startDate: start, endDate: end, productGroup: group),
          _localDbService.getHighestMarginCustomers(startDate: start, endDate: end),
          _localDbService.getImportForecast(),
          Future.value(<MarketBasketPair>[]), // Removed Market Basket calculation
          _localDbService.getCustomerCLV(startDate: start, endDate: end, party: party),
          _localDbService.getSlowMovingStock(startDate: start, endDate: end, party: party, productGroup: group),
          _localDbService.getSalesForecast(startDate: start, endDate: end, party: party),
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
        _marketBasket = results[16] as List<MarketBasketPair>;
        _customerCLV = results[17] as List<CustomerCLV>;
        _slowMovingStock = results[18] as List<SlowMovingProduct>;
        _salesForecast = results[19] as List<SalesForecast>;
      } else {
        // Client-side computation for Web
        if (!_webDataLoaded) {
          final resultsTable = await Future.wait([
            SyncService.fetchTable('vouchers'),
            SyncService.fetchTable('sales_items'),
            SyncService.fetchTable('products'),
          ]);
          _clientComputeService.updateCache(
            vouchers: resultsTable[0],
            salesItems: resultsTable[1],
            products: resultsTable[2],
          );
          _webDataLoaded = true;
        }

        // Execute queries locally in-memory
        final results = await Future.wait([
          _clientComputeService.getGroupSales(startDate: start, endDate: end, party: party),
          _clientComputeService.getTopCustomers(limit: 10, startDate: start, endDate: end, productGroup: group),
          _clientComputeService.getTopSellers(limit: 10, startDate: start, endDate: end, productGroup: group),
          _clientComputeService.getTopProducts(startDate: start, endDate: end, party: party, productGroup: group),
          _clientComputeService.getTopSalesProducts(startDate: start, endDate: end, party: party, productGroup: group),
          _clientComputeService.getDailyTrends(startDate: start, endDate: end, party: party, productGroup: group),
          _clientComputeService.getPricingConsistency(minSales: 5, startDate: start, endDate: end, party: party, productGroup: group),
          Future.value(<WeekdaySales>[]), // Removed WeekdaySales calculation
          _clientComputeService.getParetoAnalysis(startDate: start, endDate: end),
          _clientComputeService.getMitiDailyTrends(startDate: start, endDate: end, party: party, productGroup: group),
          _clientComputeService.getMitiMonthlyTrends(startDate: start, endDate: end, party: party, productGroup: group),
          _clientComputeService.getCustomerRetention(startDate: start, endDate: end),
          _clientComputeService.getSalesByVoucherType(startDate: start, endDate: end, party: party),
          _clientComputeService.getHighestMarginProducts(limit: 10, startDate: start, endDate: end, productGroup: group),
          _clientComputeService.getHighestMarginCustomers(startDate: start, endDate: end),
          _clientComputeService.getImportForecast(),
          Future.value(<MarketBasketPair>[]), // Removed Market Basket calculation
          _clientComputeService.getCustomerCLV(startDate: start, endDate: end, party: party),
          _clientComputeService.getSlowMovingStock(startDate: start, endDate: end, party: party, productGroup: group),
          _clientComputeService.getSalesForecast(startDate: start, endDate: end, party: party),
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
        _marketBasket = results[16] as List<MarketBasketPair>;
        _customerCLV = results[17] as List<CustomerCLV>;
        _slowMovingStock = results[18] as List<SlowMovingProduct>;
        _salesForecast = results[19] as List<SalesForecast>;
      }

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
      if (isAndroid) {
        _ungroupedProducts = await _localDbService.getUngroupedProducts();
      } else {
        _ungroupedProducts = await _clientComputeService.getUngroupedProducts();
      }
    } catch (e) {
      debugPrint('Error loading ungrouped products: $e');
    }
  }

  Future<bool> assignProductGroup(String productName, String groupName) async {
    try {
      if (isAndroid) {
        await _localDbService.assignGroup(productName, groupName);
      } else {
        await _clientComputeService.assignGroup(productName, groupName);
      }
      // Push to Supabase via backend in background
      _apiService.assignGroup(productName, groupName).catchError((e) {
        debugPrint('Background push of assigned group failed: $e');
        return false;
      });
      await fetchUngroupedProducts();
      notifyListeners();
      return true;
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
      if (isAndroid) {
        try {
          await SyncService.sync();
        } catch (syncError) {
          debugPrint('Sync after upload failed: $syncError');
        }
      } else {
        _webDataLoaded = false;
      }
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
      if (isAndroid) {
        try {
          await SyncService.sync();
        } catch (syncError) {
          debugPrint('Sync after upload failed: $syncError');
        }
      } else {
        _webDataLoaded = false;
      }
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
