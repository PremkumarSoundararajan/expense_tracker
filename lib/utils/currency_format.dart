String formatCompactCurrency(double amount, String currencySymbol) {
  final absoluteAmount = amount.abs();
  final isIndianCurrency = currencySymbol == '₹';
  if (!isIndianCurrency && absoluteAmount >= 10000) {
    final thousands = absoluteAmount / 1000;
    final formattedThousands = _trimDecimalZeros(thousands.toStringAsFixed(1));
    final sign = amount < 0 ? '-' : '';
    return '$sign$currencySymbol${formattedThousands}k';
  }

  final formattedAmount = _trimDecimalZeros(amount.toStringAsFixed(2));
  return '$currencySymbol${_addThousandsSeparators(formattedAmount, isIndianCurrency: isIndianCurrency)}';
}

String formatFullCurrency(double amount, String currencySymbol) {
  final formattedAmount = _trimDecimalZeros(amount.toStringAsFixed(2));
  return '$currencySymbol${_addThousandsSeparators(formattedAmount, isIndianCurrency: currencySymbol == '₹')}';
}

/// Like [formatFullCurrency] but rounded to whole units (no cents), for
/// figures that are read and added up by hand.
String formatWholeCurrency(double? amount, String currencySymbol) {
  if (amount == null || !amount.isFinite) return '${currencySymbol}0';
  final rounded = amount.round();
  return '$currencySymbol${_addThousandsSeparators(rounded.toString(), isIndianCurrency: currencySymbol == '₹')}';
}

String _trimDecimalZeros(String amount) {
  if (!amount.contains('.')) return amount;
  return amount.replaceFirst(RegExp(r'\.?0+$'), '');
}

String _addThousandsSeparators(
  String amount, {
  required bool isIndianCurrency,
}) {
  final decimalIndex = amount.indexOf('.');
  final integerPart = decimalIndex == -1
      ? amount
      : amount.substring(0, decimalIndex);
  final decimalPart = decimalIndex == -1 ? '' : amount.substring(decimalIndex);
  final sign = integerPart.startsWith('-') ? '-' : '';
  final digits = sign.isEmpty ? integerPart : integerPart.substring(1);
  final groupedDigits = isIndianCurrency
      ? _addIndianSeparators(digits)
      : digits.replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => ',');
  return '$sign$groupedDigits$decimalPart';
}

String _addIndianSeparators(String digits) {
  if (digits.length <= 3) return digits;
  final lastThreeDigits = digits.substring(digits.length - 3);
  final precedingDigits = digits.substring(0, digits.length - 3);
  final groupedPrecedingDigits = precedingDigits.replaceAllMapped(
    RegExp(r'\B(?=(\d{2})+(?!\d))'),
    (_) => ',',
  );
  return '$groupedPrecedingDigits,$lastThreeDigits';
}
