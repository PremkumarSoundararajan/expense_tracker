import 'package:flutter_test/flutter_test.dart';
import 'package:pocket_ledger/models/transaction.dart';
import 'package:pocket_ledger/services/merchant_discovery_service.dart';

void main() {
  group('MerchantDiscoveryService', () {
    final service = MerchantDiscoveryService();

    test('normalizes and aggregates matching merchant descriptions', () {
      final merchants = service.discover([
        _transaction(DateTime(2025, 1), 60, 'ATMOS ENERGY WEB ID 812'),
        _transaction(DateTime(2025, 2), 100, 'ATMOS ENERGY PYMT 9002'),
        _transaction(DateTime(2025, 2), 90, 'COSTCO WHSE #456'),
      ]);

      expect(merchants, hasLength(2));
      expect(merchants.first.merchantFingerprint, 'ATMOS ENERGY');
      expect(merchants.first.occurrenceCount, 2);
      expect(merchants.first.averageAmount, 80);
      expect(merchants.last.merchantFingerprint, 'COSTCO WHSE');
    });

    test('refunds, reversals, transfers and card payments are excluded', () {
      final merchants = service.discover([
        _transaction(DateTime(2025, 1), 20, 'ATMOS ENERGY refund'),
        _transaction(DateTime(2025, 1), 30, 'Charge reversed'),
        _transaction(
          DateTime(2025, 1),
          50,
          'Transfer to savings',
          category: 'Transfer',
        ),
        _transaction(DateTime(2025, 1), 400, 'Credit card payment'),
        _transaction(DateTime(2025, 1), -20, 'ATMOS ENERGY'),
        _transaction(DateTime(2025, 1), 15, 'ATMOS ENERGY'),
      ]);

      expect(merchants, hasLength(1));
      expect(merchants.single.merchantFingerprint, 'ATMOS ENERGY');
      expect(merchants.single.occurrenceCount, 1);
    });
  });
}

Transaction _transaction(
  DateTime date,
  double amount,
  String description, {
  String category = 'Bills',
}) => Transaction(
  date: date,
  amount: amount,
  category: category,
  description: description,
);
