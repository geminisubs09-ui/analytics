import 'dart:math';
import '../models/analytics_models.dart';

class ClientComputeService {
  static final ClientComputeService _instance = ClientComputeService._internal();
  factory ClientComputeService() => _instance;
  ClientComputeService._internal();

  List<Map<String, dynamic>> _vouchers = [];
  List<Map<String, dynamic>> _salesItems = [];
  List<Map<String, dynamic>> _products = [];

  void updateCache({
    List<Map<String, dynamic>>? vouchers,
    List<Map<String, dynamic>>? salesItems,
    List<Map<String, dynamic>>? products,
  }) {
    if (vouchers != null) _vouchers = vouchers;
    if (salesItems != null) _salesItems = salesItems;
    if (products != null) _products = products;
  }

  // --- FILTER HELPERS ---

  String _getMitiKey(String mitiStr) {
    final parts = mitiStr.trim().split('-');
    if (parts.length == 3) {
      return '${parts[2]}-${parts[1]}-${parts[0]}'; // DD-MM-YYYY -> YYYY-MM-DD
    }
    return '';
  }

  List<Map<String, dynamic>> _filterVouchers({
    String? startDate,
    String? endDate,
    String? party,
    String? startMiti,
    String? endMiti,
  }) {
    return _vouchers.where((vch) {
      final date = vch['date'] as String?;
      if (startDate != null && startDate.isNotEmpty && date != null) {
        if (date.compareTo(startDate) < 0) return false;
      }
      if (endDate != null && endDate.isNotEmpty && date != null) {
        if (date.compareTo(endDate) > 0) return false;
      }
      final partyName = vch['party'] as String?;
      if (party != null && party.isNotEmpty) {
        if (partyName == null || partyName.trim().toLowerCase() != party.trim().toLowerCase()) {
          return false;
        }
      }
      final miti = vch['miti'] as String?;
      if (miti != null && miti.isNotEmpty) {
        final mitiKey = _getMitiKey(miti);
        if (startMiti != null && startMiti.isNotEmpty) {
          if (mitiKey.compareTo(_getMitiKey(startMiti)) < 0) return false;
        }
        if (endMiti != null && endMiti.isNotEmpty) {
          if (mitiKey.compareTo(_getMitiKey(endMiti)) > 0) return false;
        }
      } else if (startMiti != null || endMiti != null) {
        return false;
      }
      return true;
    }).toList();
  }

  List<Map<String, dynamic>> _filterSalesItems({
    String? startDate,
    String? endDate,
    String? party,
    String? productGroup,
    String? startMiti,
    String? endMiti,
  }) {
    final filteredVch = _filterVouchers(
      startDate: startDate,
      endDate: endDate,
      party: party,
      startMiti: startMiti,
      endMiti: endMiti,
    );
    final Set<String> validVchKeys = filteredVch.map((v) => '${v['vch_type']}__${v['vch_no']}').toSet();

    final Map<String, String> productToGroup = {
      for (final p in _products)
        (p['product_name'] as String).trim().toLowerCase(): (p['group_name'] as String).trim().toLowerCase()
    };

    return _salesItems.where((item) {
      final vchKey = '${item['vch_type']}__${item['vch_no']}';
      if (!validVchKeys.contains(vchKey)) return false;

      if (productGroup != null && productGroup.isNotEmpty) {
        final pName = (item['product_name'] as String?)?.trim().toLowerCase() ?? '';
        final group = productToGroup[pName] ?? 'unmapped';
        if (group != productGroup.trim().toLowerCase()) return false;
      }

      return true;
    }).toList();
  }

  // --- QUERY METHODS ---

  Future<List<GroupSales>> getGroupSales({String? startDate, String? endDate, String? party}) async {
    final filteredItems = _filterSalesItems(startDate: startDate, endDate: endDate, party: party);
    
    final Map<String, String> productToGroup = {
      for (final p in _products)
        p['product_name'].toString(): p['group_name'].toString()
    };

    final Map<String, double> vchToProfitPct = {
      for (final v in _vouchers)
        '${v['vch_type']}__${v['vch_no']}': (v['profit_pct'] as num?)?.toDouble() ?? 0.0
    };

    final Map<String, List<Map<String, dynamic>>> grouped = {};
    for (final item in filteredItems) {
      final pName = item['product_name'] as String;
      final group = productToGroup[pName] ?? 'Unmapped';
      grouped.putIfAbsent(group, () => []).add(item);
    }

    final List<GroupSales> result = [];
    grouped.forEach((groupName, items) {
      final orderLinesCount = items.length;
      final totalQuantity = items.fold<double>(0.0, (sum, item) => sum + ((item['quantity'] as num?)?.toDouble() ?? 0.0));
      final totalSalesValue = items.fold<double>(0.0, (sum, item) => sum + ((item['value'] as num?)?.toDouble() ?? 0.0));
      
      final estimatedProfit = items.fold<double>(0.0, (sum, item) {
        final vchKey = '${item['vch_type']}__${item['vch_no']}';
        final profitPct = vchToProfitPct[vchKey] ?? 0.0;
        final val = (item['value'] as num?)?.toDouble() ?? 0.0;
        return sum + (val * profitPct / 100.0);
      });

      final margin = totalSalesValue > 0 ? (estimatedProfit / totalSalesValue) * 100.0 : 0.0;

      result.add(GroupSales(
        productGroup: groupName,
        orderLinesCount: orderLinesCount,
        totalQuantity: totalQuantity,
        totalSalesValue: totalSalesValue,
        estimatedProfit: estimatedProfit,
        profitMarginPct: margin,
      ));
    });

    return result;
  }

