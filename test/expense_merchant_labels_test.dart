import 'package:flutter_test/flutter_test.dart';
import 'package:pocket_ledger/services/favourite_spending_spots_service.dart';

void main() {
  test('statement labels reuse cleanup without changing raw descriptions', () {
    final descriptions = [
      'POS DEBIT       BACON PLUMBING #123 11/13/2026',
      'ATM DEBIT 400 COLONIAL ST FORT WORTH TX',
      'ATMOS ENERGY RCR UTIL PYMT 003068 WEB ID: 900',
      'ATT        PAYMENT       PPD ID: 900',
      'WINCO FOODS #137 8968 FORT WORTH TX',
      'RHYTHM OPS LLC PURCHASE 389202',
      'OTHER SHOP #9 FORT WORTH TX',
      'buying iPhone',
      'Recorded expense 2',
      'Dinner for 4 friends',
      'தமிழ் கடை',
      '',
    ];
    final before = List<String>.of(descriptions);
    final labels = ExpenseMerchantLabels(descriptions);
    expect(labels.label(descriptions[0]), 'Bacon Plumbing');
    expect(labels.label(descriptions[1]), 'ATM withdrawal');
    expect(labels.label(descriptions[2]), 'Atmos Energy');
    expect(labels.label(descriptions[3]), 'ATT');
    expect(labels.label(descriptions[4]), 'Winco Foods');
    expect(labels.label(descriptions[5]), 'Rhythm OPS LLC');
    expect(labels.label('buying iPhone'), 'buying iPhone');
    expect(labels.label('Recorded expense 2'), 'Recorded expense 2');
    expect(labels.label('Dinner for 4 friends'), 'Dinner for 4 friends');
    expect(labels.label('தமிழ் கடை'), 'தமிழ் கடை');
    expect(labels.label('', fallback: 'Groceries'), 'Groceries');
    expect(descriptions, before);
  });
  test('empty cleanup and unknown labels keep a readable fallback', () {
    final labels = ExpenseMerchantLabels([
      'POS DEBIT 12345',
      '  custom    note  ',
    ]);
    expect(labels.label('POS DEBIT 12345'), 'POS DEBIT 12345');
    expect(labels.label('  custom    note  '), 'custom note');
    expect(labels.label('not indexed'), 'not indexed');
  });
}
