import 'package:flutter_test/flutter_test.dart';
import 'package:pocket_ledger/models/financial_baseline.dart';
import 'package:pocket_ledger/models/transaction.dart';
import 'package:pocket_ledger/services/merchant_discovery_service.dart';
import 'package:pocket_ledger/services/financial_baseline_service.dart';

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

    test('sorts merchants by total spending, not transaction count', () {
      final merchants = service.discover([
        _transaction(DateTime(2025, 1), 100, 'ONE TIME PURCHASE'),
        _transaction(DateTime(2025, 1), 10, 'FREQUENT SHOP'),
        _transaction(DateTime(2025, 2), 10, 'FREQUENT SHOP'),
        _transaction(DateTime(2025, 3), 10, 'FREQUENT SHOP'),
      ]);

      expect(merchants.first.merchantFingerprint, 'ONE TIME');
      expect(merchants.first.totalAmount, 100);
    });

    test('confirmed user mapping takes precedence over starter rules', () {
      final merchants = service.discover([
        _transaction(DateTime(2025, 1), 50, 'ATMOS ENERGY'),
      ]);
      final suggestions = service.suggestClassifications(
        merchants: merchants,
        confirmedMappings: const [
          FinancialBaselineMapping(
            merchantFingerprint: 'ATMOS ENERGY',
            group: BaselineGroup.committed,
          ),
        ],
      );

      expect(suggestions.single.state, MerchantClassificationState.confirmed);
      expect(suggestions.single.group, BaselineGroup.committed);
      expect(suggestions.single.source, MerchantSuggestionSource.userMapping);
    });

    test('matches case-insensitive global entertainment merchant rules', () {
      final merchant = service.discover([
        _transaction(DateTime(2025, 1), 15, 'netflix monthly plan'),
      ]).single;
      final suggestion = service
          .suggestClassifications(
            merchants: [merchant],
            confirmedMappings: const [],
          )
          .single;

      expect(suggestion.state, MerchantClassificationState.suggested);
      expect(suggestion.group, BaselineGroup.discretionary);
      expect(suggestion.confidence, MerchantSuggestionConfidence.high);
      expect(suggestion.source, MerchantSuggestionSource.systemRule);
      expect(suggestion.reason, contains('entertainment subscription'));
    });

    test('recognizes country-neutral mobile provider patterns cautiously', () {
      final merchant = service.discover([
        _transaction(DateTime(2025, 1), 45, 'vodafone recurring plan'),
      ]).single;
      final suggestion = service
          .suggestClassifications(
            merchants: [merchant],
            confirmedMappings: const [],
          )
          .single;

      expect(suggestion.group, BaselineGroup.potentiallyFlexible);
      expect(suggestion.confidence, MerchantSuggestionConfidence.medium);
    });

    test('marks mixed retailers for review without selecting a group', () {
      final merchant = service.discover([
        _transaction(DateTime(2025, 1), 75, 'Amazon Marketplace'),
      ]).single;
      final suggestion = service
          .suggestClassifications(
            merchants: [merchant],
            confirmedMappings: const [],
          )
          .single;

      expect(suggestion.state, MerchantClassificationState.needsReview);
      expect(suggestion.group, isNull);
      expect(suggestion.reason, contains('mix'));
    });

    test('does not infer lifestyle group from payment provider alone', () {
      final merchant = service.discover([
        _transaction(DateTime(2025, 1), 30, 'PayPal payment to a person'),
      ]).single;
      final suggestion = service
          .suggestClassifications(
            merchants: [merchant],
            confirmedMappings: const [],
          )
          .single;

      expect(suggestion.state, MerchantClassificationState.unknown);
      expect(suggestion.group, isNull);
      expect(suggestion.reason, contains('underlying merchant'));
    });

    test(
      'can identify a known underlying merchant in a payment description',
      () {
        final merchant = service.discover([
          _transaction(DateTime(2025, 1), 15, 'PayPal Netflix monthly'),
        ]).single;
        final suggestion = service
            .suggestClassifications(
              merchants: [merchant],
              confirmedMappings: const [],
            )
            .single;

        expect(suggestion.group, BaselineGroup.discretionary);
        expect(suggestion.confidence, MerchantSuggestionConfidence.high);
      },
    );

    test(
      'uses uniform transaction category only for cautious medium suggestions',
      () {
        final merchant = service.discover([
          _transaction(
            DateTime(2025, 1),
            80,
            'LOCAL SERVICE',
            category: 'Fuel',
          ),
          _transaction(
            DateTime(2025, 2),
            60,
            'LOCAL SERVICE',
            category: 'Fuel',
          ),
        ]).single;
        final suggestion = service
            .suggestClassifications(
              merchants: [merchant],
              confirmedMappings: const [],
            )
            .single;

        expect(suggestion.group, BaselineGroup.potentiallyFlexible);
        expect(suggestion.confidence, MerchantSuggestionConfidence.medium);
      },
    );

    test('system suggestions remain provisional in baseline totals', () {
      final transaction = _transaction(DateTime(2025, 1), 100, 'ATMOS ENERGY');
      final suggestion = service
          .suggestClassifications(
            merchants: service.discover([transaction]),
            confirmedMappings: const [],
          )
          .single;
      final summary = FinancialBaselineService().summarize(
        transactions: [transaction],
        mappings: const [],
      );

      expect(suggestion.state, MerchantClassificationState.suggested);
      expect(summary.essential.monthlyAverage, 0);
      expect(summary.unclassifiedAmount, 100);
    });

    test('returns no merchant classifications for empty input', () {
      expect(
        service.suggestClassifications(
          merchants: const [],
          confirmedMappings: const [],
        ),
        isEmpty,
      );
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
