import 'package:flutter_test/flutter_test.dart';
import 'package:pocket_ledger/utils/currency_format.dart';

void main() {
  group('formatCompactCurrency', () {
    test('abbreviates large values to thousands', () {
      expect(formatCompactCurrency(15000, '\$'), '\$15k');
      expect(formatCompactCurrency(15500, '\$'), '\$15.5k');
    });

    test('groups thousands and omits decimals for whole amounts', () {
      expect(formatCompactCurrency(1133, '\$'), '\$1,133');
      expect(formatCompactCurrency(468, '\$'), '\$468');
      expect(formatCompactCurrency(1133.5, '\$'), '\$1,133.5');
    });

    test('preserves the configured currency symbol', () {
      expect(formatCompactCurrency(1500, 'RM'), 'RM1,500');
    });

    test('uses Indian grouping without k abbreviations for rupees', () {
      expect(formatCompactCurrency(15000, '₹'), '₹15,000');
      expect(formatCompactCurrency(1234567.5, '₹'), '₹12,34,567.5');
    });
  });

  group('formatFullCurrency', () {
    test('keeps main-card values complete and grouped', () {
      expect(formatFullCurrency(10468, '\$'), '\$10,468');
      expect(formatFullCurrency(10468.25, '\$'), '\$10,468.25');
    });

    test('uses Indian comma grouping for rupees', () {
      expect(formatFullCurrency(1234567.5, '₹'), '₹12,34,567.5');
    });
  });
}
