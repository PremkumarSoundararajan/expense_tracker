import 'package:flutter/foundation.dart';

import '../models/financial_baseline.dart';
import '../models/transaction.dart';
import 'merchant_normalizer.dart';
import 'transaction_filter.dart';

class FinancialBaselineMatch {
  const FinancialBaselineMatch({
    required this.transaction,
    required this.mappings,
    required this.isIgnored,
  });

  final Transaction transaction;
  final List<FinancialBaselineMapping> mappings;
  final bool isIgnored;

  Set<BaselineGroup> get groups =>
      mappings.map((mapping) => mapping.group).toSet();
  bool get needsReview => !isIgnored && groups.length > 1;
  BaselineGroup? get assignedGroup =>
      !isIgnored && !needsReview && groups.isNotEmpty ? groups.single : null;
}

class BaselineGroupMetrics {
  const BaselineGroupMetrics({
    required this.monthlyAverage,
    required this.annualizedAmount,
  });

  final double monthlyAverage;
  final double annualizedAmount;
}

enum BaselineInsightReadiness { insufficient, provisional, representative }

BaselineInsightReadiness baselineInsightReadiness(double classifiedPercentage) {
  if (!classifiedPercentage.isFinite || classifiedPercentage < 50) {
    return BaselineInsightReadiness.insufficient;
  }
  if (classifiedPercentage < 80) {
    return BaselineInsightReadiness.provisional;
  }
  return BaselineInsightReadiness.representative;
}

class FinancialBaselineSummary {
  const FinancialBaselineSummary({
    required this.monthCount,
    required this.metrics,
    required this.conflictCount,
    required this.conflictAmount,
    required this.ignoredCount,
    required this.unclassifiedAmount,
    required this.trackedSpending,
  });

  final int monthCount;
  final Map<BaselineGroup, BaselineGroupMetrics> metrics;
  final int conflictCount;
  final double conflictAmount;
  final int ignoredCount;
  final double unclassifiedAmount;
  final double trackedSpending;

  double get unclassifiedMonthlyAverage =>
      monthCount == 0 ? 0 : unclassifiedAmount / monthCount;
  double get unclassifiedAnnualizedAmount => unclassifiedMonthlyAverage * 12;
  double get trackedMonthlyAverage =>
      monthCount == 0 ? 0 : trackedSpending / monthCount;
  double get trackedAnnualizedAmount => trackedMonthlyAverage * 12;
  double get identifiedBaselineMonthlyAverage => essential.monthlyAverage;
  double get potentiallyAdjustableMonthlyAverage =>
      potentiallyFlexible.monthlyAverage;
  double get classifiedAmount => (trackedSpending - unclassifiedAmount)
      .clamp(0, trackedSpending)
      .toDouble();
  double get classifiedPercentage => trackedSpending <= 0
      ? 0
      : (classifiedAmount / trackedSpending * 100).clamp(0, 100).toDouble();
  double get unclassifiedPercentage => trackedSpending <= 0
      ? 0
      : (unclassifiedAmount / trackedSpending * 100).clamp(0, 100).toDouble();
  BaselineGroupMetrics get essential => metrics[BaselineGroup.essential]!;
  BaselineGroupMetrics get potentiallyFlexible =>
      metrics[BaselineGroup.potentiallyFlexible]!;
}

class FinancialBaselineService {
  final MerchantNormalizer _normalizer = const MerchantNormalizer();

  static const _ignoredPhrases = <String>[
    'transfer',
    'credit card payment',
    'credit card pymt',
    'payment to credit card',
    'payment to card',
    'payment for card',
    'card payment',
    'card autopay',
    'cc payment',
    'autopay credit card',
    'payment thank you',
    'payment - thank you',
    'refund',
    'refunded',
    'return',
    'returned',
    'reversal',
    'reversed',
    'chargeback',
  ];

  List<FinancialBaselineMatch> classify({
    required Iterable<Transaction> transactions,
    required Iterable<FinancialBaselineMapping> mappings,
  }) {
    final configuredMappings = mappings.toList(growable: false);
    return transactions
        .map((transaction) {
          final ignored = _isIgnored(transaction);
          final matched = ignored
              ? const <FinancialBaselineMapping>[]
              : configuredMappings
                    .where((mapping) => _matches(transaction, mapping))
                    .toList(growable: false);
          return FinancialBaselineMatch(
            transaction: transaction,
            mappings: matched,
            isIgnored: ignored,
          );
        })
        .toList(growable: false);
  }

