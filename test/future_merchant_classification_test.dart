import 'package:flutter_test/flutter_test.dart';
import 'package:pocket_ledger/models/financial_baseline.dart';
import 'package:pocket_ledger/models/transaction.dart';
import 'package:pocket_ledger/services/financial_baseline_service.dart';
import 'package:pocket_ledger/services/financial_baseline_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

const mappings = [
  FinancialBaselineMapping(
    merchantFingerprint: 'ATMOS ENERGY',
    group: BaselineGroup.essential,
  ),
  FinancialBaselineMapping(
    merchantFingerprint: 'NETFLIX',
    group: BaselineGroup.potentiallyFlexible,
  ),
];
Transaction expense(String merchant, {double amount = 20}) => Transaction(
  date: DateTime(2026, 12, 5),
  amount: amount,
  description: merchant,
  category: 'Other',
);

void main() {
  final service = FinancialBaselineService();
  test('future manual entries inherit saved groups and brand-new merchants stay unclassified', () {
    final result = service.classify(
      transactions: [
        expense('atmos energy WEB ID 94721'),
        expense('NETFLIX MONTHLY PLAN'),
        expense('NEBULA STUDIO'),
        expense('SPOTIFY'), // A starter suggestion is not a saved assignment.
      ],
      mappings: mappings,
    );
    expect(result.map((m) => m.assignedGroup), [
      BaselineGroup.essential,
      BaselineGroup.potentiallyFlexible,
      null,
      null,
    ]);
  });
  test(
    'committed statement rows use the same saved rules and transaction dates',
    () {
      final imported = [
        [
          '2026-12-01',
          50,
          'Housing / Bills',
          'ATMOS ENERGY PYMT 9123',
          'Regular',
          'import-one',
        ],
        [
          '2027-01-03',
          15,
          'Lifestyle / Misc',
          'NETFLIX WEB ID ABC123',
          'Regular',
          'import-two',
        ],
        ['2027-01-04', 25, 'Other', 'NEBULA STUDIO', 'Regular', 'import-three'],
      ].map(Transaction.tryParseSheetRow).whereType<Transaction>().toList();
      final result = service.classify(
        transactions: imported,
        mappings: mappings,
      );
      expect(result.map((m) => m.assignedGroup), [
        BaselineGroup.essential,
        BaselineGroup.potentiallyFlexible,
        null,
      ]);
      expect(result[1].transaction.date, DateTime(2027, 1, 3));
      expect(
        service
            .summarize(transactions: imported, mappings: mappings)
            .unclassifiedAmount,
        25,
      );
    },
  );
  test(
    'offline cached rules apply immediately without creating mapping records',
    () async {
      SharedPreferences.setMockInitialValues({});
      final store = FinancialBaselineStore(accountKey: 'future-test');
      await store.saveMappings(mappings);
      final prefs = await SharedPreferences.getInstance();
      const key = 'financial_baseline_mappings_v2_future-test';
      final saved = prefs.getString(key);
      final restored = await store.loadMappings();
      final result = service.classify(
        transactions: [
          expense('NETFLIX MONTHLY PLAN'),
          expense('NETFLIX WEB ID 888'),
          expense('NEW SHOP'),
        ],
        mappings: restored,
      );
      expect(result.first.assignedGroup, BaselineGroup.potentiallyFlexible);
      expect(result.last.assignedGroup, isNull);
      expect(await store.loadMappings(), hasLength(2));
      expect(prefs.getString(key), saved);
      expect(await store.loadPendingSync(), isNull);
    },
  );
  test('ledger refresh and reassignment recalculate existing and future transactions', () {
    final provider = FinancialBaselineProvider(mappings: mappings);
    addTearDown(provider.dispose);
    provider.updateTransactions([
      expense('NETFLIX'),
      expense('NETFLIX MONTHLY PLAN'),
    ]);
    expect(provider.summary.potentiallyAdjustableMonthlyAverage, 40);
    provider.updateMappings(const [
      FinancialBaselineMapping(
        merchantFingerprint: 'NETFLIX',
        group: BaselineGroup.essential,
      ),
    ]);
    provider.updateTransactions([
      ...provider.transactions,
      expense('NETFLIX WEB ID 999'),
    ]);
    expect(provider.summary.identifiedBaselineMonthlyAverage, 60);
    expect(provider.summary.potentiallyAdjustableMonthlyAverage, 0);
  });
  test('partial names and conflicting assignments do not silently classify a new merchant', () {
    final result = service.classify(
      transactions: [expense('NETFLIXTON'), expense('NETFLIX CAFE')],
      mappings: [
        ...mappings,
        const FinancialBaselineMapping(
          merchantFingerprint: 'CAFE',
          group: BaselineGroup.essential,
        ),
      ],
    );
    expect(result.first.assignedGroup, isNull);
    expect(result.last.needsReview, isTrue);
    expect(result.last.assignedGroup, isNull);
  });
  test('ignored imported or manual transactions do not enter either group', () {
    final result = service.classify(
      transactions: [
        expense('NETFLIX REFUND'),
        expense('ATMOS ENERGY REVERSAL'),
        expense('NETFLIX', amount: 0),
      ],
      mappings: mappings,
    );
    expect(result.every((m) => m.isIgnored && m.assignedGroup == null), isTrue);
  });
}
