import 'package:intl/intl.dart';

class AppFormatters {
  static final NumberFormat _da = NumberFormat.currency(
    locale: 'fr_DZ',
    symbol: 'DA',
    decimalDigits: 2,
  );

  static String price(double value) => _da.format(value);
}