  FinancialBaselineSummary summarize({
    required Iterable<Transaction> transactions,
    required Iterable<FinancialBaselineMapping> mappings,
  }) {
    final history = transactions.toList(growable: false);
    final matches = classify(transactions: history, mappings: mappings);
    final totals = {for (final group in BaselineGroup.values) group: 0.0};
    var conflictCount = 0;
    var conflictAmount = 0.0;
    var ignoredCount = 0;
    var unclassifiedAmount = 0.0;
    var trackedSpending = 0.0;
    for (final match in matches) {
      if (match.isIgnored) {
        ignoredCount++;
        continue;
      }
      trackedSpending += match.transaction.amount;
      if (match.needsReview) {
        conflictCount++;
        conflictAmount += match.transaction.amount;
        unclassifiedAmount += match.transaction.amount;
      } else if (match.assignedGroup case final group?) {
        totals[group] = totals[group]! + match.transaction.amount;
      } else {
        unclassifiedAmount += match.transaction.amount;
      }
    }

    final monthCount = _calendarMonthSpan(history);
    final metrics = {
      for (final group in BaselineGroup.values)
        group: BaselineGroupMetrics(
          monthlyAverage: monthCount == 0 ? 0 : totals[group]! / monthCount,
          annualizedAmount: monthCount == 0
              ? 0
              : totals[group]! / monthCount * 12,
        ),
    };
    return FinancialBaselineSummary(
      monthCount: monthCount,
      metrics: metrics,
      conflictCount: conflictCount,
      conflictAmount: conflictAmount,
      ignoredCount: ignoredCount,
      unclassifiedAmount: unclassifiedAmount,
      trackedSpending: trackedSpending,
    );
  }

  bool _matches(Transaction transaction, FinancialBaselineMapping mapping) {
    final searchable = _normalizer
        .normalize(transaction.description)
        .toLowerCase()
        .trim();
    final merchant = _normalizer
        .normalize(mapping.merchantFingerprint)
        .toLowerCase()
        .trim();
    if (searchable.isEmpty || merchant.isEmpty) return false;
    return searchable == merchant ||
        searchable.startsWith('$merchant ') ||
        searchable.endsWith(' $merchant') ||
        searchable.contains(' $merchant ');
  }

  bool _isIgnored(Transaction transaction) {
    if (transaction.amount <= 0 || !transaction.amount.isFinite) return true;
    if (isTransferTransaction(transaction) ||
        isInternalTransfer(transaction.description)) {
      return true;
    }
    final searchable = '${transaction.category} ${transaction.description}'
        .trim()
        .toLowerCase();
    return _ignoredPhrases.any(searchable.contains);
  }

  int _calendarMonthSpan(List<Transaction> transactions) {
    if (transactions.isEmpty) return 0;
    var first = transactions.first.date;
    var last = first;
    for (final transaction in transactions.skip(1)) {
      if (transaction.date.isBefore(first)) first = transaction.date;
      if (transaction.date.isAfter(last)) last = transaction.date;
    }
    return (last.year - first.year) * 12 + last.month - first.month + 1;
  }
}

class FinancialBaselineProvider extends ChangeNotifier {
  FinancialBaselineProvider({
    Iterable<Transaction> transactions = const [],
    Iterable<FinancialBaselineMapping> mappings = const [],
    FinancialBaselineService? service,
  }) : _transactions = List.of(transactions),
       _mappings = List.of(mappings),
       _service = service ?? FinancialBaselineService();

  List<Transaction> _transactions;
  List<FinancialBaselineMapping> _mappings;
  final FinancialBaselineService _service;

  List<Transaction> get transactions => List.unmodifiable(_transactions);
  List<FinancialBaselineMapping> get mappings => List.unmodifiable(_mappings);
  FinancialBaselineSummary get summary =>
      _service.summarize(transactions: _transactions, mappings: _mappings);

  void updateTransactions(Iterable<Transaction> transactions) {
    _transactions = List.of(transactions);
    notifyListeners();
  }

  void updateMappings(Iterable<FinancialBaselineMapping> mappings) {
    _mappings = List.of(mappings);
    notifyListeners();
  }
}
