class GroupSales {
  final String productGroup;
  final int orderLinesCount;
  final double totalQuantity;
  final double totalSalesValue;
  final double estimatedProfit;
  final double profitMarginPct;

  GroupSales({
    required this.productGroup,
    required this.orderLinesCount,
    required this.totalQuantity,
    required this.totalSalesValue,
    required this.estimatedProfit,
    required this.profitMarginPct,
  });

  factory GroupSales.fromJson(Map<String, dynamic> json) {
    return GroupSales(
      productGroup: json['product_group'] ?? 'Unknown',
      orderLinesCount: json['order_lines_count'] ?? 0,
      totalQuantity: (json['total_quantity'] as num?)?.toDouble() ?? 0.0,
      totalSalesValue: (json['total_sales_value'] as num?)?.toDouble() ?? 0.0,
      estimatedProfit: (json['estimated_profit'] as num?)?.toDouble() ?? 0.0,
      profitMarginPct: (json['profit_margin_pct'] as num?)?.toDouble() ?? 0.0,
    );
  }
}

class CustomerSales {
  final String party;
  final double totalSales;
  final double totalProfit;
  final int vouchersCount;
  final double avgOrderValue;
  final double profitMarginPct;

  CustomerSales({
    required this.party,
    required this.totalSales,
    required this.totalProfit,
    required this.vouchersCount,
    required this.avgOrderValue,
    required this.profitMarginPct,
  });

  factory CustomerSales.fromJson(Map<String, dynamic> json) {
    return CustomerSales(
      party: json['party'] ?? 'Unknown',
      totalSales: (json['total_sales'] as num?)?.toDouble() ?? 0.0,
      totalProfit: (json['total_profit'] as num?)?.toDouble() ?? 0.0,
      vouchersCount: json['vouchers_count'] ?? 0,
      avgOrderValue: (json['avg_order_value'] as num?)?.toDouble() ?? 0.0,
      profitMarginPct: (json['profit_margin_pct'] as num?)?.toDouble() ?? 0.0,
    );
  }
}

class ProductSales {
  final String productName;
  final double totalSalesValue;
  final double totalQuantity;
  final double averageRate;
  final int transactionsCount;

  ProductSales({
    required this.productName,
    required this.totalSalesValue,
    required this.totalQuantity,
    required this.averageRate,
    required this.transactionsCount,
  });

  factory ProductSales.fromJson(Map<String, dynamic> json) {
    return ProductSales(
      productName: json['product_name'] ?? 'Unknown',
      totalSalesValue: (json['total_sales_value'] as num?)?.toDouble() ?? 0.0,
      totalQuantity: (json['total_quantity'] as num?)?.toDouble() ?? 0.0,
      averageRate: (json['average_rate'] as num?)?.toDouble() ?? 0.0,
      transactionsCount: json['transactions_count'] ?? 0,
    );
  }
}

class DailyTrend {
  final String dateStr;
  final double dailySales;
  final double dailyProfit;
  final int vouchersCount;

  DailyTrend({
    required this.dateStr,
    required this.dailySales,
    required this.dailyProfit,
    required this.vouchersCount,
  });

  factory DailyTrend.fromJson(Map<String, dynamic> json) {
    return DailyTrend(
      dateStr: json['date_str'] ?? '',
      dailySales: (json['daily_sales'] as num?)?.toDouble() ?? 0.0,
      dailyProfit: (json['daily_profit'] as num?)?.toDouble() ?? 0.0,
      vouchersCount: json['vouchers_count'] ?? 0,
    );
  }
}

class PricingConsistency {
  final String productName;
  final double minRate;
  final double maxRate;
  final double avgRate;
  final double stdRate;
  final int salesCount;
  final double rateSpreadPct;
  final String minRateInvoices;
  final String maxRateInvoices;

  PricingConsistency({
    required this.productName,
    required this.minRate,
    required this.maxRate,
    required this.avgRate,
    required this.stdRate,
    required this.salesCount,
    required this.rateSpreadPct,
    required this.minRateInvoices,
    required this.maxRateInvoices,
  });

  factory PricingConsistency.fromJson(Map<String, dynamic> json) {
    return PricingConsistency(
      productName: json['product_name'] ?? 'Unknown',
      minRate: (json['min_rate'] as num?)?.toDouble() ?? 0.0,
      maxRate: (json['max_rate'] as num?)?.toDouble() ?? 0.0,
      avgRate: (json['avg_rate'] as num?)?.toDouble() ?? 0.0,
      stdRate: (json['std_rate'] as num?)?.toDouble() ?? 0.0,
      salesCount: json['sales_count'] ?? 0,
      rateSpreadPct: (json['rate_spread_pct'] as num?)?.toDouble() ?? 0.0,
      minRateInvoices: json['min_rate_invoices'] ?? '',
      maxRateInvoices: json['max_rate_invoices'] ?? '',
    );
  }
}

