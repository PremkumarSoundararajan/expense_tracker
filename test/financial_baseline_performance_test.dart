import 'package:flutter_test/flutter_test.dart';
import 'package:pocket_ledger/models/financial_baseline.dart';
import 'package:pocket_ledger/models/transaction.dart';
import 'package:pocket_ledger/services/financial_baseline_service.dart';
import 'package:pocket_ledger/services/financial_baseline_insights_service.dart';
import 'package:pocket_ledger/services/spending_reduction_planner_service.dart';
import 'package:pocket_ledger/services/merchant_normalizer.dart';

class CountingNormalizer extends MerchantNormalizer {
  int calls = 0;
  @override
  String normalize(String value) {
    calls++;
    return super.normalize(value);
  }
}

class CountingBaseline extends FinancialBaselineService {
  int classifications = 0;
  @override
  List<FinancialBaselineMatch> classify({
    required Iterable<Transaction> transactions,
    required Iterable<FinancialBaselineMapping> mappings,
  }) {
    classifications++;
    return super.classify(transactions: transactions, mappings: mappings);
  }
}

const essential = FinancialBaselineMapping(
  merchantFingerprint: 'MARKET ALPHA',
  group: BaselineGroup.essential,
);
const flexible = FinancialBaselineMapping(
  merchantFingerprint: 'MARKET ALPHA',
  group: BaselineGroup.potentiallyFlexible,
);
Transaction tx(int i) => Transaction(
  date: DateTime(2026, 5 + i % 6, 5),
  amount: 20,
  category: 'Food / Household',
  description: 'MARKET ALPHA WEB ID ${10000 + i}',
);

void main() {
  test('indexed matching preserves word boundaries, overlapping rules, duplicates and original order', () {
    final service = FinancialBaselineService();
    final mappings = [
      essential,
      flexible,
      const FinancialBaselineMapping(
        merchantFingerprint: 'ALPHA CAFE',
        group: BaselineGroup.essential,
      ),
      const FinancialBaselineMapping(
        merchantFingerprint: 'CAFE',
        group: BaselineGroup.potentiallyFlexible,
      ),
      const FinancialBaselineMapping(
        merchantFingerprint: '',
        group: BaselineGroup.essential,
      ),
    ];
    final matcher = service.merchantMatcher(mappings);
    for (final description in [
      'MARKET ALPHA',
      'MARKET ALPHA CAFE',
      'A MARKET ALPHA CAFE Z',
      'MARKET ALPHABET',
      'CAFE CAFE',
      'MARKET ALPHA WEB ID 938',
      '',
      'NEW STORE',
    ]) {
      final reference = mappings
          .where((m) => service.matchesMerchant(description, m))
          .toList();
      expect(matcher.match(description), reference, reason: description);
    }
  });
  test('provider reuses an immutable snapshot and invalidates it on both kinds of edits', () {
    final service = CountingBaseline();
    final provider = FinancialBaselineProvider(
      transactions: [tx(0)],
      mappings: [essential],
      service: service,
    );
    addTearDown(provider.dispose);
    final first = provider.analysis;
    expect(identical(provider.analysis, first), isTrue);
    expect(identical(provider.summary, first.summary), isTrue);
    expect(service.classifications, 1);
    expect(() => provider.transactions.clear(), throwsUnsupportedError);
    expect(() => provider.mappings.clear(), throwsUnsupportedError);
    expect(() => first.matches.clear(), throwsUnsupportedError);
    expect(() => first.summary.metrics.clear(), throwsUnsupportedError);
    provider.updateMappings([flexible]);
    expect(provider.summary.potentiallyAdjustableMonthlyAverage, 20);
    expect(first.summary.identifiedBaselineMonthlyAverage, 20);
    expect(service.classifications, 2);
    provider.updateTransactions([tx(0), tx(1)]);
    expect(
      provider.summary.potentiallyAdjustableMonthlyAverage,
      20,
    ); // two calendar months
    expect(service.classifications, 3);
  });
  test('assignment changes do not renormalize a ledger larger than the bounded string cache', () {
    final normalizer = CountingNormalizer();
    final provider = FinancialBaselineProvider(
      transactions: [for (var i = 0; i < 5000; i++) tx(i)],
      mappings: [essential],
      service: FinancialBaselineService(normalizer: normalizer),
    );
    addTearDown(provider.dispose);
    final first = provider.summary;
    final calls = normalizer.calls;
    provider.updateMappings([flexible]);
    expect(
      provider.summary.potentiallyAdjustableMonthlyAverage,
      first.identifiedBaselineMonthlyAverage,
    );
    expect(normalizer.calls - calls, lessThanOrEqualTo(1));
  });
  test('insights and reduction planner share classification instead of scanning the ledger again', () {
    final service = CountingBaseline();
    final ledger = [for (var i = 0; i < 600; i++) tx(i)];
    final baseline = service.analyze(
      transactions: ledger,
      mappings: [flexible],
    );
    final insights = FinancialBaselineInsightsService(baselineService: service);
    final planner = SpendingReductionPlannerService(baselineService: service);
    final sharedTrend = insights.build(
      transactions: ledger,
      mappings: [flexible],
      now: DateTime(2026, 11),
      classifiedTransactions: baseline.matches,
    );
    final sharedPlan = planner.analyze(
      transactions: ledger,
      lifestyleMappings: [flexible],
      categories: [],
      baselineAnalysis: baseline,
    );
    expect(service.classifications, 1);
    final standaloneTrend = insights.build(
      transactions: ledger,
      mappings: [flexible],
      now: DateTime(2026, 11),
    );
    final standalonePlan = planner.analyze(
      transactions: ledger,
      lifestyleMappings: [flexible],
      categories: [],
    );
    expect(service.classifications, 3);
    expect(
      sharedTrend.months.map((m) => m.adjustable),
      standaloneTrend.months.map((m) => m.adjustable),
    );
    expect(
      sharedPlan.calculate({'merchant:market alpha': 25}).monthlyReduction,
      standalonePlan.calculate({'merchant:market alpha': 25}).monthlyReduction,
    );
  });
}