  Future<List<CustomerSales>> getTopCustomers({int? limit, String? startDate, String? endDate, String? productGroup}) async {
    final List<CustomerSales> list = [];

    if (productGroup != null && productGroup.isNotEmpty) {
      final filteredItems = _filterSalesItems(startDate: startDate, endDate: endDate, productGroup: productGroup);
      
      final Map<String, double> vchToProfitPct = {
        for (final v in _vouchers)
          '${v['vch_type']}__${v['vch_no']}': (v['profit_pct'] as num?)?.toDouble() ?? 0.0
      };

      final Map<String, List<Map<String, dynamic>>> grouped = {};
      for (final item in filteredItems) {
        final party = item['party'] as String? ?? 'Unknown';
        grouped.putIfAbsent(party, () => []).add(item);
      }

      grouped.forEach((partyName, items) {
        final totalSales = items.fold<double>(0.0, (sum, i) => sum + ((i['value'] as num?)?.toDouble() ?? 0.0));
        final totalProfit = items.fold<double>(0.0, (sum, i) {
          final vKey = '${i['vch_type']}__${i['vch_no']}';
          final pct = vchToProfitPct[vKey] ?? 0.0;
          final val = (i['value'] as num?)?.toDouble() ?? 0.0;
          return sum + (val * pct / 100.0);
        });
        final vouchersCount = items.map((i) => '${i['vch_type']}__${i['vch_no']}').toSet().length;
        final avgOrder = vouchersCount > 0 ? totalSales / vouchersCount : 0.0;
        final margin = totalSales > 0 ? (totalProfit / totalSales) * 100.0 : 0.0;

        list.add(CustomerSales(
          party: partyName,
          totalSales: totalSales,
          totalProfit: totalProfit,
          vouchersCount: vouchersCount,
          avgOrderValue: avgOrder,
          profitMarginPct: margin,
        ));
      });
    } else {
      final filteredVch = _filterVouchers(startDate: startDate, endDate: endDate);
      final Map<String, List<Map<String, dynamic>>> grouped = {};
      for (final v in filteredVch) {
        final party = v['party'] as String? ?? 'Unknown';
        grouped.putIfAbsent(party, () => []).add(v);
      }

      grouped.forEach((partyName, vchs) {
        final totalSales = vchs.fold<double>(0.0, (sum, v) => sum + ((v['value'] as num?)?.toDouble() ?? 0.0));
        final totalProfit = vchs.fold<double>(0.0, (sum, v) => sum + ((v['profit'] as num?)?.toDouble() ?? 0.0));
        final vouchersCount = vchs.length;
        final avgOrder = vouchersCount > 0 ? totalSales / vouchersCount : 0.0;
        final margin = totalSales > 0 ? (totalProfit / totalSales) * 100.0 : 0.0;

        list.add(CustomerSales(
          party: partyName,
          totalSales: totalSales,
          totalProfit: totalProfit,
          vouchersCount: vouchersCount,
          avgOrderValue: avgOrder,
          profitMarginPct: margin,
        ));
      });
    }

    list.sort((a, b) => b.totalSales.compareTo(a.totalSales));
    if (limit != null) {
      return list.take(limit).toList();
    }
    return list;
  }

  Future<List<CustomerSales>> getTopSellers({int? limit, String? startDate, String? endDate, String? productGroup}) async {
    return getTopCustomers(limit: limit, startDate: startDate, endDate: endDate, productGroup: productGroup);
  }

  Future<List<ProductSales>> getTopProducts({int? limit, String? startDate, String? endDate, String? party, String? productGroup}) async {
    final filteredItems = _filterSalesItems(startDate: startDate, endDate: endDate, party: party, productGroup: productGroup);

    final Map<String, List<Map<String, dynamic>>> grouped = {};
    for (final item in filteredItems) {
      final name = item['product_name'] as String;
      grouped.putIfAbsent(name, () => []).add(item);
    }

    final List<ProductSales> result = [];
    grouped.forEach((pName, items) {
      final totalSalesValue = items.fold<double>(0.0, (sum, i) => sum + ((i['value'] as num?)?.toDouble() ?? 0.0));
      final totalQuantity = items.fold<double>(0.0, (sum, i) => sum + ((i['quantity'] as num?)?.toDouble() ?? 0.0));
      final totalRates = items.fold<double>(0.0, (sum, i) => sum + ((i['rate'] as num?)?.toDouble() ?? 0.0));
      final avgRate = items.isNotEmpty ? totalRates / items.length : 0.0;
      final txCount = items.length;

      result.add(ProductSales(
        productName: pName,
        totalSalesValue: totalSalesValue,
        totalQuantity: totalQuantity,
        averageRate: avgRate,
        transactionsCount: txCount,
      ));
    });

    result.sort((a, b) => b.totalSalesValue.compareTo(a.totalSalesValue));
    if (limit != null) {
      return result.take(limit).toList();
    }
    return result;
  }

  Future<List<ProductSales>> getTopSalesProducts({int? limit, String? startDate, String? endDate, String? party, String? productGroup}) async {
    return getTopProducts(limit: limit, startDate: startDate, endDate: endDate, party: party, productGroup: productGroup);
  }