class WeekdaySales {
  final String dayOfWeek;
  final double totalSales;
  final int vouchersCount;

  WeekdaySales({
    required this.dayOfWeek,
    required this.totalSales,
    required this.vouchersCount,
  });

  factory WeekdaySales.fromJson(Map<String, dynamic> json) {
    return WeekdaySales(
      dayOfWeek: json['day_of_week'] ?? 'Unknown',
      totalSales: (json['total_sales'] as num?)?.toDouble() ?? 0.0,
      vouchersCount: json['vouchers_count'] ?? 0,
    );
  }
}

class ParetoAnalysis {
  final double totalSales;
  final int totalUniqueParties;
  final int partiesGenerating80PercentSales;
  final double percentageOfPartiesGenerating80Percent;
  final int totalUniqueProducts;
  final int productsGenerating80PercentSales;
  final double percentageOfProductsGenerating80Percent;

  ParetoAnalysis({
    required this.totalSales,
    required this.totalUniqueParties,
    required this.partiesGenerating80PercentSales,
    required this.percentageOfPartiesGenerating80Percent,
    required this.totalUniqueProducts,
    required this.productsGenerating80PercentSales,
    required this.percentageOfProductsGenerating80Percent,
  });

  factory ParetoAnalysis.fromJson(Map<String, dynamic> json) {
    return ParetoAnalysis(
      totalSales: (json['total_sales'] as num?)?.toDouble() ?? 0.0,
      totalUniqueParties: json['total_unique_parties'] ?? 0,
      partiesGenerating80PercentSales: json['parties_generating_80_percent_sales'] ?? 0,
      percentageOfPartiesGenerating80Percent: (json['percentage_of_parties_generating_80_percent'] as num?)?.toDouble() ?? 0.0,
      totalUniqueProducts: json['total_unique_products'] ?? 0,
      productsGenerating80PercentSales: json['products_generating_80_percent_sales'] ?? 0,
      percentageOfProductsGenerating80Percent: (json['percentage_of_products_generating_80_percent'] as num?)?.toDouble() ?? 0.0,
    );
  }
}

class MitiDailyTrend {
  final String miti;
  final double dailySales;
  final double dailyProfit;
  final int vouchersCount;

  MitiDailyTrend({
    required this.miti,
    required this.dailySales,
    required this.dailyProfit,
    required this.vouchersCount,
  });

  factory MitiDailyTrend.fromJson(Map<String, dynamic> json) {
    return MitiDailyTrend(
      miti: json['miti'] ?? '',
      dailySales: (json['daily_sales'] as num?)?.toDouble() ?? 0.0,
      dailyProfit: (json['daily_profit'] as num?)?.toDouble() ?? 0.0,
      vouchersCount: json['vouchers_count'] ?? 0,
    );
  }
}

class MitiMonthlyTrend {
  final String year;
  final String monthCode;
  final String monthName;
  final double monthlySales;
  final double monthlyProfit;
  final int vouchersCount;
  final String period;

  MitiMonthlyTrend({
    required this.year,
    required this.monthCode,
    required this.monthName,
    required this.monthlySales,
    required this.monthlyProfit,
    required this.vouchersCount,
    required this.period,
  });

  factory MitiMonthlyTrend.fromJson(Map<String, dynamic> json) {
    return MitiMonthlyTrend(
      year: json['year'] ?? '',
      monthCode: json['month_code'] ?? '',
      monthName: json['month_name'] ?? '',
      monthlySales: (json['monthly_sales'] as num?)?.toDouble() ?? 0.0,
      monthlyProfit: (json['monthly_profit'] as num?)?.toDouble() ?? 0.0,
      vouchersCount: json['vouchers_count'] ?? 0,
      period: json['period'] ?? '',
    );
  }
}

class CustomerRetention {
  final String party;
  final String firstOrderDate;
  final String lastOrderDate;
  final int totalOrders;
  final double totalRevenue;
  final double avgOrderValue;
  final double avgOrderIntervalDays;
  final int inactiveDays;
  final String status;

  CustomerRetention({
    required this.party,
    required this.firstOrderDate,
    required this.lastOrderDate,
    required this.totalOrders,
    required this.totalRevenue,
    required this.avgOrderValue,
    required this.avgOrderIntervalDays,
    required this.inactiveDays,
    required this.status,
  });

