// lib/core/utils/currency.dart
// Single source of truth for money formatting across the app. The company
// operates in Egyptian Pounds (EGP); all finance, analytics, reports, PDF
// exports, dashboard revenue totals and calendar costs render through here.

class Money {
  Money._();

  /// ISO code shown as the currency label app-wide.
  static const String code = 'EGP';

  /// Full amount with 2 decimals, e.g. `1,250.00 EGP`.
  static String egp(num value, {int decimals = 2}) =>
      '${_grouped(value, decimals)} $code';

  /// Compact amount for tight UI (hero cards, chart labels), e.g. `1.3k EGP`.
  static String egpCompact(num value) => '${compact(value)} $code';

  /// Compact number without the currency label (e.g. chart bar labels).
  static String compact(num value) {
    final v = value.toDouble();
    final sign = v < 0 ? '-' : '';
    final a = v.abs();
    if (a >= 1000000) return '$sign${(a / 1000000).toStringAsFixed(1)}M';
    if (a >= 1000) return '$sign${(a / 1000).toStringAsFixed(1)}k';
    return '$sign${a.toStringAsFixed(0)}';
  }

  static String _grouped(num value, int decimals) {
    final neg = value < 0;
    final fixed = value.abs().toStringAsFixed(decimals);
    final parts = fixed.split('.');
    final intPart = parts[0];
    final buf = StringBuffer();
    for (int i = 0; i < intPart.length; i++) {
      if (i > 0 && (intPart.length - i) % 3 == 0) buf.write(',');
      buf.write(intPart[i]);
    }
    final grouped = parts.length > 1 ? '$buf.${parts[1]}' : buf.toString();
    return neg ? '-$grouped' : grouped;
  }
}
