import 'package:flutter_test/flutter_test.dart';
import 'package:pocket_ledger/models/transaction.dart';
import 'package:pocket_ledger/services/transaction_filter.dart';

void main() {
  group('internal transfer detection', () {
    test('detects brokerage moneyline descriptions', () {
      expect(isInternalTransfer('FID BKG SVC LLC DES:MONEYLINE'), isTrue);
      expect(isInternalTransfer('Fidelity A2A Xfers'), isTrue);
    });

    test('detects all configured transfer signals case-insensitively', () {
      for (final description in [
        'A2A',
        'TRANSFER TO SAVINGS',
        'XFER TO BROKERAGE',
        'WIRE PAYMENT',
        'ACH CREDIT',
        'CONTRIBUTION',
        'DISTRIBUTION',
      ]) {
        expect(isInternalTransfer(description), isTrue, reason: description);
      }
    });

    test(
      'institution names and mortgage merchants alone are not transfers',
      () {
        expect(isInternalTransfer('DIGITAL FEDERAL CREDIT UNION'), isFalse);
        expect(isInternalTransfer('PENNYMAC LOAN'), isFalse);
        expect(
          isInternalTransfer(
            'DIGITAL FEDERAL CREDIT UNION CUSTOMER',
            context: const UserTransferContext(ownNames: ['CUSTOMER']),
          ),
          isTrue,
        );
      },
    );
    test('explicit spending categories are preserved even with transfer-like descriptions', () {
      final expense = Transaction(
        date: DateTime(2026, 1, 1),
        amount: 25,
        category: 'Financial Obligations',
        description: 'FID BKG SVC LLC DES:MONEYLINE',
      );
      expect(tagInternalTransfer(expense).category, 'Financial Obligations');
      expect(isTransferTransaction(expense), isFalse);
    });
    test('does not classify unrelated descriptions by partial word match', () {
      expect(isInternalTransfer('Wireless headphones'), isFalse);
      expect(isInternalTransfer('Grocery store'), isFalse);
    });

    test(
      'tags matched transactions as Transfers without losing identifiers',
      () {
        final transaction = Transaction(
          date: DateTime(2025, 1, 1),
          amount: 125,
          category: 'Lifestyle / Misc',
          description: 'FID BKG SVC LLC DES:MONEYLINE',
          id: 'transaction-1',
          sheetRow: 8,
        );

        final tagged = tagInternalTransfer(transaction);

        expect(tagged.category, 'Transfers');
        expect(tagged.id, 'transaction-1');
        expect(tagged.sheetRow, 8);
        expect(isTransferTransaction(tagged), isTrue);
      },
    );
  });
}