  factory CustomerRetention.fromJson(Map<String, dynamic> json) {
    return CustomerRetention(
      party: json['party'] ?? 'Unknown',
      firstOrderDate: json['first_order_date'] ?? '',
      lastOrderDate: json['last_order_date'] ?? '',
      totalOrders: json['total_orders'] ?? 0,
      totalRevenue: (json['total_revenue'] as num?)?.toDouble() ?? 0.0,
      avgOrderValue: (json['avg_order_value'] as num?)?.toDouble() ?? 0.0,
      avgOrderIntervalDays: (json['avg_order_interval_days'] as num?)?.toDouble() ?? 0.0,
      inactiveDays: json['inactive_days'] ?? 0,
      status: json['status'] ?? 'Inactive',
    );
  }
}

class VoucherTypeSales {
  final String vchType;
  final double totalSales;
  final double totalProfit;
  final int vouchersCount;
  final double profitMarginPct;

  VoucherTypeSales({
    required this.vchType,
    required this.totalSales,
    required this.totalProfit,
    required this.vouchersCount,
    required this.profitMarginPct,
  });

  factory VoucherTypeSales.fromJson(Map<String, dynamic> json) {
    return VoucherTypeSales(
      vchType: json['vch_type'] ?? 'Unknown',
      totalSales: (json['total_sales'] as num?)?.toDouble() ?? 0.0,
      totalProfit: (json['total_profit'] as num?)?.toDouble() ?? 0.0,
      vouchersCount: json['vouchers_count'] ?? 0,
      profitMarginPct: (json['profit_margin_pct'] as num?)?.toDouble() ?? 0.0,
    );
  }
}

class HighMarginProduct {
  final String productName;
  final double totalSalesValue;
  final double totalQuantity;
  final double totalProfit;
  final double averageMarginPct;

  HighMarginProduct({
    required this.productName,
    required this.totalSalesValue,
    required this.totalQuantity,
    required this.totalProfit,
    required this.averageMarginPct,
  });

  factory HighMarginProduct.fromJson(Map<String, dynamic> json) {
    return HighMarginProduct(
      productName: json['product_name'] ?? 'Unknown',
      totalSalesValue: (json['total_sales_value'] as num?)?.toDouble() ?? 0.0,
      totalQuantity: (json['total_quantity'] as num?)?.toDouble() ?? 0.0,
      totalProfit: (json['total_profit'] as num?)?.toDouble() ?? 0.0,
      averageMarginPct: (json['average_margin_pct'] as num?)?.toDouble() ?? 0.0,
    );
  }
}

class HighMarginCustomer {
  final String party;
  final double totalSales;
  final double totalProfit;
  final double profitMarginPct;

  HighMarginCustomer({
    required this.party,
    required this.totalSales,
    required this.totalProfit,
    required this.profitMarginPct,
  });

  factory HighMarginCustomer.fromJson(Map<String, dynamic> json) {
    return HighMarginCustomer(
      party: json['party'] ?? 'Unknown',
      totalSales: (json['total_sales'] as num?)?.toDouble() ?? 0.0,
      totalProfit: (json['total_profit'] as num?)?.toDouble() ?? 0.0,
      profitMarginPct: (json['profit_margin_pct'] as num?)?.toDouble() ?? 0.0,
    );
  }
}

class ImportForecast {
  final String productName;
  final String groupName;
  final double totalQuantity;
  final double totalSalesValue;
  final int salesCount;
  final double monthlyRunRate;
  final double projected3MonthDemand;
  final int suggestedOrderQty;

  ImportForecast({
    required this.productName,
    required this.groupName,
    required this.totalQuantity,
    required this.totalSalesValue,
    required this.salesCount,
    required this.monthlyRunRate,
    required this.projected3MonthDemand,
    required this.suggestedOrderQty,
  });

  factory ImportForecast.fromJson(Map<String, dynamic> json) {
    return ImportForecast(
      productName: json['product_name'] ?? 'Unknown',
      groupName: json['group_name'] ?? 'Unmapped',
      totalQuantity: (json['total_quantity'] as num?)?.toDouble() ?? 0.0,
      totalSalesValue: (json['total_sales_value'] as num?)?.toDouble() ?? 0.0,
      salesCount: json['sales_count'] ?? 0,
      monthlyRunRate: (json['monthly_run_rate'] as num?)?.toDouble() ?? 0.0,
      projected3MonthDemand: (json['projected_3month_demand'] as num?)?.toDouble() ?? 0.0,
      suggestedOrderQty: json['suggested_order_qty'] ?? 0,
    );
  }
}
