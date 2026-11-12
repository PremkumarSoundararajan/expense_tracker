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
  bool get needsReview {
    if (isIgnored || mappings.length < 2) return false;
    final group = mappings.first.group;
    return mappings.any((mapping) => mapping.group != group);
  }

  BaselineGroup? get assignedGroup =>
      !isIgnored && mappings.isNotEmpty && !needsReview
      ? mappings.first.group
      : null;
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

/// One immutable result shared by the organizer, insights and planner.
class FinancialBaselineAnalysis {
  const FinancialBaselineAnalysis({
    required this.matches,
    required this.summary,
  });
  final List<FinancialBaselineMatch> matches;
  final FinancialBaselineSummary summary;
}

class _MerchantRuleNode {
  final children = <String, _MerchantRuleNode>{};
  final rules = <(int, FinancialBaselineMapping)>[];
}

/// Token-prefix index preserves whole-word, contiguous matching and all
/// overlapping rules, without scanning every saved merchant for every expense.
class FinancialBaselineMerchantMatcher {
  FinancialBaselineMerchantMatcher._(
    Iterable<FinancialBaselineMapping> mappings,
    this._key,
  ) {
    var index = 0;
    for (final mapping in mappings) {
      final fingerprint = _key(mapping.merchantFingerprint);
      if (fingerprint.isNotEmpty) {
        var node = _root;
        for (final token in fingerprint.split(' ')) {
          node = node.children.putIfAbsent(token, _MerchantRuleNode.new);
        }
        node.rules.add((index, mapping));
      }
      index++;
    }
  }
  final String Function(String) _key;
  final _root = _MerchantRuleNode();
  final _matches = <String, List<FinancialBaselineMapping>>{};

  List<FinancialBaselineMapping> match(String description) {
    return matchKey(_key(description));
  }

  List<FinancialBaselineMapping> matchKey(String key) {
    final cached = _matches[key];
    if (cached != null) return cached;
    final tokens = key.split(' ');
    final found = <int, FinancialBaselineMapping>{};
    for (var start = 0; start < tokens.length; start++) {
      var node = _root;
      for (var end = start; end < tokens.length; end++) {
        final child = node.children[tokens[end]];
        if (child == null) break;
        node = child;
        for (final rule in node.rules) {
          found[rule.$1] = rule.$2;
        }
      }
    }
    final indices = found.keys.toList()..sort();
    final result = List<FinancialBaselineMapping>.unmodifiable([
      for (final i in indices) found[i]!,
    ]);
    if (_matches.length >= 4096) _matches.remove(_matches.keys.first);
    return _matches[key] = result;
  }
}

class FinancialBaselineService {
  FinancialBaselineService({MerchantNormalizer? normalizer})
    : _normalizer = normalizer ?? const MerchantNormalizer();
  final MerchantNormalizer _normalizer;
  final _merchantKeys = <String, String>{};
  final _ignored = <(String, String), bool>{};
  // Transactions are immutable. Weak identity caching avoids renormalizing a
  // large ledger after each assignment, without retaining replaced ledgers.
  final _preparedTransactions = Expando<(bool, String)>('baseline transaction');

  String merchantKey(String description) {
    final cached = _merchantKeys[description];
    if (cached != null) return cached;
    final key = _normalizer.normalize(description).toLowerCase().trim();
    if (_merchantKeys.length >= 4096) {
      _merchantKeys.remove(_merchantKeys.keys.first);
    }
    return _merchantKeys[description] = key;
  }

  FinancialBaselineMerchantMatcher merchantMatcher(
    Iterable<FinancialBaselineMapping> mappings,
  ) => FinancialBaselineMerchantMatcher._(mappings, merchantKey);

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
    final matcher = merchantMatcher(mappings);
    return transactions
        .map((transaction) {
          var prepared = _preparedTransactions[transaction];
          if (prepared == null) {
            final ignored = _isIgnored(transaction);
            prepared = (
              ignored,
              ignored ? '' : merchantKey(transaction.description),
            );
            _preparedTransactions[transaction] = prepared;
          }
          final ignored = prepared.$1;
          final masterGroup = transaction.baselineGroup;
          final matched = masterGroup != null
              ? masterGroup == 'Unclassified'
                    ? const <FinancialBaselineMapping>[]
                    : [
                        FinancialBaselineMapping(
                          merchantFingerprint: transaction.description,
                          group: BaselineGroup.parse(masterGroup),
                        ),
                      ]
              : ignored
              ? const <FinancialBaselineMapping>[]
              : matcher.matchKey(prepared.$2);
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
  }) => analyze(transactions: transactions, mappings: mappings).summary;

  FinancialBaselineAnalysis analyze({
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
    final summary = FinancialBaselineSummary(
      monthCount: monthCount,
      metrics: Map.unmodifiable(metrics),
      conflictCount: conflictCount,
      conflictAmount: conflictAmount,
      ignoredCount: ignoredCount,
      unclassifiedAmount: unclassifiedAmount,
      trackedSpending: trackedSpending,
    );
    return FinancialBaselineAnalysis(
      matches: List.unmodifiable(matches),
      summary: summary,
    );
  }

  /// Shared by ledger classification and the merchant inventory. Future
  /// entries inherit confirmed merchant rules without persisting transaction
  /// classifications or creating a new mapping for every statement variant.
  bool matchesMerchant(String description, FinancialBaselineMapping mapping) {
    final searchable = merchantKey(description);
    final merchant = merchantKey(mapping.merchantFingerprint);
    if (searchable.isEmpty || merchant.isEmpty) return false;
    return searchable == merchant ||
        searchable.startsWith('$merchant ') ||
        searchable.endsWith(' $merchant') ||
        searchable.contains(' $merchant ');
  }

  bool _isIgnored(Transaction transaction) {
    if (transaction.amount <= 0 || !transaction.amount.isFinite) return true;
    final key = (transaction.category, transaction.description);
    final cached = _ignored[key];
    if (cached != null) return cached;
    final searchable = '${transaction.category} ${transaction.description}'
        .trim()
        .toLowerCase();
    final ignored =
        transaction.category.trim().toUpperCase() == 'TRANSFERS' ||
        isInternalTransfer(transaction.description) ||
        _ignoredPhrases.any(searchable.contains);
    if (_ignored.length >= 4096) _ignored.remove(_ignored.keys.first);
    return _ignored[key] = ignored;
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
  }) : _transactions = List.unmodifiable(transactions),
       _mappings = List.unmodifiable(mappings),
       _service = service ?? FinancialBaselineService();

  List<Transaction> _transactions;
  List<FinancialBaselineMapping> _mappings;
  final FinancialBaselineService _service;

  FinancialBaselineAnalysis? _analysis;
  List<Transaction> get transactions => _transactions;
  List<FinancialBaselineMapping> get mappings => _mappings;
  FinancialBaselineAnalysis get analysis => _analysis ??= _service.analyze(
    transactions: _transactions,
    mappings: _mappings,
  );
  FinancialBaselineSummary get summary => analysis.summary;

  void updateTransactions(Iterable<Transaction> transactions) {
    _transactions = List.unmodifiable(transactions);
    _analysis = null;
    notifyListeners();
  }

  void updateMappings(Iterable<FinancialBaselineMapping> mappings) {
    _mappings = List.unmodifiable(mappings);
    _analysis = null;
    notifyListeners();
  }
}
