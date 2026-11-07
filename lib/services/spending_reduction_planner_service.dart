import '../models/expense_category.dart';
import '../models/financial_baseline.dart';
import '../models/transaction.dart';
import 'financial_baseline_service.dart';
import 'merchant_normalizer.dart';

enum SpendingReductionView { category, merchant }

class ReductionCategoryOption {
  const ReductionCategoryOption({
    required this.id,
    required this.name,
    required this.parentId,
    required this.monthlySpending,
    required this.transactionCount,
    required this.isParent,
    this.isUncategorized = false,
  });

  final String id;
  final String name;
  final String parentId;
  final double monthlySpending;
  final int transactionCount;
  final bool isParent;
  final bool isUncategorized;
}

class ReductionMerchantOption {
  const ReductionMerchantOption({
    required this.key,
    required this.name,
    required this.lifestyleGroup,
    required this.monthlySpending,
    required this.transactionCount,
  });

  final String key;
  final String name;
  final String lifestyleGroup;
  final double monthlySpending;
  final int transactionCount;
}

class ReductionTargetImpact {
  const ReductionTargetImpact({
    required this.key,
    required this.name,
    required this.isMerchant,
    required this.percentage,
    required this.monthlyReduction,
    required this.transactionCount,
  });

  final String key;
  final String name;
  final bool isMerchant;
  final int percentage;
  final double monthlyReduction;
  final int transactionCount;
}

class SpendingReductionPlan {
  const SpendingReductionPlan({
    required this.monthlyReduction,
    required this.impacts,
    required this.targetCount,
  });

  final double monthlyReduction;
  final List<ReductionTargetImpact> impacts;
  final int targetCount;
  double get annualizedPotential => monthlyReduction * 12;
}

class SpendingReductionPlannerAnalysis {
  SpendingReductionPlannerAnalysis._({
    required this.categories,
    required this.merchants,
    required this.hasUncategorizedSpending,
    required this.uncategorizedMonthlySpending,
    required this.uncategorizedTransactionCount,
    required this.monthCount,
    required List<_EligibleReductionTransaction> transactions,
    required Map<String, String> categoryNames,
    required Map<String, String> merchantNames,
  }) {
    _transactions = transactions;
    _categoryNames = categoryNames;
    _merchantNames = merchantNames;
  }

  final List<ReductionCategoryOption> categories;
  final List<ReductionMerchantOption> merchants;
  final bool hasUncategorizedSpending;
  final double uncategorizedMonthlySpending;
  final int uncategorizedTransactionCount;
  final int monthCount;
  late final List<_EligibleReductionTransaction> _transactions;
  late final Map<String, String> _categoryNames;
  late final Map<String, String> _merchantNames;

  SpendingReductionPlan calculate(Map<String, int> targets) {
    final amounts = <String, double>{};
    final counts = <String, int>{};
    for (final transaction in _transactions) {
      String? targetKey;
      if (transaction.merchantKey != null &&
          targets.containsKey('merchant:${transaction.merchantKey}')) {
        targetKey = 'merchant:${transaction.merchantKey}';
      } else {
        for (final categoryId in transaction.categoryPath) {
          final candidate = 'category:$categoryId';
          if (targets.containsKey(candidate)) {
            targetKey = candidate;
            break;
          }
        }
      }
      if (targetKey == null) continue;
      final percentage = targets[targetKey] ?? 0;
      if (percentage <= 0) continue;
      final amount = transaction.amount / monthCount * percentage / 100;
      amounts.update(
        targetKey,
        (value) => value + amount,
        ifAbsent: () => amount,
      );
      counts.update(targetKey, (value) => value + 1, ifAbsent: () => 1);
    }

    final impacts =
        [
          for (final entry in targets.entries)
            ReductionTargetImpact(
              key: entry.key,
              name: entry.key.startsWith('merchant:')
                  ? (_merchantNames[entry.key.substring(9)] ??
                        entry.key.substring(9))
                  : (_categoryNames[entry.key.substring(9)] ??
                        entry.key.substring(9)),
              isMerchant: entry.key.startsWith('merchant:'),
              percentage: entry.value,
              monthlyReduction: amounts[entry.key] ?? 0,
              transactionCount: counts[entry.key] ?? 0,
            ),
        ]..sort((a, b) {
          final typeOrder = a.isMerchant == b.isMerchant
              ? 0
              : (a.isMerchant ? 1 : -1);
          return typeOrder != 0
              ? typeOrder
              : a.name.toLowerCase().compareTo(b.name.toLowerCase());
        });
    final total = impacts.fold<double>(
      0,
      (sum, impact) => sum + impact.monthlyReduction,
    );
    return SpendingReductionPlan(
      monthlyReduction: total,
      impacts: List.unmodifiable(impacts),
      targetCount: targets.length,
    );
  }
}

