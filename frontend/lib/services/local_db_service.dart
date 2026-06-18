import 'dart:math';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';
import '../models/analytics_models.dart';

class LocalDbService {
  static final LocalDbService _instance = LocalDbService._internal();
  factory LocalDbService() => _instance;
  LocalDbService._internal();

  Database? _db;

  Future<Database> get database async {
    if (_db != null) return _db!;
    _db = await _initDb();
    return _db!;
  }

  Future<Database> _initDb() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, 'sales_data.db');

    return await openDatabase(
      path,
      version: 1,
      onConfigure: (db) async {
        await db.execute('PRAGMA foreign_keys = ON;');
      },
      onCreate: (db, version) async {
        // Create Vouchers table
        await db.execute('''
          CREATE TABLE vouchers (
            date TEXT,
            miti TEXT,
            party TEXT,
            vch_type TEXT,
            vch_no TEXT,
            value REAL,
            revenue REAL,
            cost REAL,
            profit REAL,
            profit_pct REAL,
            PRIMARY KEY (vch_type, vch_no)
          )
        ''');

        // Create Products Group Mapping table
        await db.execute('''
          CREATE TABLE products (
            product_name TEXT PRIMARY KEY,
            group_name TEXT NOT NULL
          )
        ''');

        // Create Sales Items table
        await db.execute('''
          CREATE TABLE sales_items (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            date TEXT,
            party TEXT,
            vch_type TEXT NOT NULL,
            vch_no TEXT NOT NULL,
            product_name TEXT NOT NULL,
            quantity REAL,
            rate REAL,
            value REAL,
            FOREIGN KEY (vch_type, vch_no) REFERENCES vouchers (vch_type, vch_no) ON DELETE CASCADE
          )
        ''');

        // Indexes
        await db.execute('CREATE INDEX idx_sales_items_voucher ON sales_items (vch_type, vch_no);');
        await db.execute('CREATE INDEX idx_sales_items_product ON sales_items (product_name);');
        await db.execute('CREATE INDEX idx_vouchers_date ON vouchers (date);');
        await db.execute('CREATE INDEX idx_sales_items_date ON sales_items (date);');
      },
    );
  }

  // --- SYNC HELPERS ---

  Future<String?> getMaxTransactionDate() async {
    final db = await database;
    final maps = await db.rawQuery('SELECT MAX(date) as max_date FROM vouchers');
    if (maps.isNotEmpty && maps.first['max_date'] != null) {
      return maps.first['max_date'] as String;
    }
    return null;
  }

  Future<void> deleteRecordsFromDate(String dateStr) async {
    final db = await database;
    await db.transaction((txn) async {
      // Cascade delete is active, but delete manually just in case
      await txn.delete(
        'sales_items',
        where: 'date >= ?',
        whereArgs: [dateStr],
      );
      await txn.delete(
        'vouchers',
        where: 'date >= ?',
        whereArgs: [dateStr],
      );
    });
  }

  Future<void> bulkInsertVouchers(List<Map<String, dynamic>> vouchers) async {
    final db = await database;
    await db.transaction((txn) async {
      final batch = txn.batch();
      for (final vch in vouchers) {
        batch.insert(
          'vouchers',
          {
            'date': vch['date'],
            'miti': vch['miti'],
            'party': vch['party'],
            'vch_type': vch['vch_type'],
            'vch_no': vch['vch_no'],
            'value': vch['value'],
            'revenue': vch['revenue'],
            'cost': vch['cost'],
            'profit': vch['profit'],
            'profit_pct': vch['profit_pct'],
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
      await batch.commit(noResult: true);
    });
  }

  Future<void> bulkInsertSalesItems(List<Map<String, dynamic>> items) async {
    final db = await database;
    await db.transaction((txn) async {
      final batch = txn.batch();
      for (final item in items) {
        batch.insert(
          'sales_items',
          {
            'date': item['date'],
            'party': item['party'],
            'vch_type': item['vch_type'],
            'vch_no': item['vch_no'],
            'product_name': item['product_name'],
            'quantity': item['quantity'],
            'rate': item['rate'],
            'value': item['value'],
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
      await batch.commit(noResult: true);
    });
  }

  Future<void> bulkInsertProducts(List<Map<String, dynamic>> products) async {
    final db = await database;
    await db.transaction((txn) async {
      final batch = txn.batch();
      for (final prod in products) {
        batch.insert(
          'products',
          {
            'product_name': prod['product_name'],
            'group_name': prod['group_name'],
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
      await batch.commit(noResult: true);
    });
  }

  Future<void> clearLocalData() async {
    final db = await database;
    await db.transaction((txn) async {
      await txn.delete('sales_items');
      await txn.delete('vouchers');
      await txn.delete('products');
    });
  }

  // --- QUERY HELPER ---

  // Build filters dynamically
  void _applyFilters(
      StringBuffer query, List<dynamic> args, String tableAlias,
      {String? startDate, String? endDate, String? party, String? productGroup, String? startMiti, String? endMiti}) {
    if (startDate != null && startDate.isNotEmpty) {
      query.write(' AND $tableAlias.date >= ?');
      args.add(startDate);
    }
    if (endDate != null && endDate.isNotEmpty) {
      query.write(' AND $tableAlias.date <= ?');
      args.add(endDate);
    }
    if (party != null && party.isNotEmpty) {
      query.write(' AND LOWER(TRIM($tableAlias.party)) = LOWER(TRIM(?))');
      args.add(party);
    }
    if (startMiti != null && startMiti.isNotEmpty) {
      query.write(" AND (SUBSTR($tableAlias.miti, 7, 4) || '-' || SUBSTR($tableAlias.miti, 4, 2) || '-' || SUBSTR($tableAlias.miti, 1, 2)) >= ?");
      args.add(_getMitiKey(startMiti));
    }
    if (endMiti != null && endMiti.isNotEmpty) {
      query.write(" AND (SUBSTR($tableAlias.miti, 7, 4) || '-' || SUBSTR($tableAlias.miti, 4, 2) || '-' || SUBSTR($tableAlias.miti, 1, 2)) <= ?");
      args.add(_getMitiKey(endMiti));
    }
    if (productGroup != null && productGroup.isNotEmpty) {
      // Since productGroup refers to product group_name, we must ensure the product group filter matches
      // By checking the join or nested subquery
      query.write(" AND s.product_name IN (SELECT p.product_name FROM products p WHERE LOWER(TRIM(p.group_name)) = LOWER(TRIM(?)))");
      args.add(productGroup);
    }
  }

  String _getMitiKey(String mitiStr) {
    final parts = mitiStr.trim().split('-');
    if (parts.length == 3) {
      return '${parts[2]}-${parts[1]}-${parts[0]}';
    }
    return '';
  }

  // --- ANALYTICS QUERIES ---

  Future<List<GroupSales>> getGroupSales({String? startDate, String? endDate, String? party}) async {
    final db = await database;
    final query = StringBuffer('''
      SELECT
        COALESCE(p.group_name, 'Unmapped') as product_group,
        COUNT(*) as order_lines_count,
        SUM(s.quantity) as total_quantity,
        SUM(s.value) as total_sales_value,
        SUM(s.value * COALESCE(v.profit_pct, 0.0) / 100.0) as estimated_profit
      FROM sales_items s
      LEFT JOIN products p ON s.product_name = p.product_name
      LEFT JOIN vouchers v ON s.vch_type = v.vch_type AND s.vch_no = v.vch_no
      WHERE 1=1
    ''');
    final args = <dynamic>[];
    _applyFilters(query, args, 's', startDate: startDate, endDate: endDate, party: party);
    query.write(' GROUP BY product_group');

    final List<Map<String, dynamic>> maps = await db.rawQuery(query.toString(), args);

    return maps.map((map) {
      final totalSales = (map['total_sales_value'] as num?)?.toDouble() ?? 0.0;
      final estProfit = (map['estimated_profit'] as num?)?.toDouble() ?? 0.0;
      final margin = totalSales > 0 ? (estProfit / totalSales) * 100.0 : 0.0;

      return GroupSales(
        productGroup: map['product_group'] ?? 'Unknown',
        orderLinesCount: map['order_lines_count'] ?? 0,
        totalQuantity: (map['total_quantity'] as num?)?.toDouble() ?? 0.0,
        totalSalesValue: totalSales,
        estimatedProfit: estProfit,
        profitMarginPct: margin,
      );
    }).toList();
  }

  Future<List<CustomerSales>> getTopCustomers({int? limit, String? startDate, String? endDate, String? productGroup}) async {
    final db = await database;
    List<Map<String, dynamic>> maps;

    if (productGroup != null && productGroup.isNotEmpty) {
      final query = StringBuffer('''
        SELECT
          s.party as party,
          SUM(s.value) as total_sales,
          SUM(s.value * COALESCE(v.profit_pct, 0.0) / 100.0) as total_profit,
          COUNT(DISTINCT s.vch_type || '_' || s.vch_no) as vouchers_count
        FROM sales_items s
        INNER JOIN vouchers v ON s.vch_type = v.vch_type AND s.vch_no = v.vch_no
        LEFT JOIN products p ON s.product_name = p.product_name
        WHERE 1=1
      ''');
      final args = <dynamic>[];
      _applyFilters(query, args, 's', startDate: startDate, endDate: endDate, productGroup: productGroup);
      query.write(' GROUP BY s.party ORDER BY total_sales DESC');
      if (limit != null) {
        query.write(' LIMIT ?');
        args.add(limit);
      }
      maps = await db.rawQuery(query.toString(), args);
    } else {
      final query = StringBuffer('''
        SELECT
          v.party as party,
          SUM(v.value) as total_sales,
          SUM(v.profit) as total_profit,
          COUNT(*) as vouchers_count
        FROM vouchers v
        WHERE 1=1
      ''');
      final args = <dynamic>[];
      _applyFilters(query, args, 'v', startDate: startDate, endDate: endDate);
      query.write(' GROUP BY v.party ORDER BY total_sales DESC');
      if (limit != null) {
        query.write(' LIMIT ?');
        args.add(limit);
      }
      maps = await db.rawQuery(query.toString(), args);
    }

    return maps.map((map) {
      final totalSales = (map['total_sales'] as num?)?.toDouble() ?? 0.0;
      final totalProfit = (map['total_profit'] as num?)?.toDouble() ?? 0.0;
      final count = map['vouchers_count'] ?? 0;
      final avgOrder = count > 0 ? totalSales / count : 0.0;
      final margin = totalSales > 0 ? (totalProfit / totalSales) * 100.0 : 0.0;

      return CustomerSales(
        party: map['party'] ?? 'Unknown',
        totalSales: totalSales,
        totalProfit: totalProfit,
        vouchersCount: count,
        avgOrderValue: avgOrder,
        profitMarginPct: margin,
      );
    }).toList();
  }

  Future<List<CustomerSales>> getTopSellers({int? limit, String? startDate, String? endDate, String? productGroup}) async {
    return getTopCustomers(limit: limit, startDate: startDate, endDate: endDate, productGroup: productGroup);
  }

  Future<List<ProductSales>> getTopProducts({int? limit, String? startDate, String? endDate, String? party, String? productGroup}) async {
    final db = await database;
    final query = StringBuffer('''
      SELECT
        s.product_name as product_name,
        SUM(s.value) as total_sales_value,
        SUM(s.quantity) as total_quantity,
        AVG(s.rate) as average_rate,
        COUNT(*) as transactions_count
      FROM sales_items s
      LEFT JOIN products p ON s.product_name = p.product_name
      WHERE 1=1
    ''');
    final args = <dynamic>[];
    _applyFilters(query, args, 's', startDate: startDate, endDate: endDate, party: party, productGroup: productGroup);
    query.write(' GROUP BY s.product_name ORDER BY total_sales_value DESC');
    if (limit != null) {
      query.write(' LIMIT ?');
      args.add(limit);
    }

    final List<Map<String, dynamic>> maps = await db.rawQuery(query.toString(), args);

    return maps.map((map) {
      return ProductSales(
        productName: map['product_name'] ?? 'Unknown',
        totalSalesValue: (map['total_sales_value'] as num?)?.toDouble() ?? 0.0,
        totalQuantity: (map['total_quantity'] as num?)?.toDouble() ?? 0.0,
        averageRate: (map['average_rate'] as num?)?.toDouble() ?? 0.0,
        transactionsCount: map['transactions_count'] ?? 0,
      );
    }).toList();
  }

  Future<List<ProductSales>> getTopSalesProducts({int? limit, String? startDate, String? endDate, String? party, String? productGroup}) async {
    return getTopProducts(limit: limit, startDate: startDate, endDate: endDate, party: party, productGroup: productGroup);
  }

  Future<List<DailyTrend>> getDailyTrends({String? startDate, String? endDate, String? party, String? productGroup}) async {
    final db = await database;
    List<Map<String, dynamic>> maps;

    if (productGroup != null && productGroup.isNotEmpty) {
      final query = StringBuffer('''
        SELECT
          s.date as date_str,
          SUM(s.value) as daily_sales,
          SUM(s.value * COALESCE(v.profit_pct, 0.0) / 100.0) as daily_profit,
          COUNT(DISTINCT s.vch_type || '_' || s.vch_no) as vouchers_count
        FROM sales_items s
        INNER JOIN vouchers v ON s.vch_type = v.vch_type AND s.vch_no = v.vch_no
        LEFT JOIN products p ON s.product_name = p.product_name
        WHERE 1=1
      ''');
      final args = <dynamic>[];
      _applyFilters(query, args, 's', startDate: startDate, endDate: endDate, party: party, productGroup: productGroup);
      query.write(' GROUP BY date_str ORDER BY date_str ASC');
      maps = await db.rawQuery(query.toString(), args);
    } else {
      final query = StringBuffer('''
        SELECT
          v.date as date_str,
          SUM(v.value) as daily_sales,
          SUM(v.profit) as daily_profit,
          COUNT(*) as vouchers_count
        FROM vouchers v
        WHERE 1=1
      ''');
      final args = <dynamic>[];
      _applyFilters(query, args, 'v', startDate: startDate, endDate: endDate, party: party);
      query.write(' GROUP BY date_str ORDER BY date_str ASC');
      maps = await db.rawQuery(query.toString(), args);
    }

    return maps.map((map) {
      return DailyTrend(
        dateStr: map['date_str'] ?? '',
        dailySales: (map['daily_sales'] as num?)?.toDouble() ?? 0.0,
        dailyProfit: (map['daily_profit'] as num?)?.toDouble() ?? 0.0,
        vouchersCount: map['vouchers_count'] ?? 0,
      );
    }).toList();
  }

  Future<List<PricingConsistency>> getPricingConsistency({int? minSales, String? startDate, String? endDate, String? party, String? productGroup}) async {
    final db = await database;
    final minS = minSales ?? 5;

    // Load items after filters
    final query = StringBuffer('''
      SELECT
        s.product_name,
        s.rate,
        s.vch_no
      FROM sales_items s
      LEFT JOIN products p ON s.product_name = p.product_name
      WHERE LOWER(TRIM(s.product_name)) != 'indian item'
    ''');
    final args = <dynamic>[];
    _applyFilters(query, args, 's', startDate: startDate, endDate: endDate, party: party, productGroup: productGroup);
    
    final List<Map<String, dynamic>> rows = await db.rawQuery(query.toString(), args);
    if (rows.isEmpty) return [];

    // Group in memory
    final Map<String, List<Map<String, dynamic>>> groups = {};
    for (final r in rows) {
      final pName = r['product_name'] as String;
      groups.putIfAbsent(pName, () => []).add(r);
    }

    final List<PricingConsistency> records = [];

    groups.forEach((productName, group) {
      final salesCount = group.length;
      if (salesCount < minS) return;

      final rates = group.map((r) => (r['rate'] as num).toDouble()).toList();
      final minRate = rates.reduce(min);
      final maxRate = rates.reduce(max);

      // Robust average
      // 1. Calculate mode
      final Map<double, int> freq = {};
      for (final r in rates) {
        freq[r] = (freq[r] ?? 0) + 1;
      }
      int maxFreq = 0;
      double modeRate = rates[0];

      // To break ties consistently, we sort keys
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

      // Standard deviation
      double stdRate = 0.0;
      if (salesCount > 1) {
        final meanRate = rates.reduce((a, b) => a + b) / salesCount;
        final variance = rates.map((r) => pow(r - meanRate, 2)).reduce((a, b) => a + b) / (salesCount - 1);
        stdRate = sqrt(variance);
      }

      // Invoice Details
      final minInvoices = group.where((r) => (r['rate'] as num).toDouble() == minRate)
          .map((r) => r['vch_no'].toString())
          .toSet()
          .map((no) => '#$no (@ ${minRate.toStringAsFixed(2)})')
          .join(', ');

      final maxInvoices = group.where((r) => (r['rate'] as num).toDouble() == maxRate)
          .map((r) => r['vch_no'].toString())
          .toSet()
          .map((no) => '#$no (@ ${maxRate.toStringAsFixed(2)})')
          .join(', ');

      final rateSpreadPct = avgRate > 0 ? ((maxRate - minRate) / avgRate) * 100.0 : 0.0;

      records.add(PricingConsistency(
        productName: productName,
        minRate: minRate,
        maxRate: maxRate,
        avgRate: avgRate,
        stdRate: stdRate.isNaN ? 0.0 : stdRate,
        salesCount: salesCount,
        rateSpreadPct: rateSpreadPct,
        minRateInvoices: minInvoices,
        maxRateInvoices: maxInvoices,
      ));
    });

    // Sort descending by spread
    records.sort((a, b) => b.rateSpreadPct.compareTo(a.rateSpreadPct));
    return records;
  }

  Future<List<WeekdaySales>> getWeekdaySales({String? startDate, String? endDate, String? party, String? productGroup}) async {
    final db = await database;
    List<Map<String, dynamic>> maps;

    final weekdayCase = '''
      CASE strftime('%w', date)
        WHEN '0' THEN 'Sunday'
        WHEN '1' THEN 'Monday'
        WHEN '2' THEN 'Tuesday'
        WHEN '3' THEN 'Wednesday'
        WHEN '4' THEN 'Thursday'
        WHEN '5' THEN 'Friday'
        WHEN '6' THEN 'Saturday'
      END as day_of_week
    ''';

    final sortCase = '''
      CASE strftime('%w', date)
        WHEN '0' THEN 7
        ELSE CAST(strftime('%w', date) AS INTEGER)
      END as day_index
    ''';

    if (productGroup != null && productGroup.isNotEmpty) {
      final query = StringBuffer('''
        SELECT
          $weekdayCase,
          SUM(s.value) as total_sales,
          COUNT(DISTINCT s.vch_type || '_' || s.vch_no) as vouchers_count,
          $sortCase
        FROM sales_items s
        LEFT JOIN products p ON s.product_name = p.product_name
        WHERE 1=1
      ''');
      final args = <dynamic>[];
      _applyFilters(query, args, 's', startDate: startDate, endDate: endDate, party: party, productGroup: productGroup);
      query.write(' GROUP BY day_of_week, day_index ORDER BY day_index ASC');
      maps = await db.rawQuery(query.toString(), args);
    } else {
      final query = StringBuffer('''
        SELECT
          $weekdayCase,
          SUM(v.value) as total_sales,
          COUNT(*) as vouchers_count,
          $sortCase
        FROM vouchers v
        WHERE 1=1
      ''');
      final args = <dynamic>[];
      _applyFilters(query, args, 'v', startDate: startDate, endDate: endDate, party: party);
      query.write(' GROUP BY day_of_week, day_index ORDER BY day_index ASC');
      maps = await db.rawQuery(query.toString(), args);
    }

    return maps.map((map) {
      return WeekdaySales(
        dayOfWeek: map['day_of_week'] ?? 'Unknown',
        totalSales: (map['total_sales'] as num?)?.toDouble() ?? 0.0,
        vouchersCount: map['vouchers_count'] ?? 0,
      );
    }).toList();
  }

  Future<ParetoAnalysis> getParetoAnalysis({String? startDate, String? endDate}) async {
    final db = await database;

    // 1. Parties Pareto
    final partyQuery = StringBuffer('''
      SELECT party, SUM(value) as total_sales
      FROM vouchers v
      WHERE party IS NOT NULL AND party != ''
    ''');
    final partyArgs = <dynamic>[];
    _applyFilters(partyQuery, partyArgs, 'v', startDate: startDate, endDate: endDate);
    partyQuery.write(' GROUP BY party ORDER BY total_sales DESC');
    final List<Map<String, dynamic>> partyMaps = await db.rawQuery(partyQuery.toString(), partyArgs);

    // 2. Products Pareto
    final productQuery = StringBuffer('''
      SELECT s.product_name, SUM(s.value) as total_sales
      FROM sales_items s
      WHERE s.product_name IS NOT NULL
    ''');
    final productArgs = <dynamic>[];
    _applyFilters(productQuery, productArgs, 's', startDate: startDate, endDate: endDate);
    productQuery.write(' GROUP BY s.product_name ORDER BY total_sales DESC');
    final List<Map<String, dynamic>> productMaps = await db.rawQuery(productQuery.toString(), productArgs);

    if (partyMaps.isEmpty || productMaps.isEmpty) {
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

    // Party Pareto Calculation
    final totalPartySales = partyMaps.map((m) => (m['total_sales'] as num).toDouble()).reduce((a, b) => a + b);
    double cumulativePartySales = 0.0;
    int parties80 = 0;
    for (final map in partyMaps) {
      cumulativePartySales += (map['total_sales'] as num).toDouble();
      final pct = (cumulativePartySales / totalPartySales) * 100.0;
      if (pct <= 85.0) {
        parties80++;
      } else {
        break;
      }
    }
    final numParties80 = parties80 + 1;
    final pctParties80 = (numParties80 / partyMaps.length) * 100.0;

    // Product Pareto Calculation
    final totalProductSales = productMaps.map((m) => (m['total_sales'] as num).toDouble()).reduce((a, b) => a + b);
    double cumulativeProductSales = 0.0;
    int products80 = 0;
    for (final map in productMaps) {
      cumulativeProductSales += (map['total_sales'] as num).toDouble();
      final pct = (cumulativeProductSales / totalProductSales) * 100.0;
      if (pct <= 85.0) {
        products80++;
      } else {
        break;
      }
    }
    final numProducts80 = products80 + 1;
    final pctProducts80 = (numProducts80 / productMaps.length) * 100.0;

    return ParetoAnalysis(
      totalSales: totalPartySales,
      totalUniqueParties: partyMaps.length,
      partiesGenerating80PercentSales: numParties80,
      percentageOfPartiesGenerating80Percent: double.parse(pctParties80.toStringAsFixed(2)),
      totalUniqueProducts: productMaps.length,
      productsGenerating80PercentSales: numProducts80,
      percentageOfProductsGenerating80Percent: double.parse(pctProducts80.toStringAsFixed(2)),
    );
  }

  Future<List<MitiDailyTrend>> getMitiDailyTrends({String? startDate, String? endDate, String? party, String? productGroup, String? startMiti, String? endMiti}) async {
    final db = await database;
    List<Map<String, dynamic>> maps;

    final sortKeyExpression = "(SUBSTR(v.miti, 7, 4) || '-' || SUBSTR(v.miti, 4, 2) || '-' || SUBSTR(v.miti, 1, 2))";

    if (productGroup != null && productGroup.isNotEmpty) {
      final query = StringBuffer('''
        SELECT
          v.miti as miti,
          $sortKeyExpression as sort_key,
          SUM(s.value) as daily_sales,
          SUM(s.value * COALESCE(v.profit_pct, 0.0) / 100.0) as daily_profit,
          COUNT(DISTINCT s.vch_type || '_' || s.vch_no) as vouchers_count
        FROM sales_items s
        INNER JOIN vouchers v ON s.vch_type = v.vch_type AND s.vch_no = v.vch_no
        LEFT JOIN products p ON s.product_name = p.product_name
        WHERE v.miti IS NOT NULL AND v.miti != '' AND LENGTH(v.miti) = 10
      ''');
      final args = <dynamic>[];
      _applyFilters(query, args, 'v', startDate: startDate, endDate: endDate, party: party, productGroup: productGroup, startMiti: startMiti, endMiti: endMiti);
      query.write(' GROUP BY miti, sort_key ORDER BY sort_key ASC');
      maps = await db.rawQuery(query.toString(), args);
    } else {
      final query = StringBuffer('''
        SELECT
          v.miti as miti,
          $sortKeyExpression as sort_key,
          SUM(v.value) as daily_sales,
          SUM(v.profit) as daily_profit,
          COUNT(*) as vouchers_count
        FROM vouchers v
        WHERE v.miti IS NOT NULL AND v.miti != '' AND LENGTH(v.miti) = 10
      ''');
      final args = <dynamic>[];
      _applyFilters(query, args, 'v', startDate: startDate, endDate: endDate, party: party, startMiti: startMiti, endMiti: endMiti);
      query.write(' GROUP BY miti, sort_key ORDER BY sort_key ASC');
      maps = await db.rawQuery(query.toString(), args);
    }

    return maps.map((map) {
      return MitiDailyTrend(
        miti: map['miti'] ?? '',
        dailySales: (map['daily_sales'] as num?)?.toDouble() ?? 0.0,
        dailyProfit: (map['daily_profit'] as num?)?.toDouble() ?? 0.0,
        vouchersCount: map['vouchers_count'] ?? 0,
      );
    }).toList();
  }

  Future<List<MitiMonthlyTrend>> getMitiMonthlyTrends({String? startDate, String? endDate, String? party, String? productGroup, String? startMiti, String? endMiti}) async {
    final db = await database;
    List<Map<String, dynamic>> maps;

    final nepaliMonths = {
      '01': 'Baishakh',
      '02': 'Jestha',
      '03': 'Ashadh',
      '04': 'Shrawan',
      '05': 'Bhadra',
      '06': 'Ashwin',
      '07': 'Kartik',
      '08': 'Mangsir',
      '09': 'Poush',
      '10': 'Magh',
      '11': 'Falgun',
      '12': 'Chaitra'
    };

    final yearExpr = "SUBSTR(v.miti, 7, 4)";
    final monthExpr = "SUBSTR(v.miti, 4, 2)";

    if (productGroup != null && productGroup.isNotEmpty) {
      final query = StringBuffer('''
        SELECT
          $yearExpr as year,
          $monthExpr as month_code,
          SUM(s.value) as monthly_sales,
          SUM(s.value * COALESCE(v.profit_pct, 0.0) / 100.0) as monthly_profit,
          COUNT(DISTINCT s.vch_type || '_' || s.vch_no) as vouchers_count
        FROM sales_items s
        INNER JOIN vouchers v ON s.vch_type = v.vch_type AND s.vch_no = v.vch_no
        LEFT JOIN products p ON s.product_name = p.product_name
        WHERE v.miti IS NOT NULL AND v.miti != '' AND LENGTH(v.miti) = 10
      ''');
      final args = <dynamic>[];
      _applyFilters(query, args, 'v', startDate: startDate, endDate: endDate, party: party, productGroup: productGroup, startMiti: startMiti, endMiti: endMiti);
      query.write(' GROUP BY year, month_code ORDER BY year ASC, month_code ASC');
      maps = await db.rawQuery(query.toString(), args);
    } else {
      final query = StringBuffer('''
        SELECT
          $yearExpr as year,
          $monthExpr as month_code,
          SUM(v.value) as monthly_sales,
          SUM(v.profit) as monthly_profit,
          COUNT(*) as vouchers_count
        FROM vouchers v
        WHERE v.miti IS NOT NULL AND v.miti != '' AND LENGTH(v.miti) = 10
      ''');
      final args = <dynamic>[];
      _applyFilters(query, args, 'v', startDate: startDate, endDate: endDate, party: party, startMiti: startMiti, endMiti: endMiti);
      query.write(' GROUP BY year, month_code ORDER BY year ASC, month_code ASC');
      maps = await db.rawQuery(query.toString(), args);
    }

    return maps.map((map) {
      final yr = map['year'] ?? '';
      final code = map['month_code'] ?? '';
      final name = nepaliMonths[code] ?? 'Month $code';

      return MitiMonthlyTrend(
        year: yr,
        monthCode: code,
        monthName: name,
        monthlySales: (map['monthly_sales'] as num?)?.toDouble() ?? 0.0,
        monthlyProfit: (map['monthly_profit'] as num?)?.toDouble() ?? 0.0,
        vouchersCount: map['vouchers_count'] ?? 0,
        period: '$name $yr',
      );
    }).toList();
  }

  Future<List<CustomerRetention>> getCustomerRetention({String? startDate, String? endDate}) async {
    final db = await database;
    final query = StringBuffer('''
      SELECT party, date, value
      FROM vouchers v
      WHERE party IS NOT NULL AND party != ''
    ''');
    final args = <dynamic>[];
    _applyFilters(query, args, 'v', startDate: startDate, endDate: endDate);
    query.write(' ORDER BY date ASC');

    final List<Map<String, dynamic>> rows = await db.rawQuery(query.toString(), args);
    if (rows.isEmpty) return [];

    // Group in memory
    final Map<String, List<Map<String, dynamic>>> customerGroups = {};
    for (final r in rows) {
      final pName = r['party'] as String;
      customerGroups.putIfAbsent(pName, () => []).add(r);
    }

    // Find global max date as today
    DateTime? maxDatasetDate;
    for (final r in rows) {
      final dStr = r['date'] as String;
      final dt = DateTime.parse(dStr.split(' ')[0]);
      if (maxDatasetDate == null || dt.isAfter(maxDatasetDate)) {
        maxDatasetDate = dt;
      }
    }

    maxDatasetDate ??= DateTime.now();

    final List<CustomerRetention> retentionList = [];

    customerGroups.forEach((partyName, group) {
      final dates = group.map((r) => DateTime.parse((r['date'] as String).split(' ')[0])).toList()..sort();
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

      final totalOrders = group.length;
      final totalRev = group.map((r) => (r['value'] as num).toDouble()).reduce((a, b) => a + b);
      final avgVal = totalRev / totalOrders;

      retentionList.add(CustomerRetention(
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

    // Sort by revenue descending
    retentionList.sort((a, b) => b.totalRevenue.compareTo(a.totalRevenue));
    return retentionList;
  }

  Future<List<VoucherTypeSales>> getSalesByVoucherType({String? startDate, String? endDate, String? party}) async {
    final db = await database;
    final query = StringBuffer('''
      SELECT
        vch_type as vchType,
        SUM(value) as total_sales,
        SUM(profit) as total_profit,
        COUNT(*) as vouchers_count
      FROM vouchers v
      WHERE 1=1
    ''');
    final args = <dynamic>[];
    _applyFilters(query, args, 'v', startDate: startDate, endDate: endDate, party: party);
    query.write(' GROUP BY vchType ORDER BY total_sales DESC');

    final List<Map<String, dynamic>> maps = await db.rawQuery(query.toString(), args);

    return maps.map((map) {
      final totalSales = (map['total_sales'] as num?)?.toDouble() ?? 0.0;
      final totalProfit = (map['total_profit'] as num?)?.toDouble() ?? 0.0;
      final margin = totalSales > 0 ? (totalProfit / totalSales) * 100.0 : 0.0;

      return VoucherTypeSales(
        vchType: map['vchType'] ?? 'Unknown',
        totalSales: totalSales,
        totalProfit: totalProfit,
        vouchersCount: map['vouchers_count'] ?? 0,
        profitMarginPct: margin,
      );
    }).toList();
  }

  Future<List<HighMarginProduct>> getHighestMarginProducts({int? limit, String? startDate, String? endDate, String? productGroup}) async {
    final db = await database;
    final query = StringBuffer('''
      SELECT
        s.product_name as productName,
        SUM(s.value) as total_sales_value,
        SUM(s.quantity) as total_quantity,
        SUM(s.value * COALESCE(v.profit_pct, 0.0) / 100.0) as total_profit
      FROM sales_items s
      INNER JOIN vouchers v ON s.vch_type = v.vch_type AND s.vch_no = v.vch_no
      LEFT JOIN products p ON s.product_name = p.product_name
      WHERE 1=1
    ''');
    final args = <dynamic>[];
    _applyFilters(query, args, 's', startDate: startDate, endDate: endDate, productGroup: productGroup);
    query.write(' GROUP BY s.product_name');

    final List<Map<String, dynamic>> maps = await db.rawQuery(query.toString(), args);

    final List<HighMarginProduct> list = maps.map((map) {
      final totalSales = (map['total_sales_value'] as num?)?.toDouble() ?? 0.0;
      final profit = (map['total_profit'] as num?)?.toDouble() ?? 0.0;
      final margin = totalSales > 0 ? (profit / totalSales) * 100.0 : 0.0;

      return HighMarginProduct(
        productName: map['productName'] ?? 'Unknown',
        totalSalesValue: totalSales,
        totalQuantity: (map['total_quantity'] as num?)?.toDouble() ?? 0.0,
        totalProfit: profit,
        averageMarginPct: margin,
      );
    }).toList();

    list.sort((a, b) => b.averageMarginPct.compareTo(a.averageMarginPct));
    if (limit != null) {
      return list.take(limit).toList();
    }
    return list;
  }

  Future<List<HighMarginCustomer>> getHighestMarginCustomers({int? limit, String? startDate, String? endDate}) async {
    final db = await database;
    final query = StringBuffer('''
      SELECT
        party,
        SUM(value) as total_sales,
        SUM(profit) as total_profit
      FROM vouchers v
      WHERE party IS NOT NULL AND party != ''
    ''');
    final args = <dynamic>[];
    _applyFilters(query, args, 'v', startDate: startDate, endDate: endDate);
    query.write(' GROUP BY party');

    final List<Map<String, dynamic>> maps = await db.rawQuery(query.toString(), args);

    final List<HighMarginCustomer> list = maps.map((map) {
      final totalSales = (map['total_sales'] as num?)?.toDouble() ?? 0.0;
      final profit = (map['total_profit'] as num?)?.toDouble() ?? 0.0;
      final margin = totalSales > 0 ? (profit / totalSales) * 100.0 : 0.0;

      return HighMarginCustomer(
        party: map['party'] ?? 'Unknown',
        totalSales: totalSales,
        totalProfit: profit,
        profitMarginPct: margin,
      );
    }).toList();

    list.sort((a, b) => b.profitMarginPct.compareTo(a.profitMarginPct));
    if (limit != null) {
      return list.take(limit).toList();
    }
    return list;
  }

  Future<List<ImportForecast>> getImportForecast({int? days}) async {
    final db = await database;
    final durationDays = days ?? 90;

    // First find max date in database
    final maxDateMap = await db.rawQuery('SELECT MAX(date) as max_date FROM sales_items');
    if (maxDateMap.isEmpty || maxDateMap.first['max_date'] == null) {
      return [];
    }

    final maxDateStr = maxDateMap.first['max_date'] as String;
    final maxDate = DateTime.parse(maxDateStr.split(' ')[0]);
    final cutoffDate = maxDate.subtract(Duration(days: durationDays));
    final cutoffStr = cutoffDate.toIso8601String().split('T')[0];

    final query = '''
      SELECT
        s.product_name as productName,
        COALESCE(p.group_name, 'Unmapped') as groupName,
        SUM(s.quantity) as total_quantity,
        SUM(s.value) as total_sales_value,
        COUNT(*) as sales_count
      FROM sales_items s
      LEFT JOIN products p ON s.product_name = p.product_name
      WHERE s.date >= ?
      GROUP BY s.product_name
    ''';

    final List<Map<String, dynamic>> maps = await db.rawQuery(query, [cutoffStr]);

    final List<ImportForecast> list = maps.map((map) {
      final totalQty = (map['total_quantity'] as num?)?.toDouble() ?? 0.0;
      final totalSales = (map['total_sales_value'] as num?)?.toDouble() ?? 0.0;
      final count = map['sales_count'] ?? 0;

      final monthlyRunRate = (totalQty / durationDays) * 30.0;
      final projected3Month = monthlyRunRate * 3.0;
      final suggestedOrder = projected3Month * 1.25;

      return ImportForecast(
        productName: map['productName'] ?? 'Unknown',
        groupName: map['groupName'] ?? 'Unmapped',
        totalQuantity: double.parse(totalQty.toStringAsFixed(1)),
        totalSalesValue: double.parse(totalSales.toStringAsFixed(2)),
        salesCount: count,
        monthlyRunRate: double.parse(monthlyRunRate.toStringAsFixed(1)),
        projected3MonthDemand: double.parse(projected3Month.toStringAsFixed(1)),
        suggestedOrderQty: suggestedOrder.isNaN || suggestedOrder.isInfinite ? 0 : suggestedOrder.round(),
      );
    }).toList();

    list.sort((a, b) => b.suggestedOrderQty.compareTo(a.suggestedOrderQty));
    return list;
  }

  Future<List<MarketBasketPair>> getMarketBasket({String? startDate, String? endDate, String? party, String? productGroup, int? minSupport, int? topN}) async {
    final db = await database;
    final support = minSupport ?? 2;
    final limit = topN ?? 15;

    // Load sales_items
    final query = StringBuffer('''
      SELECT
        s.vch_type || '_' || s.vch_no as vch_key,
        s.product_name
      FROM sales_items s
      LEFT JOIN products p ON s.product_name = p.product_name
      WHERE 1=1
    ''');
    final args = <dynamic>[];
    _applyFilters(query, args, 's', startDate: startDate, endDate: endDate, party: party, productGroup: productGroup);

    final List<Map<String, dynamic>> rows = await db.rawQuery(query.toString(), args);
    if (rows.isEmpty) return [];

    // Group products by voucher key
    final Map<String, Set<String>> basket = {};
    for (final r in rows) {
      final key = r['vch_key'] as String;
      final prod = r['product_name'] as String;
      basket.putIfAbsent(key, () => {}).add(prod);
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
    final db = await database;
    final query = StringBuffer('''
      SELECT
        party,
        SUM(revenue) as total_revenue,
        COUNT(DISTINCT vch_type || '_' || vch_no) as total_orders,
        MIN(date) as first_purchase,
        MAX(date) as last_purchase
      FROM vouchers v
      WHERE party IS NOT NULL AND party != ''
    ''');
    final args = <dynamic>[];
    _applyFilters(query, args, 'v', startDate: startDate, endDate: endDate, party: party);
    query.write(' GROUP BY party HAVING total_revenue > 0 ORDER BY total_revenue DESC');

    final List<Map<String, dynamic>> maps = await db.rawQuery(query.toString(), args);

    return maps.map((map) {
      final totalRev = (map['total_revenue'] as num?)?.toDouble() ?? 0.0;
      final totalOrders = map['total_orders'] ?? 0;
      final firstStr = map['first_purchase'] as String;
      final lastStr = map['last_purchase'] as String;

      final firstDate = DateTime.parse(firstStr.split(' ')[0]);
      final lastDate = DateTime.parse(lastStr.split(' ')[0]);

      int lifespan = lastDate.difference(firstDate).inDays;
      if (lifespan <= 0) lifespan = 1;

      final avgOrder = totalRev / totalOrders;
      final freq = (totalOrders / lifespan) * 365.0;
      final clv = avgOrder * freq;

      return CustomerCLV(
        party: map['party'] ?? '',
        totalRevenue: double.parse(totalRev.toStringAsFixed(2)),
        totalOrders: totalOrders,
        averageOrderValue: double.parse(avgOrder.toStringAsFixed(2)),
        lifespanDays: lifespan,
        purchaseFrequencyAnnual: double.parse(freq.toStringAsFixed(1)),
        estimatedAnnualClv: double.parse(clv.toStringAsFixed(2)),
        firstPurchase: firstStr.split(' ')[0],
        lastPurchase: lastStr.split(' ')[0],
      );
    }).toList();
  }

  Future<List<SlowMovingProduct>> getSlowMovingStock({String? startDate, String? endDate, String? party, String? productGroup, int? thresholdDays}) async {
    final db = await database;
    final threshold = thresholdDays ?? 60;

    final query = StringBuffer('''
      SELECT
        s.product_name as productName,
        COALESCE(p.group_name, 'Unmapped') as groupName,
        MAX(s.date) as lastSaleDate,
        SUM(s.quantity) as totalQuantity,
        SUM(s.value) as totalRevenue
      FROM sales_items s
      LEFT JOIN products p ON s.product_name = p.product_name
      WHERE 1=1
    ''');
    final args = <dynamic>[];
    _applyFilters(query, args, 's', startDate: startDate, endDate: endDate, party: party, productGroup: productGroup);
    query.write(' GROUP BY s.product_name');

    final List<Map<String, dynamic>> maps = await db.rawQuery(query.toString(), args);
    if (maps.isEmpty) return [];

    // Find global max date as today
    DateTime? maxDate;
    for (final map in maps) {
      final dStr = map['lastSaleDate'] as String;
      final dt = DateTime.parse(dStr.split(' ')[0]);
      if (maxDate == null || dt.isAfter(maxDate)) {
        maxDate = dt;
      }
    }
    maxDate ??= DateTime.now();

    final List<SlowMovingProduct> list = [];

    for (final map in maps) {
      final lastSaleStr = map['lastSaleDate'] as String;
      final lastSale = DateTime.parse(lastSaleStr.split(' ')[0]);
      final diffDays = maxDate.difference(lastSale).inDays;

      if (diffDays >= threshold) {
        list.add(SlowMovingProduct(
          productName: map['productName'] ?? '',
          groupName: map['groupName'] ?? 'Unmapped',
          lastSaleDate: lastSaleStr.split(' ')[0],
          daysSinceLastSale: diffDays,
          totalQuantity: ((map['totalQuantity'] as num?)?.toDouble() ?? 0.0),
          totalRevenue: ((map['totalRevenue'] as num?)?.toDouble() ?? 0.0),
        ));
      }
    }

    list.sort((a, b) => b.daysSinceLastSale.compareTo(a.daysSinceLastSale));
    return list;
  }

  Future<List<SalesForecast>> getSalesForecast({String? startDate, String? endDate, String? party, int? forecastDays}) async {
    final db = await database;
    final days = forecastDays ?? 30;

    final query = StringBuffer('''
      SELECT date, SUM(revenue) as revenue
      FROM vouchers v
      WHERE 1=1
    ''');
    final args = <dynamic>[];
    _applyFilters(query, args, 'v', startDate: startDate, endDate: endDate, party: party);
    query.write(' GROUP BY date ORDER BY date ASC');

    final List<Map<String, dynamic>> maps = await db.rawQuery(query.toString(), args);
    if (maps.isEmpty) return [];

    final List<Map<String, dynamic>> dailyList = maps.map((m) {
      return {
        'date': DateTime.parse((m['date'] as String).split(' ')[0]),
        'revenue': (m['revenue'] as num).toDouble(),
      };
    }).toList();

    final minDate = dailyList.first['date'] as DateTime;
    final maxDate = dailyList.last['date'] as DateTime;

    final int totalDays = maxDate.difference(minDate).inDays + 1;
    final List<double> continuousRev = List.filled(totalDays, 0.0);

    for (final d in dailyList) {
      final index = (d['date'] as DateTime).difference(minDate).inDays;
      continuousRev[index] = d['revenue'] as double;
    }

    // Calculate rolling 7-day average
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

    // Historical data: last 30 days
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

    // Forecast data
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

  // --- UNGROUPED PRODUCTS ---

  Future<List<String>> getUngroupedProducts() async {
    final db = await database;
    final maps = await db.rawQuery('''
      SELECT DISTINCT TRIM(product_name) as product_name
      FROM sales_items
      WHERE TRIM(product_name) NOT IN (SELECT DISTINCT TRIM(product_name) FROM products)
      ORDER BY product_name ASC
    ''');
    return maps.map((m) => m['product_name'].toString()).toList();
  }

  Future<void> assignGroup(String productName, String groupName) async {
    final db = await database;
    await db.insert(
      'products',
      {
        'product_name': productName.trim(),
        'group_name': groupName.trim(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }
}