  Future<List<DailyTrend>> getDailyTrends({String? startDate, String? endDate, String? party, String? productGroup}) async {
    final List<DailyTrend> list = [];

    if (productGroup != null && productGroup.isNotEmpty) {
      final filteredItems = _filterSalesItems(startDate: startDate, endDate: endDate, party: party, productGroup: productGroup);
      final Map<String, double> vchToProfitPct = {
        for (final v in _vouchers)
          '${v['vch_type']}__${v['vch_no']}': (v['profit_pct'] as num?)?.toDouble() ?? 0.0
      };

      final Map<String, List<Map<String, dynamic>>> grouped = {};
      for (final item in filteredItems) {
        final dStr = (item['date'] as String).split(' ')[0];
        grouped.putIfAbsent(dStr, () => []).add(item);
      }

      grouped.forEach((dateStr, items) {
        final sales = items.fold<double>(0.0, (sum, i) => sum + ((i['value'] as num?)?.toDouble() ?? 0.0));
        final profit = items.fold<double>(0.0, (sum, i) {
          final vKey = '${i['vch_type']}__${i['vch_no']}';
          final pct = vchToProfitPct[vKey] ?? 0.0;
          final val = (i['value'] as num?)?.toDouble() ?? 0.0;
          return sum + (val * pct / 100.0);
        });
        final count = items.map((i) => '${i['vch_type']}__${i['vch_no']}').toSet().length;

        list.add(DailyTrend(
          dateStr: dateStr,
          dailySales: sales,
          dailyProfit: profit,
          vouchersCount: count,
        ));
      });
    } else {
      final filteredVch = _filterVouchers(startDate: startDate, endDate: endDate, party: party);
      final Map<String, List<Map<String, dynamic>>> grouped = {};
      for (final v in filteredVch) {
        final dStr = (v['date'] as String).split(' ')[0];
        grouped.putIfAbsent(dStr, () => []).add(v);
      }

      grouped.forEach((dateStr, vchs) {
        final sales = vchs.fold<double>(0.0, (sum, v) => sum + ((v['value'] as num?)?.toDouble() ?? 0.0));
        final profit = vchs.fold<double>(0.0, (sum, v) => sum + ((v['profit'] as num?)?.toDouble() ?? 0.0));
        final count = vchs.length;

        list.add(DailyTrend(
          dateStr: dateStr,
          dailySales: sales,
          dailyProfit: profit,
          vouchersCount: count,
        ));
      });
    }

    list.sort((a, b) => a.dateStr.compareTo(b.dateStr));
    return list;
  }

  Future<List<PricingConsistency>> getPricingConsistency({int? minSales, String? startDate, String? endDate, String? party, String? productGroup}) async {
    final minS = minSales ?? 5;
    final filteredItems = _filterSalesItems(startDate: startDate, endDate: endDate, party: party, productGroup: productGroup)
        .where((item) => (item['product_name'] as String).trim().toLowerCase() != 'indian item')
        .toList();

    final Map<String, List<Map<String, dynamic>>> grouped = {};
    for (final item in filteredItems) {
      final name = item['product_name'] as String;
      grouped.putIfAbsent(name, () => []).add(item);
    }

    final List<PricingConsistency> result = [];

    grouped.forEach((productName, items) {
      final salesCount = items.length;
      if (salesCount < minS) return;

      final rates = items.map((i) => ((i['rate'] as num?)?.toDouble() ?? 0.0)).toList();
      final minRate = rates.reduce(min);
      final maxRate = rates.reduce(max);

      // Mode
      final Map<double, int> freq = {};
      for (final r in rates) {
        freq[r] = (freq[r] ?? 0) + 1;
      }
      int maxFreq = 0;
      double modeRate = rates[0];
      final sortedKeys = freq.keys.toList()..sort();
      for (final k in sortedKeys) {
        if (freq[k]! > maxFreq) {
          maxFreq = freq[k]!;
          modeRate = k;
        }
      }

      double avgRate;
      if (rates.isNotEmpty) {
        final lower = modeRate * 0.9;
        final upper = modeRate * 1.1;
        final filteredRates = rates.where((r) => r >= lower && r <= upper).toList();
        if (filteredRates.isNotEmpty) {
          avgRate = filteredRates.reduce((a, b) => a + b) / filteredRates.length;
        } else {
          avgRate = rates.reduce((a, b) => a + b) / rates.length;
        }
      } else {
        avgRate = 0.0;
      }

      double stdRate = 0.0;
      if (salesCount > 1) {
        final meanRate = rates.reduce((a, b) => a + b) / salesCount;
        final variance = rates.map((r) => pow(r - meanRate, 2)).reduce((a, b) => a + b) / (salesCount - 1);
        stdRate = sqrt(variance);
      }

      final minInvoices = items.where((i) => ((i['rate'] as num?)?.toDouble() ?? 0.0) == minRate)
          .map((i) => i['vch_no'].toString())
          .toSet()
          .map((no) => '#$no (@ ${minRate.toStringAsFixed(2)})')
          .join(', ');

      final maxInvoices = items.where((i) => ((i['rate'] as num?)?.toDouble() ?? 0.0) == maxRate)
          .map((i) => i['vch_no'].toString())
          .toSet()
          .map((no) => '#$no (@ ${maxRate.toStringAsFixed(2)})')
          .join(', ');

      final spread = avgRate > 0 ? ((maxRate - minRate) / avgRate) * 100.0 : 0.0;

      result.add(PricingConsistency(
        productName: productName,
        minRate: minRate,
        maxRate: maxRate,
        avgRate: avgRate,
        stdRate: stdRate.isNaN ? 0.0 : stdRate,
        salesCount: salesCount,
        rateSpreadPct: spread,
        minRateInvoices: minInvoices,
        maxRateInvoices: maxInvoices,
      ));
    });

    result.sort((a, b) => b.rateSpreadPct.compareTo(a.rateSpreadPct));
    return result;
  }

  Future<List<WeekdaySales>> getWeekdaySales({String? startDate, String? endDate, String? party, String? productGroup}) async {
    final List<WeekdaySales> list = [];
    final List<Map<String, dynamic>> records;
    final bool isProductGroup = productGroup != null && productGroup.isNotEmpty;

    if (isProductGroup) {
      records = _filterSalesItems(startDate: startDate, endDate: endDate, party: party, productGroup: productGroup);
    } else {
      records = _filterVouchers(startDate: startDate, endDate: endDate, party: party);
    }

    final order = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
    final Map<String, List<Map<String, dynamic>>> grouped = {};

    for (final r in records) {
      final dateStr = (r['date'] as String).split(' ')[0];
      final dt = DateTime.parse(dateStr);
      final dayName = _getWeekdayName(dt.weekday);
      grouped.putIfAbsent(dayName, () => []).add(r);
    }

    grouped.forEach((dayName, rows) {
      final totalSales = rows.fold<double>(0.0, (sum, r) => sum + ((r['value'] as num?)?.toDouble() ?? 0.0));
      final count = isProductGroup 
          ? rows.map((r) => '${r['vch_type']}__${r['vch_no']}').toSet().length 
          : rows.length;

      list.add(WeekdaySales(
        dayOfWeek: dayName,
        totalSales: totalSales,
        vouchersCount: count,
      ));
    });

    list.sort((a, b) {
      final idxA = order.indexOf(a.dayOfWeek);
      final idxB = order.indexOf(b.dayOfWeek);
      return idxA.compareTo(idxB);
    });

    return list;
  }

