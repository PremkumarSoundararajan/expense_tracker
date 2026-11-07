import 'package:flutter_test/flutter_test.dart';
import 'package:pocket_ledger/models/financial_baseline.dart';
import 'package:pocket_ledger/models/transaction.dart';
import 'package:pocket_ledger/services/financial_baseline_insights_service.dart';

Transaction tx(
  DateTime date,
  double amount,
  String description, {
  String category = 'Food',
}) => Transaction(
  date: date,
  amount: amount,
  category: category,
  description: description,
);

void main() {
  final now = DateTime(2026, 11, 15);
  final service = FinancialBaselineInsightsService();
  final mapping = <FinancialBaselineMapping>[
    const FinancialBaselineMapping(
      merchantFingerprint: 'POWER COMPANY',
      group: BaselineGroup.essential,
    ),
    const FinancialBaselineMapping(
      merchantFingerprint: 'GROCERY STORE',
      group: BaselineGroup.potentiallyFlexible,
    ),
  ];

  test(
    'returns six completed calendar months and excludes the current month',
    () {
      final result = service.build(
        now: now,
        mappings: mapping,
        transactions: [
          tx(DateTime(2026, 5, 1), 10, 'POWER COMPANY'),
          tx(DateTime(2026, 6, 1), 20, 'POWER COMPANY'),
          tx(DateTime(2026, 7, 1), 30, 'POWER COMPANY'),
          tx(DateTime(2026, 8, 1), 40, 'POWER COMPANY'),
          tx(DateTime(2026, 9, 1), 50, 'POWER COMPANY'),
          tx(DateTime(2026, 10, 1), 60, 'POWER COMPANY'),
          tx(DateTime(2026, 11, 1), 999, 'POWER COMPANY'),
        ],
      );
      expect(result.months, hasLength(6));
      expect(result.months.first.month, DateTime(2026, 5));
      expect(result.months.last.month, DateTime(2026, 10));
      expect(result.months.map((month) => month.total), [
        10,
        20,
        30,
        40,
        50,
        60,
      ]);
      expect(
        result.months.every((month) => month.total == month.baseline),
        isTrue,
      );
    },
  );

  test('separates baseline, adjustable and unclassified and excludes ineligible rows', () {
    final result = service.build(
      now: now,
      mappings: mapping,
      transactions: [
        tx(DateTime(2026, 5, 2), 100, 'POWER COMPANY'),
        tx(DateTime(2026, 5, 3), 50, 'GROCERY STORE'),
        tx(DateTime(2026, 5, 4), 25, 'LOCAL MARKET'),
        tx(
          DateTime(2026, 5, 5),
          500,
          'CREDIT CARD PAYMENT',
          category: 'Transfers',
        ),
        tx(DateTime(2026, 5, 6), 300, 'STORE REFUND'),
      ],
    );
    final may = result.months.first;
    expect(may.baseline, 100);
    expect(may.adjustable, 50);
    expect(may.unclassified, 25);
    expect(may.total, 175);
  });

  test(
    'applies draft merchant classification consistently across past months',
    () {
      final result = service.build(
        now: now,
        mappings: const [
          FinancialBaselineMapping(
            merchantFingerprint: 'LOCAL MARKET',
            group: BaselineGroup.potentiallyFlexible,
          ),
        ],
        transactions: [
          tx(DateTime(2026, 5, 2), 10, 'LOCAL MARKET'),
          tx(DateTime(2026, 9, 2), 20, 'LOCAL MARKET'),
        ],
      );
      expect(result.months.first.adjustable, 10);
      expect(result.months[4].adjustable, 20);
      expect(result.months.first.unclassified, 0);
    },
  );

  test(
    'compares adjustable spending with the previous three completed months',
    () {
      final result = service.build(
        now: now,
        mappings: mapping,
        transactions: [
          for (var month = 5; month <= 10; month++)
            tx(DateTime(2026, month, 2), month < 8 ? 100 : 50, 'GROCERY STORE'),
        ],
      );
      expect(result.hasSixMonthsOfHistory, isTrue);
      expect(result.observation, contains('decreased 50%'));
      expect(result.isTrendProvisional, isFalse);
    },
  );

  test(
    'reports increasing and stable adjustable spending without judgement',
    () {
      final increased = service.build(
        now: now,
        mappings: mapping,
        transactions: [
          for (var month = 5; month <= 10; month++)
            tx(DateTime(2026, month, 2), month < 8 ? 50 : 100, 'GROCERY STORE'),
        ],
      );
      expect(increased.observation, contains('increased 100%'));

      final stable = service.build(
        now: now,
        mappings: mapping,
        transactions: [
          for (var month = 5; month <= 10; month++)
            tx(
              DateTime(2026, month, 2),
              month < 8 ? 100 : 104,
              'GROCERY STORE',
            ),
        ],
      );
      expect(stable.observation, contains('remained relatively stable'));
    },
  );

  test('handles zero previous averages and no adjustable spending', () {
    final positiveAfterZero = service.build(
      now: now,
      mappings: mapping,
      transactions: [
        tx(DateTime(2026, 5, 2), 100, 'POWER COMPANY'),
        tx(DateTime(2026, 8, 2), 30, 'GROCERY STORE'),
      ],
    );
    expect(positiveAfterZero.observation, contains('increased by'));

    final none = service.build(
      now: now,
      mappings: mapping,
      transactions: [
        for (var month = 5; month <= 10; month++)
          tx(DateTime(2026, month, 2), 30, 'POWER COMPANY'),
      ],
    );
    expect(none.observation, contains('No adjustable spending'));
  });

  test(
    'requires history and marks a comparison provisional below 80% coverage',
    () {
      final shortHistory = service.build(
        now: now,
        mappings: mapping,
        transactions: [tx(DateTime(2026, 9, 2), 100, 'GROCERY STORE')],
      );
      expect(shortHistory.hasSixMonthsOfHistory, isFalse);
      expect(shortHistory.observation, contains('More spending history'));

      final lowCoverage = service.build(
        now: now,
        mappings: mapping,
        transactions: [
          tx(DateTime(2026, 5, 2), 100, 'POWER COMPANY'),
          tx(DateTime(2026, 6, 2), 100, 'POWER COMPANY'),
          tx(DateTime(2026, 7, 2), 100, 'POWER COMPANY'),
          for (var month = 8; month <= 10; month++) ...[
            tx(DateTime(2026, month, 2), 70, 'POWER COMPANY'),
            tx(DateTime(2026, month, 3), 30, 'LOCAL MARKET'),
          ],
        ],
      );
      expect(lowCoverage.previousCoveragePercentage, 100);
      expect(lowCoverage.recentCoveragePercentage, closeTo(70, .01));
      expect(lowCoverage.isTrendProvisional, isTrue);
      expect(lowCoverage.observation, contains('trend is provisional'));

      final previousPeriodLow = service.build(
        now: now,
        mappings: mapping,
        transactions: [
          for (var month = 5; month <= 7; month++) ...[
            tx(DateTime(2026, month, 2), 70, 'POWER COMPANY'),
            tx(DateTime(2026, month, 3), 30, 'LOCAL MARKET'),
          ],
          for (var month = 8; month <= 10; month++)
            tx(DateTime(2026, month, 2), 100, 'POWER COMPANY'),
        ],
      );
      expect(previousPeriodLow.previousCoveragePercentage, closeTo(70, .01));
      expect(previousPeriodLow.recentCoveragePercentage, 100);
      expect(previousPeriodLow.isTrendProvisional, isTrue);
      expect(previousPeriodLow.observation, contains('trend is provisional'));

      final atThreshold = service.build(
        now: now,
        mappings: mapping,
        transactions: [
          tx(DateTime(2026, 5, 2), 100, 'POWER COMPANY'),
          tx(DateTime(2026, 6, 2), 100, 'POWER COMPANY'),
          tx(DateTime(2026, 7, 2), 100, 'POWER COMPANY'),
          for (var month = 8; month <= 10; month++) ...[
            tx(DateTime(2026, month, 2), 80, 'POWER COMPANY'),
            tx(DateTime(2026, month, 3), 20, 'LOCAL MARKET'),
          ],
        ],
      );
      expect(atThreshold.recentCoveragePercentage, 80);
      expect(atThreshold.isTrendProvisional, isFalse);
    },
  );
}
