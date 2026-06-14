import 'package:intl/intl.dart';

class Formatters {
  static String formatNepaliCurrency(double amount) {
    bool isNegative = amount < 0;
    amount = amount.abs();
    
    String formatted;
    if (amount >= 10000000) { // Crore
      formatted = 'Rs ${(amount / 10000000).toStringAsFixed(2)} Cr';
    } else if (amount >= 100000) { // Lakh
      formatted = 'Rs ${(amount / 100000).toStringAsFixed(2)} L';
    } else {
      formatted = 'Rs ${NumberFormat("#,##0").format(amount)}';
    }
    
    return isNegative ? '-$formatted' : formatted;
  }
}