  String _getWeekdayName(int weekday) {
    switch (weekday) {
      case DateTime.monday: return 'Monday';
      case DateTime.tuesday: return 'Tuesday';
      case DateTime.wednesday: return 'Wednesday';
      case DateTime.thursday: return 'Thursday';
      case DateTime.friday: return 'Friday';
      case DateTime.saturday: return 'Saturday';
      case DateTime.sunday: return 'Sunday';
      default: return 'Unknown';
    }
  }

  Future<ParetoAnalysis> getParetoAnalysis({String? startDate, String? endDate}) async {
    final filteredVch = _filterVouchers(startDate: startDate, endDate: endDate);
    final filteredItems = _filterSalesItems(startDate: startDate, endDate: endDate);

    if (filteredVch.isEmpty || filteredItems.isEmpty) {
      return ParetoAnalysis(
        totalSales: 0.0,
        totalUniqueParties: 0,
        partiesGenerating80PercentSales: 0,
        percentageOfPartiesGenerating80Percent: 0.0,
        totalUniqueProducts: 0,
        productsGenerating80PercentSales: 0,
        percentageOfProductsGenerating80Percent: 0.0,
      );
    }

    // Party Pareto
    final Map<String, double> partySales = {};
    for (final v in filteredVch) {
      final p = v['party'] as String? ?? 'Unknown';
      partySales[p] = (partySales[p] ?? 0.0) + ((v['value'] as num?)?.toDouble() ?? 0.0);
    }
    final totalPartySales = partySales.values.reduce((a, b) => a + b);
    final sortedParties = partySales.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    double cumulativePartySales = 0.0;
    int parties80 = 0;
    for (final entry in sortedParties) {
      cumulativePartySales += entry.value;
      if ((cumulativePartySales / totalPartySales) * 100.0 <= 85.0) {
        parties80++;
      } else {
        break;
      }
    }
    final numParties80 = parties80 + 1;
    final pctParties80 = (numParties80 / sortedParties.length) * 100.0;

    // Product Pareto
    final Map<String, double> productSales = {};
    for (final item in filteredItems) {
      final p = item['product_name'] as String;
      productSales[p] = (productSales[p] ?? 0.0) + ((item['value'] as num?)?.toDouble() ?? 0.0);
    }
    final totalProductSales = productSales.values.reduce((a, b) => a + b);
    final sortedProducts = productSales.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    double cumulativeProductSales = 0.0;
    int products80 = 0;
    for (final entry in sortedProducts) {
      cumulativeProductSales += entry.value;
      if ((cumulativeProductSales / totalProductSales) * 100.0 <= 85.0) {
        products80++;
      } else {
        break;
      }
    }
    final numProducts80 = products80 + 1;
    final pctProducts80 = (numProducts80 / sortedProducts.length) * 100.0;

    return ParetoAnalysis(
      totalSales: totalPartySales,
      totalUniqueParties: sortedParties.length,
      partiesGenerating80PercentSales: numParties80,
      percentageOfPartiesGenerating80Percent: double.parse(pctParties80.toStringAsFixed(2)),
      totalUniqueProducts: sortedProducts.length,
      productsGenerating80PercentSales: numProducts80,
      percentageOfProductsGenerating80Percent: double.parse(pctProducts80.toStringAsFixed(2)),
    );
  }

  Future<List<MitiDailyTrend>> getMitiDailyTrends({String? startDate, String? endDate, String? party, String? productGroup, String? startMiti, String? endMiti}) async {
    final List<MitiDailyTrend> list = [];
    final bool isProductGroup = productGroup != null && productGroup.isNotEmpty;

    if (isProductGroup) {
      final filteredItems = _filterSalesItems(startDate: startDate, endDate: endDate, party: party, productGroup: productGroup, startMiti: startMiti, endMiti: endMiti);
      final Map<String, double> vchToProfitPct = {
        for (final v in _vouchers)
          '${v['vch_type']}__${v['vch_no']}': (v['profit_pct'] as num?)?.toDouble() ?? 0.0
      };
      final Map<String, String> vchToMiti = {
        for (final v in _vouchers)
          '${v['vch_type']}__${v['vch_no']}': v['miti'] as String? ?? ''
      };

      final Map<String, List<Map<String, dynamic>>> grouped = {};
      for (final item in filteredItems) {
        final vKey = '${item['vch_type']}__${item['vch_no']}';
        final miti = vchToMiti[vKey] ?? '';
        if (miti.isNotEmpty && miti.length == 10) {
          grouped.putIfAbsent(miti, () => []).add(item);
        }
      }

      grouped.forEach((miti, items) {
        final sales = items.fold<double>(0.0, (sum, i) => sum + ((i['value'] as num?)?.toDouble() ?? 0.0));
        final profit = items.fold<double>(0.0, (sum, i) {
          final vKey = '${i['vch_type']}__${i['vch_no']}';
          final pct = vchToProfitPct[vKey] ?? 0.0;
          final val = (i['value'] as num?)?.toDouble() ?? 0.0;
          return sum + (val * pct / 100.0);
        });
        final count = items.map((i) => '${i['vch_type']}__${i['vch_no']}').toSet().length;

        list.add(MitiDailyTrend(
          miti: miti,
          dailySales: sales,
          dailyProfit: profit,
          vouchersCount: count,
        ));
      });
    } else {
      final filteredVch = _filterVouchers(startDate: startDate, endDate: endDate, party: party, startMiti: startMiti, endMiti: endMiti);
      final Map<String, List<Map<String, dynamic>>> grouped = {};
      for (final v in filteredVch) {
        final miti = v['miti'] as String? ?? '';
        if (miti.isNotEmpty && miti.length == 10) {
          grouped.putIfAbsent(miti, () => []).add(v);
        }
      }

      grouped.forEach((miti, vchs) {
        final sales = vchs.fold<double>(0.0, (sum, v) => sum + ((v['value'] as num?)?.toDouble() ?? 0.0));
        final profit = vchs.fold<double>(0.0, (sum, v) => sum + ((v['profit'] as num?)?.toDouble() ?? 0.0));
        final count = vchs.length;

        list.add(MitiDailyTrend(
          miti: miti,
          dailySales: sales,
          dailyProfit: profit,
          vouchersCount: count,
        ));
      });
    }

    list.sort((a, b) => _getMitiKey(a.miti).compareTo(_getMitiKey(b.miti)));
    return list;
  }

