import 'package:intl/intl.dart';

final _currency = NumberFormat.currency(locale: 'en_PH', symbol: '₱', decimalDigits: 2);

/// Formats a peso amount with thousands separators (e.g. ₱1,500.00) instead
/// of a raw toStringAsFixed(2), which drops the separator on larger totals.
String formatPeso(num amount) => _currency.format(amount);
