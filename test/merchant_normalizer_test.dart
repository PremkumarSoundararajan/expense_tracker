import 'package:flutter_test/flutter_test.dart';
import 'package:pocket_ledger/services/merchant_normalizer.dart';

void main() {
  group('normalizeMerchant', () {
    test('removes payment boilerplate and reference identifiers', () {
      expect(
        normalizeMerchant(
          'ATMOS ENERGY RCR UTIL PYMT 003068 WEB ID: 900',
        ),
        'ATMOS ENERGY',
      );
    });

    test('removes dates, check numbers, ACH identifiers and location codes', () {
      expect(
        normalizeMerchant(
          '2025-03-04 CHECK #4812 HEB #104 ACH ID: TX9028 DALLAS TX',
        ),
        'HEB DALLAS TX',
      );
    });

    test('normalizes punctuation and whitespace into a stable fingerprint', () {
      expect(
        normalizeMerchant('  Netflix.Com   Recurring   Payment  '),
        'NETFLIX COM',
      );
      expect(
        normalizeMerchant('Netflix.Com Recurring Payment'),
        normalizeMerchant(' netflix.com   recurring payment '),
      );
    });

    test('returns an empty fingerprint when the description is only noise', () {
      expect(normalizeMerchant('WEB ID: 900 05/20/2025 PYMT'), isEmpty);
    });
  });
}