  Future<List<MitiMonthlyTrend>> getMitiMonthlyTrends({String? startDate, String? endDate, String? party, String? productGroup, String? startMiti, String? endMiti}) async {
    final List<MitiMonthlyTrend> list = [];
    final bool isProductGroup = productGroup != null && productGroup.isNotEmpty;

    final nepaliMonths = {
      '01': 'Baishakh', '02': 'Jestha', '03': 'Ashadh', '04': 'Shrawan',
      '05': 'Bhadra', '06': 'Ashwin', '07': 'Kartik', '08': 'Mangsir',
      '09': 'Poush', '10': 'Magh', '11': 'Falgun', '12': 'Chaitra'
    };

    final Map<String, List<Map<String, dynamic>>> grouped = {};

    if (isProductGroup) {
      final filteredItems = _filterSalesItems(startDate: startDate, endDate: endDate, party: party, productGroup: productGroup, startMiti: startMiti, endMiti: endMiti);
      final Map<String, double> vchToProfitPct = {
        for (final v in _vouchers)
          '${v['vch_type']}__${v['vch_no']}': (v['profit_pct'] as num?)?.toDouble() ?? 0.0
      };
      final Map<String, String> vchToMiti = {
        for (final v in _vouchers)
          '${v['vch_type']}__${v['vch_no']}': v['miti'] as String? ?? ''
      };

      for (final item in filteredItems) {
        final vKey = '${item['vch_type']}__${item['vch_no']}';
        final miti = vchToMiti[vKey] ?? '';
        if (miti.isNotEmpty && miti.length == 10) {
          final parts = miti.split('-');
          final yr = parts[2];
          final code = parts[1];
          grouped.putIfAbsent('$yr-$code', () => []).add(item);
        }
      }

      grouped.forEach((key, items) {
        final parts = key.split('-');
        final yr = parts[0];
        final code = parts[1];
        final name = nepaliMonths[code] ?? 'Month $code';

        final sales = items.fold<double>(0.0, (sum, i) => sum + ((i['value'] as num?)?.toDouble() ?? 0.0));
        final profit = items.fold<double>(0.0, (sum, i) {
          final vKey = '${i['vch_type']}__${i['vch_no']}';
          final pct = vchToProfitPct[vKey] ?? 0.0;
          final val = (i['value'] as num?)?.toDouble() ?? 0.0;
          return sum + (val * pct / 100.0);
        });
        final count = items.map((i) => '${i['vch_type']}__${i['vch_no']}').toSet().length;

        list.add(MitiMonthlyTrend(
          year: yr,
          monthCode: code,
          monthName: name,
          monthlySales: sales,
          monthlyProfit: profit,
          vouchersCount: count,
          period: '$name $yr',
        ));
      });
    } else {
      final filteredVch = _filterVouchers(startDate: startDate, endDate: endDate, party: party, startMiti: startMiti, endMiti: endMiti);
      
      for (final v in filteredVch) {
        final miti = v['miti'] as String? ?? '';
        if (miti.isNotEmpty && miti.length == 10) {
          final parts = miti.split('-');
          final yr = parts[2];
          final code = parts[1];
          grouped.putIfAbsent('$yr-$code', () => []).add(v);
        }
      }

      grouped.forEach((key, vchs) {
        final parts = key.split('-');
        final yr = parts[0];
        final code = parts[1];
        final name = nepaliMonths[code] ?? 'Month $code';

        final sales = vchs.fold<double>(0.0, (sum, v) => sum + ((v['value'] as num?)?.toDouble() ?? 0.0));
        final profit = vchs.fold<double>(0.0, (sum, v) => sum + ((v['profit'] as num?)?.toDouble() ?? 0.0));
        final count = vchs.length;

        list.add(MitiMonthlyTrend(
          year: yr,
          monthCode: code,
          monthName: name,
          monthlySales: sales,
          monthlyProfit: profit,
          vouchersCount: count,
          period: '$name $yr',
        ));
      });
    }

    list.sort((a, b) {
      final compYr = a.year.compareTo(b.year);
      if (compYr != 0) return compYr;
      return a.monthCode.compareTo(b.monthCode);
    });

    return list;
  }

