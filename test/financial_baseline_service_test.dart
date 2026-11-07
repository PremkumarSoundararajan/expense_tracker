import 'package:flutter_test/flutter_test.dart';
import 'package:pocket_ledger/models/financial_baseline.dart';
import 'package:pocket_ledger/models/transaction.dart';
import 'package:pocket_ledger/services/financial_baseline_service.dart';
import 'package:pocket_ledger/services/financial_baseline_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

FinancialBaselineMapping _mapping(String merchant, BaselineGroup group) =>
    FinancialBaselineMapping(merchantFingerprint: merchant, group: group);

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

void main() {
  group('FinancialBaselineService', () {
    final service = FinancialBaselineService();

    test('insight readiness uses 50 and 80 percent UX thresholds', () {
      expect(
        baselineInsightReadiness(0),
        BaselineInsightReadiness.insufficient,
      );
      expect(
        baselineInsightReadiness(49),
        BaselineInsightReadiness.insufficient,
      );
      expect(
        baselineInsightReadiness(50),
        BaselineInsightReadiness.provisional,
      );
      expect(
        baselineInsightReadiness(79),
        BaselineInsightReadiness.provisional,
      );
      expect(
        baselineInsightReadiness(80),
        BaselineInsightReadiness.representative,
      );
      expect(
        baselineInsightReadiness(100),
        BaselineInsightReadiness.representative,
      );
    });

    test('maps normalized merchant descriptions directly to a group', () {
      final matches = service.classify(
        transactions: [
          _transaction(DateTime(2025, 1), 80, ' ATMOS ENERGY WEB ID 900 '),
          _transaction(DateTime(2025, 1), 40, 'OTHER UTILITY'),
        ],
        mappings: [_mapping('ATMOS ENERGY', BaselineGroup.essential)],
      );

      expect(matches.first.assignedGroup, BaselineGroup.essential);
      expect(matches.last.assignedGroup, isNull);
    });

    test('overlapping group assignments are flagged, not double counted', () {
      final transactions = [
        _transaction(DateTime(2025, 1), 40, 'ONCOR'),
        _transaction(DateTime(2025, 1), 80, 'ONCOR WATER BUNDLE'),
      ];
      final mappings = [
        _mapping('ONCOR', BaselineGroup.essential),
        _mapping('WATER', BaselineGroup.potentiallyFlexible),
      ];

      final matches = service.classify(
        transactions: transactions,
        mappings: mappings,
      );
      final summary = service.summarize(
        transactions: transactions,
        mappings: mappings,
      );

      expect(matches.first.assignedGroup, BaselineGroup.essential);
      expect(matches.last.needsReview, isTrue);
      expect(summary.conflictCount, 1);
      expect(summary.conflictAmount, 80);
      expect(summary.essential.monthlyAverage, 40);
      expect(summary.potentiallyFlexible.monthlyAverage, 0);
    });

    test('ignores refunds, reversals, transfers and card payments', () {
      final transactions = [
        _transaction(DateTime(2025, 1), 20, 'Store refund'),
        _transaction(DateTime(2025, 1), 30, 'Charge reversed'),
        _transaction(DateTime(2025, 1), 50, 'Transfer to savings'),
        _transaction(DateTime(2025, 1), 400, 'Credit card payment'),
        _transaction(DateTime(2025, 1), -20, 'Store purchase'),
        _transaction(DateTime(2025, 1), 15, 'Local market purchase'),
      ];
      final matches = service.classify(
        transactions: transactions,
        mappings: [_mapping('LOCAL MARKET', BaselineGroup.essential)],
      );
      final summary = service.summarize(
        transactions: transactions,
        mappings: [_mapping('LOCAL MARKET', BaselineGroup.essential)],
      );

      expect(matches.take(5).every((match) => match.isIgnored), isTrue);
      expect(matches.last.assignedGroup, BaselineGroup.essential);
      expect(summary.ignoredCount, 5);
      expect(summary.essential.monthlyAverage, 15);
    });

    test('excludes institution-coded transfers from all baseline totals', () {
      final summary = service.summarize(
        transactions: [
          _transaction(DateTime(2025, 1), 300, 'FID BKG SVC LLC DES:MONEYLINE'),
          _transaction(DateTime(2025, 1), 50, 'LOCAL MARKET'),
        ],
        mappings: [
          _mapping('FID BKG SVC', BaselineGroup.essential),
          _mapping('LOCAL MARKET', BaselineGroup.potentiallyFlexible),
        ],
      );

      expect(summary.ignoredCount, 1);
      expect(summary.trackedSpending, 50);
      expect(summary.essential.monthlyAverage, 0);
      expect(summary.potentiallyFlexible.monthlyAverage, 50);
    });

    test(
      'normalizes historical monthly spend and leaves unassigned visible',
      () {
        final summary = service.summarize(
          transactions: [
            _transaction(DateTime(2025, 1, 3), 120, 'Rent'),
            _transaction(DateTime(2025, 3, 3), 60, 'Rent'),
            _transaction(DateTime(2025, 2, 4), 35, 'Unknown'),
          ],
          mappings: [_mapping('RENT', BaselineGroup.essential)],
        );

        expect(summary.monthCount, 3);
        expect(summary.essential.monthlyAverage, 60);
        expect(summary.essential.annualizedAmount, 720);
        expect(summary.unclassifiedAmount, 35);
        expect(summary.trackedSpending, 215);
      },
    );

    test(
      'potentially flexible remains separate from other assigned groups',
      () {
        final summary = service.summarize(
          transactions: [
            _transaction(DateTime(2025, 2), 300, 'Rent'),
            _transaction(DateTime(2025, 2), 50, 'Gym'),
            _transaction(DateTime(2025, 2), 25, 'Coffee'),
            _transaction(DateTime(2025, 2), 75, 'Travel'),
          ],
          mappings: [
            _mapping('RENT', BaselineGroup.essential),
            _mapping('GYM', BaselineGroup.essential),
            _mapping('COFFEE', BaselineGroup.potentiallyFlexible),
            _mapping('TRAVEL', BaselineGroup.potentiallyFlexible),
            _mapping('RENT', BaselineGroup.essential),
          ],
        );
        expect(summary.potentiallyFlexible.monthlyAverage, 100);
        expect(summary.potentiallyAdjustableMonthlyAverage, 100);
        expect(summary.identifiedBaselineMonthlyAverage, 350);
        expect(summary.potentiallyFlexible.annualizedAmount, 1200);
      },
    );

    test(
      'calculates classified spending progress by amount and reconciles',
      () {
        final summary = service.summarize(
          transactions: [
            _transaction(DateTime(2025, 1), 90, 'RENT'),
            _transaction(DateTime(2025, 1), 10, 'UNKNOWN'),
          ],
          mappings: [_mapping('RENT', BaselineGroup.essential)],
        );

        expect(summary.trackedSpending, 100);
        expect(summary.unclassifiedAmount, 10);
        expect(summary.unclassifiedPercentage, 10);
        expect(summary.classifiedPercentage, 90);
        expect(summary.classifiedAmount + summary.unclassifiedAmount, 100);
      },
    );

    test('counts ambiguous matches as unclassified so totals reconcile', () {
      final summary = service.summarize(
        transactions: [_transaction(DateTime(2025, 1), 50, 'ONCOR WATER BILL')],
        mappings: [
          _mapping('ONCOR', BaselineGroup.essential),
          _mapping('WATER', BaselineGroup.potentiallyFlexible),
        ],
      );

      expect(summary.conflictAmount, 50);
      expect(summary.unclassifiedAmount, 50);
      expect(summary.classifiedPercentage, 0);
      expect(summary.trackedSpending, 50);
    });

    test('empty data has safe zero percentages and amounts', () {
      final summary = service.summarize(
        transactions: const [],
        mappings: const [],
      );
      expect(summary.classifiedPercentage, 0);
      expect(summary.unclassifiedPercentage, 0);
      expect(summary.trackedSpending, 0);
      expect(summary.monthCount, 0);
    });

    test('classification leaves transaction frequency types unchanged', () {
      final transactions = [
        Transaction(
          date: DateTime(2025, 1),
          amount: 25,
          category: 'Food',
          description: 'COFFEE SHOP',
          expenseType: ExpenseType.plannedOccasional,
        ),
        Transaction(
          date: DateTime(2025, 2),
          amount: 40,
          category: 'Health',
          description: 'PHARMACY',
          expenseType: ExpenseType.unexpectedOccasional,
        ),
      ];

      service.classify(
        transactions: transactions,
        mappings: [_mapping('COFFEE SHOP', BaselineGroup.potentiallyFlexible)],
      );

      expect(transactions[0].expenseType, ExpenseType.plannedOccasional);
      expect(transactions[1].expenseType, ExpenseType.unexpectedOccasional);
    });
  });

  group('FinancialBaselineProvider', () {
    test('mapping updates retain complete transaction history', () {
      final history = [
        _transaction(DateTime(2023, 1), 100, 'Old bill'),
        _transaction(DateTime(2025, 1), 200, 'Recent bill'),
      ];
      final provider = FinancialBaselineProvider(
        transactions: history,
        mappings: [_mapping('OLD BILL', BaselineGroup.essential)],
      );

      provider.updateMappings([
        _mapping('RECENT BILL', BaselineGroup.essential),
      ]);

      expect(provider.transactions, hasLength(2));
      expect(provider.transactions.first.date, DateTime(2023, 1));
      expect(provider.summary.monthCount, 25);
      provider.dispose();
    });
  });

  group('FinancialBaselineStore', () {
    const accountOneKey = 'financial_baseline_mappings_v2_person@email.com';
    const legacyKey = 'financial_baseline_rules_v1_person@email.com';

    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('round-trips direct merchant group mappings by account', () async {
      final firstStore = FinancialBaselineStore(accountKey: 'Person@Email.com');
      final secondStore = FinancialBaselineStore(accountKey: 'other@email.com');
      final mappings = [
        _mapping('ONCOR', BaselineGroup.essential),
        _mapping('NETFLIX', BaselineGroup.essential),
      ];

      await firstStore.saveMappings(mappings);

      expect(await firstStore.loadMappings(), mappings);
      expect(await secondStore.loadMappings(), isEmpty);
      final preferences = await SharedPreferences.getInstance();
      expect(preferences.getString(accountOneKey), isNotNull);
    });

    test('recovers an unfinished draft and queued sync batch', () async {
      final store = FinancialBaselineStore(accountKey: 'Person@Email.com');
      final committed = _mapping('RENT', BaselineGroup.essential);
      final draft = _mapping('RENT', BaselineGroup.essential);
      await store.saveDraft(
        FinancialBaselineDraft(
          baseMappings: [committed],
          draftMappings: [draft],
        ),
      );
      await store.savePendingSync(
        FinancialBaselineSyncBatch(
          upserts: [draft],
          removals: const ['OLD MERCHANT'],
        ),
      );

      final recovered = await store.loadDraft();
      final pending = await store.loadPendingSync();
      expect(recovered?.baseMappings, [committed]);
      expect(recovered?.draftMappings, [draft]);
      expect(pending?.upserts, [draft]);
      expect(pending?.removals, ['OLD MERCHANT']);
      await store.clearDraft();
      expect(await store.loadDraft(), isNull);
    });

    test(
      'migrates legacy expense type keyword rows into direct mappings',
      () async {
        SharedPreferences.setMockInitialValues({
          legacyKey:
              '[{"id":"utilities","name":"Utilities","group":"Essential","keywords":["ONCOR","ATMOS ENERGY"]},'
              '{"id":"streaming","name":"Streaming","group":"Committed","keywords":["NETFLIX"]},'
              '{"id":"empty","name":"Unused type","group":"Discretionary","keywords":[]}]',
        });
        final store = FinancialBaselineStore(accountKey: 'Person@Email.com');

        final mappings = await store.loadMappings();

        expect(mappings, [
          _mapping('ONCOR', BaselineGroup.essential),
          _mapping('ATMOS ENERGY', BaselineGroup.essential),
          _mapping('NETFLIX', BaselineGroup.essential),
        ]);
        final preferences = await SharedPreferences.getInstance();
        expect(preferences.getString(accountOneKey), isNotNull);
      },
    );
  });
}
