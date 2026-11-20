import 'dart:ui';

import 'package:shared_preferences/shared_preferences.dart';

class CurrencyOption {
  const CurrencyOption(this.code, this.symbol);

  final String code;
  final String symbol;
}

const currencyOptions = [
  CurrencyOption('USD', r'$'),
  CurrencyOption('INR', '₹'),
  CurrencyOption('MYR', 'RM'),
  CurrencyOption('CAD', r'$'),
  CurrencyOption('GBP', '£'),
  CurrencyOption('SGD', r'$'),
  CurrencyOption('AUD', r'$'),
  CurrencyOption('EUR', '€'),
];

CurrencyOption currencyForLocale(Locale locale) {
  const codes = {
    'US': 'USD',
    'IN': 'INR',
    'MY': 'MYR',
    'CA': 'CAD',
    'GB': 'GBP',
    'SG': 'SGD',
    'AU': 'AUD',
  };
  return currencyForCode(codes[locale.countryCode?.toUpperCase()] ?? 'USD')!;
}

CurrencyOption? currencyForCode(String? code) {
  for (final currency in currencyOptions) {
    if (currency.code == code) return currency;
  }
  return null;
}

CurrencyOption? currencyForLegacySymbol(String? symbol) {
  for (final currency in currencyOptions) {
    if (currency.symbol == symbol) return currency;
  }
  return null;
}

Future<CurrencyOption> loadCurrencyPreference(
  SharedPreferences preferences,
  Locale locale,
) async {
  final code = preferences.getString('currency_code');
  if (code != null) {
    final currency = currencyForCode(code);
    if (currency == null) throw StateError('Unknown saved currency: $code');
    return currency;
  }
  final symbol = preferences.getString('currency_symbol');
  final currency = symbol == null
      ? currencyForLocale(locale)
      : currencyForLegacySymbol(symbol);
  if (currency == null) throw StateError('Unknown saved currency: $symbol');
  if (!await preferences.setString('currency_code', currency.code)) {
    throw StateError('Could not save currency preference.');
  }
  return currency;
}
