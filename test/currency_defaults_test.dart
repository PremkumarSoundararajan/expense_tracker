import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:pocket_ledger/utils/currency_defaults.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('maps device countries and falls back to USD', () {
    for (final entry in {
      'US': 'USD',
      'IN': 'INR',
      'MY': 'MYR',
      'CA': 'CAD',
      'GB': 'GBP',
      'SG': 'SGD',
      'AU': 'AUD',
      'ZZ': 'USD',
    }.entries) {
      expect(currencyForLocale(Locale('en', entry.key)).code, entry.value);
    }
    expect(currencyForLocale(const Locale('en')).code, 'USD');
  });

  test(
    'stores the first detected currency and keeps later manual choices',
    () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      expect(
        (await loadCurrencyPreference(prefs, const Locale('en', 'IN'))).code,
        'INR',
      );
      expect(
        (await loadCurrencyPreference(prefs, const Locale('en', 'US'))).code,
        'INR',
      );
      await prefs.setString('currency_code', 'CAD');
      expect(
        (await loadCurrencyPreference(prefs, const Locale('en', 'MY'))).code,
        'CAD',
      );
    },
  );

  test(
    'retains existing symbol preferences instead of the locale default',
    () async {
      SharedPreferences.setMockInitialValues({'currency_symbol': '₹'});
      final prefs = await SharedPreferences.getInstance();
      expect(
        (await loadCurrencyPreference(prefs, const Locale('en', 'US'))).code,
        'INR',
      );
      expect(prefs.getString('currency_code'), 'INR');
    },
  );
}