  Future<List<CustomerRetention>> getCustomerRetention({String? startDate, String? endDate}) async {
    final filteredVch = _filterVouchers(startDate: startDate, endDate: endDate)
        .where((v) => v['party'] != null && (v['party'] as String).trim().isNotEmpty)
        .toList();

    if (filteredVch.isEmpty) return [];

    final Map<String, List<Map<String, dynamic>>> grouped = {};
    for (final v in filteredVch) {
      final p = v['party'] as String;
      grouped.putIfAbsent(p, () => []).add(v);
    }

    DateTime? maxDatasetDate;
    for (final v in filteredVch) {
      final dStr = (v['date'] as String).split(' ')[0];
      final dt = DateTime.parse(dStr);
      if (maxDatasetDate == null || dt.isAfter(maxDatasetDate)) {
        maxDatasetDate = dt;
      }
    }
    maxDatasetDate ??= DateTime.now();

    final List<CustomerRetention> list = [];

    grouped.forEach((partyName, vchs) {
      final dates = vchs.map((v) => DateTime.parse((v['date'] as String).split(' ')[0])).toList()..sort();
      final firstOrder = dates.first;
      final lastOrder = dates.last;

      final inactiveDays = maxDatasetDate!.difference(lastOrder).inDays;

      double? avgInterval;
      if (dates.length >= 2) {
        int totalDiffs = 0;
        for (int i = 1; i < dates.length; i++) {
          totalDiffs += dates[i].difference(dates[i - 1]).inDays;
        }
        avgInterval = totalDiffs / (dates.length - 1);
      }

      String status;
      if (inactiveDays <= 3) {
        status = 'Active';
      } else if (inactiveDays <= 7) {
        status = 'Slowing Down';
      } else {
        status = 'Churn Risk';
      }

      final totalOrders = vchs.length;
      final totalRev = vchs.fold<double>(0.0, (sum, v) => sum + ((v['value'] as num?)?.toDouble() ?? 0.0));
      final avgVal = totalRev / totalOrders;

      list.add(CustomerRetention(
        party: partyName,
        firstOrderDate: firstOrder.toIso8601String().split('T')[0],
        lastOrderDate: lastOrder.toIso8601String().split('T')[0],
        totalOrders: totalOrders,
        totalRevenue: double.parse(totalRev.toStringAsFixed(2)),
        avgOrderValue: double.parse(avgVal.toStringAsFixed(2)),
        avgOrderIntervalDays: avgInterval != null ? double.parse(avgInterval.toStringAsFixed(2)) : 0.0,
        inactiveDays: inactiveDays,
        status: status,
      ));
    });

    list.sort((a, b) => b.totalRevenue.compareTo(a.totalRevenue));
    return list;
  }

  Future<List<VoucherTypeSales>> getSalesByVoucherType({String? startDate, String? endDate, String? party}) async {
    final filteredVch = _filterVouchers(startDate: startDate, endDate: endDate, party: party);
    final Map<String, List<Map<String, dynamic>>> grouped = {};
    for (final v in filteredVch) {
      final t = v['vch_type'] as String? ?? 'Unknown';
      grouped.putIfAbsent(t, () => []).add(v);
    }

    final List<VoucherTypeSales> list = [];
    grouped.forEach((vchType, vchs) {
      final totalSales = vchs.fold<double>(0.0, (sum, v) => sum + ((v['value'] as num?)?.toDouble() ?? 0.0));
      final totalProfit = vchs.fold<double>(0.0, (sum, v) => sum + ((v['profit'] as num?)?.toDouble() ?? 0.0));
      final margin = totalSales > 0 ? (totalProfit / totalSales) * 100.0 : 0.0;

      list.add(VoucherTypeSales(
        vchType: vchType,
        totalSales: totalSales,
        totalProfit: totalProfit,
        vouchersCount: vchs.length,
        profitMarginPct: margin,
      ));
    });

    list.sort((a, b) => b.totalSales.compareTo(a.totalSales));
    return list;
  }

  Future<List<HighMarginProduct>> getHighestMarginProducts({int? limit, String? startDate, String? endDate, String? productGroup}) async {
    final filteredItems = _filterSalesItems(startDate: startDate, endDate: endDate, productGroup: productGroup);
    final Map<String, double> vchToProfitPct = {
      for (final v in _vouchers)
        '${v['vch_type']}__${v['vch_no']}': (v['profit_pct'] as num?)?.toDouble() ?? 0.0
    };

    final Map<String, List<Map<String, dynamic>>> grouped = {};
    for (final item in filteredItems) {
      final name = item['product_name'] as String;
      grouped.putIfAbsent(name, () => []).add(item);
    }

    final List<HighMarginProduct> list = [];
    grouped.forEach((productName, items) {
      final totalSalesValue = items.fold<double>(0.0, (sum, i) => sum + ((i['value'] as num?)?.toDouble() ?? 0.0));
      final totalQuantity = items.fold<double>(0.0, (sum, i) => sum + ((i['quantity'] as num?)?.toDouble() ?? 0.0));
      
      final totalProfit = items.fold<double>(0.0, (sum, i) {
        final vKey = '${i['vch_type']}__${i['vch_no']}';
        final pct = vchToProfitPct[vKey] ?? 0.0;
        final val = (i['value'] as num?)?.toDouble() ?? 0.0;
        return sum + (val * pct / 100.0);
      });

      final margin = totalSalesValue > 0 ? (totalProfit / totalSalesValue) * 100.0 : 0.0;

      list.add(HighMarginProduct(
        productName: productName,
        totalSalesValue: totalSalesValue,
        totalQuantity: totalQuantity,
        totalProfit: totalProfit,
        averageMarginPct: margin,
      ));
    });

    list.sort((a, b) => b.averageMarginPct.compareTo(a.averageMarginPct));
    if (limit != null) {
      return list.take(limit).toList();
    }
    return list;
  }

  Future<List<HighMarginCustomer>> getHighestMarginCustomers({int? limit, String? startDate, String? endDate}) async {
    final filteredVch = _filterVouchers(startDate: startDate, endDate: endDate)
        .where((v) => v['party'] != null && (v['party'] as String).trim().isNotEmpty)
        .toList();

    final Map<String, List<Map<String, dynamic>>> grouped = {};
    for (final v in filteredVch) {
      final p = v['party'] as String;
      grouped.putIfAbsent(p, () => []).add(v);
    }

    final List<HighMarginCustomer> list = [];
    grouped.forEach((partyName, vchs) {
      final totalSales = vchs.fold<double>(0.0, (sum, v) => sum + ((v['value'] as num?)?.toDouble() ?? 0.0));
      final totalProfit = vchs.fold<double>(0.0, (sum, v) => sum + ((v['profit'] as num?)?.toDouble() ?? 0.0));
      final margin = totalSales > 0 ? (totalProfit / totalSales) * 100.0 : 0.0;

      list.add(HighMarginCustomer(
        party: partyName,
        totalSales: totalSales,
        totalProfit: totalProfit,
        profitMarginPct: margin,
      ));
    });

    list.sort((a, b) => b.profitMarginPct.compareTo(a.profitMarginPct));
    if (limit != null) {
      return list.take(limit).toList();
    }
    return list;
  }