class _EligibleReductionTransaction {
  const _EligibleReductionTransaction({
    required this.amount,
    required this.categoryPath,
    required this.merchantKey,
  });

  final double amount;
  final List<String> categoryPath;
  final String? merchantKey;
}

class SpendingReductionPlannerService {
  SpendingReductionPlannerService({FinancialBaselineService? baselineService})
    : _baselineService = baselineService ?? FinancialBaselineService();

  final FinancialBaselineService _baselineService;
  final MerchantNormalizer _normalizer = const MerchantNormalizer();

  SpendingReductionPlannerAnalysis analyze({
    required Iterable<Transaction> transactions,
    required Iterable<FinancialBaselineMapping> lifestyleMappings,
    required Iterable<ExpenseCategory> categories,
  }) {
    final ledger = transactions.toList(growable: false);
    final mappings = lifestyleMappings.toList(growable: false);
    final categoryMap = <String, ExpenseCategory>{
      for (final entry in defaultExpenseParents.entries)
        entry.key: ExpenseCategory(
          id: entry.key,
          parentId: entry.key,
          name: entry.value,
        ),
      for (final category in categories) category.id: category,
    };
    final historyMonths = _baselineService
        .summarize(transactions: ledger, mappings: mappings)
        .monthCount;
    final divisor = historyMonths <= 0 ? 1 : historyMonths;
    final matches = _baselineService.classify(
      transactions: ledger,
      mappings: mappings,
    );
    final eligibleRows = <_EligibleReductionTransaction>[];
    final categoryAmounts = <String, double>{};
    final categoryCounts = <String, int>{};
    final merchantAmounts = <String, double>{};
    final merchantCounts = <String, int>{};
    final merchantGroups = <String, Set<BaselineGroup>>{};
    final merchantNames = <String, String>{};
    var uncategorizedAmount = 0.0;
    var uncategorizedCount = 0;

    for (final match in matches) {
      if (match.isIgnored ||
          match.assignedGroup != BaselineGroup.potentiallyFlexible) {
        continue;
      }
      final transaction = match.transaction;
      final categoryId = _resolveCategoryId(transaction, categoryMap);
      final categoryPath = categoryId == null
          ? const <String>[]
          : _categoryPath(categoryId, categoryMap);
      final normalizedMerchant = _normalizer
          .normalize(transaction.description)
          .trim()
          .toLowerCase();
      final merchantKey = normalizedMerchant.isEmpty
          ? null
          : normalizedMerchant;
      eligibleRows.add(
        _EligibleReductionTransaction(
          amount: transaction.amount,
          categoryPath: categoryPath,
          merchantKey: merchantKey,
        ),
      );
      if (categoryId == null) {
        uncategorizedAmount += transaction.amount;
        uncategorizedCount++;
      } else {
        for (final id in categoryPath) {
          categoryAmounts.update(
            id,
            (amount) => amount + transaction.amount,
            ifAbsent: () => transaction.amount,
          );
          categoryCounts.update(id, (count) => count + 1, ifAbsent: () => 1);
        }
      }
      if (merchantKey != null) {
        merchantNames[merchantKey] = _normalizer
            .normalize(transaction.description)
            .trim();
        merchantAmounts.update(
          merchantKey,
          (amount) => amount + transaction.amount,
          ifAbsent: () => transaction.amount,
        );
        merchantCounts.update(
          merchantKey,
          (count) => count + 1,
          ifAbsent: () => 1,
        );
        merchantGroups
            .putIfAbsent(merchantKey, () => <BaselineGroup>{})
            .add(match.assignedGroup!);
      }
    }

    final categoryNames = <String, String>{
      for (final entry in categoryMap.entries) entry.key: entry.value.name,
    };
    final categoryOptions = <ReductionCategoryOption>[];
    for (final category in categoryMap.values) {
      if (!category.active || category.archived) continue;
      final amount = categoryAmounts[category.id] ?? 0;
      if (amount <= 0) continue;
      final isParent = category.id == category.parentId;
      final parentName = defaultExpenseParents[category.parentId];
      categoryOptions.add(
        ReductionCategoryOption(
          id: category.id,
          name: !isParent && parentName != null
              ? '$parentName · ${category.name}'
              : category.name,
          parentId: category.parentId,
          monthlySpending: amount / divisor,
          transactionCount: categoryCounts[category.id] ?? 0,
          isParent: isParent,
        ),
      );
    }
    categoryOptions.sort((a, b) {
      final spend = b.monthlySpending.compareTo(a.monthlySpending);
      return spend != 0 ? spend : a.name.compareTo(b.name);
    });
    final merchants =
        [
          for (final entry in merchantAmounts.entries)
            ReductionMerchantOption(
              key: entry.key,
              name: merchantNames[entry.key] ?? entry.key,
              lifestyleGroup: (merchantGroups[entry.key] ?? {})
                  .map((group) => group.label)
                  .join(' / '),
              monthlySpending: entry.value / divisor,
              transactionCount: merchantCounts[entry.key] ?? 0,
            ),
        ]..sort((a, b) {
          final spend = b.monthlySpending.compareTo(a.monthlySpending);
          return spend != 0 ? spend : a.name.compareTo(b.name);
        });
    categoryNames['__uncategorized__'] = 'Uncategorised / Other';
    return SpendingReductionPlannerAnalysis._(
      categories: List.unmodifiable(categoryOptions),
      merchants: List.unmodifiable(merchants),
      hasUncategorizedSpending: uncategorizedCount > 0,
      uncategorizedMonthlySpending: uncategorizedAmount / divisor,
      uncategorizedTransactionCount: uncategorizedCount,
      monthCount: historyMonths,
      transactions: List.unmodifiable(eligibleRows),
      categoryNames: categoryNames,
      merchantNames: merchantNames,
    );
  }

  String? _resolveCategoryId(
    Transaction transaction,
    Map<String, ExpenseCategory> categories,
  ) {
    final id = transaction.categoryId?.trim();
    if (id != null && id.isNotEmpty) {
      return categories.containsKey(id) ? id : null;
    }
    final name = transaction.category.trim().toLowerCase();
    if (const {
      '',
      'other',
      'uncategorized',
      'uncategorised',
      'unknown',
      'n/a',
      'miscellaneous',
    }.contains(name)) {
      return null;
    }
    return categories.values
        .where((category) => category.name.trim().toLowerCase() == name)
        .firstOrNull
        ?.id;
  }

  List<String> _categoryPath(
    String categoryId,
    Map<String, ExpenseCategory> categories,
  ) {
    final path = <String>[];
    var current = categories[categoryId];
    final visited = <String>{};
    while (current != null && visited.add(current.id)) {
      path.add(current.id);
      if (current.parentId == current.id) break;
      current = categories[current.parentId];
    }
    return path;
  }
}