  Future<List<ImportForecast>> getImportForecast({int? days}) async {
    final durationDays = days ?? 90;
    if (_salesItems.isEmpty) return [];

    DateTime? maxDate;
    for (final i in _salesItems) {
      final dStr = (i['date'] as String).split(' ')[0];
      final dt = DateTime.parse(dStr);
      if (maxDate == null || dt.isAfter(maxDate)) {
        maxDate = dt;
      }
    }
    maxDate ??= DateTime.now();
    final cutoffDate = maxDate.subtract(Duration(days: durationDays));

    final recentItems = _salesItems.where((i) {
      final dt = DateTime.parse((i['date'] as String).split(' ')[0]);
      return dt.isAfter(cutoffDate) || dt.isAtSameMomentAs(cutoffDate);
    }).toList();

    if (recentItems.isEmpty) return [];

    final Map<String, String> productToGroup = {
      for (final p in _products)
        p['product_name'].toString(): p['group_name'].toString()
    };

    final Map<String, List<Map<String, dynamic>>> grouped = {};
    for (final i in recentItems) {
      final name = i['product_name'] as String;
      grouped.putIfAbsent(name, () => []).add(i);
    }

    final List<ImportForecast> list = [];
    grouped.forEach((productName, items) {
      final totalQty = items.fold<double>(0.0, (sum, i) => sum + ((i['quantity'] as num?)?.toDouble() ?? 0.0));
      final totalSales = items.fold<double>(0.0, (sum, i) => sum + ((i['value'] as num?)?.toDouble() ?? 0.0));
      
      final monthlyRunRate = (totalQty / durationDays) * 30.0;
      final projected3Month = monthlyRunRate * 3.0;
      final suggestedOrder = projected3Month * 1.25;

      list.add(ImportForecast(
        productName: productName,
        groupName: productToGroup[productName] ?? 'Unmapped',
        totalQuantity: double.parse(totalQty.toStringAsFixed(1)),
        totalSalesValue: double.parse(totalSales.toStringAsFixed(2)),
        salesCount: items.length,
        monthlyRunRate: double.parse(monthlyRunRate.toStringAsFixed(1)),
        projected3MonthDemand: double.parse(projected3Month.toStringAsFixed(1)),
        suggestedOrderQty: suggestedOrder.isNaN || suggestedOrder.isInfinite ? 0 : suggestedOrder.round(),
      ));
    });

    list.sort((a, b) => b.suggestedOrderQty.compareTo(a.suggestedOrderQty));
    return list;
  }

  Future<List<MarketBasketPair>> getMarketBasket({String? startDate, String? endDate, String? party, String? productGroup, int? minSupport, int? topN}) async {
    final support = minSupport ?? 2;
    final limit = topN ?? 15;

    final filteredItems = _filterSalesItems(startDate: startDate, endDate: endDate, party: party, productGroup: productGroup);
    if (filteredItems.isEmpty) return [];

    final Map<String, Set<String>> basket = {};
    for (final i in filteredItems) {
      final key = '${i['vch_type']}__${i['vch_no']}';
      final p = i['product_name'] as String;
      basket.putIfAbsent(key, () => {}).add(p);
    }

    final Map<String, int> pairCounts = {};

    basket.forEach((vchKey, products) {
      final prodList = products.toList()..sort();
      final n = prodList.length;
      if (n < 2) return;

      for (int i = 0; i < n; i++) {
        for (int j = i + 1; j < n; j++) {
          final pA = prodList[i];
          final pB = prodList[j];
          final pairKey = '${pA}__SPLIT__$pB';
          pairCounts[pairKey] = (pairCounts[pairKey] ?? 0) + 1;
        }
      }
    });

    final List<MarketBasketPair> list = [];
    pairCounts.forEach((pairKey, count) {
      if (count >= support) {
        final parts = pairKey.split('__SPLIT__');
        list.add(MarketBasketPair(
          productA: parts[0],
          productB: parts[1],
          frequency: count,
        ));
      }
    });

    list.sort((a, b) => b.frequency.compareTo(a.frequency));
    return list.take(limit).toList();
  }

  Future<List<CustomerCLV>> getCustomerCLV({String? startDate, String? endDate, String? party}) async {
    final filteredVch = _filterVouchers(startDate: startDate, endDate: endDate, party: party)
        .where((v) => v['party'] != null && (v['party'] as String).trim().isNotEmpty)
        .toList();

    if (filteredVch.isEmpty) return [];

    final Map<String, List<Map<String, dynamic>>> grouped = {};
    for (final v in filteredVch) {
      final p = v['party'] as String;
      grouped.putIfAbsent(p, () => []).add(v);
    }

    final List<CustomerCLV> list = [];

    grouped.forEach((partyName, vchs) {
      final totalRev = vchs.fold<double>(0.0, (sum, v) => sum + ((v['revenue'] as num?)?.toDouble() ?? 0.0));
      if (totalRev <= 0) return;

      final totalOrders = vchs.map((v) => '${v['vch_type']}__${v['vch_no']}').toSet().length;

      final dates = vchs.map((v) => DateTime.parse((v['date'] as String).split(' ')[0])).toList()..sort();
      final firstDate = dates.first;
      final lastDate = dates.last;

      int lifespan = lastDate.difference(firstDate).inDays;
      if (lifespan <= 0) lifespan = 1;

      final avgOrder = totalRev / totalOrders;
      final freq = (totalOrders / lifespan) * 365.0;
      final clv = avgOrder * freq;

      list.add(CustomerCLV(
        party: partyName,
        totalRevenue: double.parse(totalRev.toStringAsFixed(2)),
        totalOrders: totalOrders,
        averageOrderValue: double.parse(avgOrder.toStringAsFixed(2)),
        lifespanDays: lifespan,
        purchaseFrequencyAnnual: double.parse(freq.toStringAsFixed(1)),
        estimatedAnnualClv: double.parse(clv.toStringAsFixed(2)),
        firstPurchase: firstDate.toIso8601String().split('T')[0],
        lastPurchase: lastDate.toIso8601String().split('T')[0],
      ));
    });

    list.sort((a, b) => b.totalRevenue.compareTo(a.totalRevenue));
    return list;
  }

  Future<List<SlowMovingProduct>> getSlowMovingStock({String? startDate, String? endDate, String? party, String? productGroup, int? thresholdDays}) async {
    final threshold = thresholdDays ?? 60;
    final filteredItems = _filterSalesItems(startDate: startDate, endDate: endDate, party: party, productGroup: productGroup);

    if (filteredItems.isEmpty) return [];

    final Map<String, List<Map<String, dynamic>>> grouped = {};
    for (final item in filteredItems) {
      final name = item['product_name'] as String;
      grouped.putIfAbsent(name, () => []).add(item);
    }

    DateTime? maxDate;
    for (final item in filteredItems) {
      final dStr = (item['date'] as String).split(' ')[0];
      final dt = DateTime.parse(dStr);
      if (maxDate == null || dt.isAfter(maxDate)) {
        maxDate = dt;
      }
    }
    maxDate ??= DateTime.now();

    final Map<String, String> productToGroup = {
      for (final p in _products)
        p['product_name'].toString(): p['group_name'].toString()
    };

    final List<SlowMovingProduct> list = [];

    grouped.forEach((productName, items) {
      final dates = items.map((i) => DateTime.parse((i['date'] as String).split(' ')[0])).toList()..sort();
      final lastSale = dates.last;
      final diffDays = maxDate!.difference(lastSale).inDays;

      if (diffDays >= threshold) {
        final totalQty = items.fold<double>(0.0, (sum, i) => sum + ((i['quantity'] as num?)?.toDouble() ?? 0.0));
        final totalRev = items.fold<double>(0.0, (sum, i) => sum + ((i['value'] as num?)?.toDouble() ?? 0.0));

        list.add(SlowMovingProduct(
          productName: productName,
          groupName: productToGroup[productName] ?? 'Unmapped',
          lastSaleDate: lastSale.toIso8601String().split('T')[0],
          daysSinceLastSale: diffDays,
          totalQuantity: double.parse(totalQty.toStringAsFixed(1)),
          totalRevenue: double.parse(totalRev.toStringAsFixed(2)),
        ));
      }
    });

    list.sort((a, b) => b.daysSinceLastSale.compareTo(a.daysSinceLastSale));
    return list;
  }

  Future<List<SalesForecast>> getSalesForecast({String? startDate, String? endDate, String? party, int? forecastDays}) async {
    final days = forecastDays ?? 30;
    final filteredVch = _filterVouchers(startDate: startDate, endDate: endDate, party: party);
    if (filteredVch.isEmpty) return [];

    final Map<DateTime, double> dailyRev = {};
    for (final v in filteredVch) {
      final dStr = (v['date'] as String).split(' ')[0];
      final dt = DateTime.parse(dStr);
      final rev = (v['revenue'] as num?)?.toDouble() ?? 0.0;
      dailyRev[dt] = (dailyRev[dt] ?? 0.0) + rev;
    }

    final sortedDates = dailyRev.keys.toList()..sort();
    if (sortedDates.isEmpty) return [];

    final minDate = sortedDates.first;
    final maxDate = sortedDates.last;

    final int totalDays = maxDate.difference(minDate).inDays + 1;
    final List<double> continuousRev = List.filled(totalDays, 0.0);

    dailyRev.forEach((dt, rev) {
      final index = dt.difference(minDate).inDays;
      continuousRev[index] = rev;
    });

    final List<double> ma7 = List.filled(totalDays, 0.0);
    for (int i = 0; i < totalDays; i++) {
      double sum = 0.0;
      int count = 0;
      for (int j = max(0, i - 6); j <= i; j++) {
        sum += continuousRev[j];
        count++;
      }
      ma7[i] = count > 0 ? sum / count : 0.0;
    }

    final lastMa = ma7.isNotEmpty ? ma7.last : 0.0;

    final List<SalesForecast> results = [];

    final startIdx = max(0, totalDays - 30);
    for (int i = startIdx; i < totalDays; i++) {
      final curDate = minDate.add(Duration(days: i));
      results.add(SalesForecast(
        date: curDate.toIso8601String().split('T')[0],
        actualRevenue: double.parse(continuousRev[i].toStringAsFixed(2)),
        forecastRevenue: null,
        isForecast: false,
      ));
    }

    for (int i = 1; i <= days; i++) {
      final fDate = maxDate.add(Duration(days: i));
      results.add(SalesForecast(
        date: fDate.toIso8601String().split('T')[0],
        actualRevenue: null,
        forecastRevenue: double.parse(lastMa.toStringAsFixed(2)),
        isForecast: true,
      ));
    }

    return results;
  }

  // --- PRODUCTS & GROUP MAPPING ---

  Future<List<String>> getUngroupedProducts() async {
    final Set<String> soldProducts = _salesItems
        .map((i) => i['product_name'].toString().trim())
        .where((n) => n.isNotEmpty)
        .toSet();

    final Set<String> mappedProducts = _products
        .map((p) => p['product_name'].toString().trim())
        .where((n) => n.isNotEmpty)
        .toSet();

    final ungrouped = soldProducts.difference(mappedProducts).toList()..sort();
    return ungrouped;
  }

  Future<void> assignGroup(String productName, String groupName) async {
    final pNameLower = productName.trim().toLowerCase();
    final index = _products.indexWhere((p) => (p['product_name'] as String).trim().toLowerCase() == pNameLower);

    if (index >= 0) {
      _products[index] = {
        'product_name': productName.trim(),
        'group_name': groupName.trim(),
      };
    } else {
      _products.add({
        'product_name': productName.trim(),
        'group_name': groupName.trim(),
      });
    }
  }
}
