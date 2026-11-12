import '../models/expense_category.dart';
import '../models/transaction.dart';
import 'favourite_spending_spots_service.dart';
import 'merchant_classification_service.dart';

class SpendingBreakdownItem {
  const SpendingBreakdownItem(this.name, this.amount);
  final String name;
  final double amount;
}

class ClassifiedSpendingDimension {
  ClassifiedSpendingDimension(Map<String, double> totals, this.eligibleTotal)
    : items = List.unmodifiable(
        totals.entries
            .where((e) => e.value != 0)
            .map((e) => SpendingBreakdownItem(e.key, e.value))
            .toList()
          ..sort((a, b) {
            final amount = b.amount.compareTo(a.amount);
            return amount == 0 ? a.name.compareTo(b.name) : amount;
          }),
      );
  final List<SpendingBreakdownItem> items;
  final double eligibleTotal;
  double get classifiedTotal => items.fold(0, (sum, item) => sum + item.amount);
  double get coverage =>
      eligibleTotal <= 0 ? 0 : classifiedTotal / eligibleTotal * 100;
  double percent(SpendingBreakdownItem item) =>
      classifiedTotal <= 0 ? 0 : item.amount / classifiedTotal * 100;
  List<SpendingBreakdownItem> get topCategories => [
    ...items.take(5),
    if (items.length > 5)
      SpendingBreakdownItem(
        'Other',
        items.skip(5).fold(0, (sum, item) => sum + item.amount),
      ),
  ];
}

class ClassifiedSpendingBreakdown {
  const ClassifiedSpendingBreakdown(this.essentiality, this.categories);
  final ClassifiedSpendingDimension essentiality;
  final ClassifiedSpendingDimension categories;
}

/// Consumes the Baseline panel's existing all-history, deduplicated merchant
/// inventory and signed net amounts. No second eligibility/refund algorithm.
class ClassifiedSpendingBreakdownService {
  const ClassifiedSpendingBreakdownService();

  ClassifiedSpendingBreakdown build({
    required List<FavouriteSpendingSpot> groups,
    required MerchantClassificationIndex index,
    required List<ExpenseCategory> categories,
    Map<Transaction, String?> legacyGroups = const {},
  }) {
    final categoryNames = {for (final c in categories) c.id: c.name};
    final essentiality = <String, double>{};
    final categoryTotals = <String, double>{};
    var eligibleTotal = 0.0;
    for (final group in groups) {
      for (final entry in group.transactions) {
        eligibleTotal += entry.netAmount;
        final original = entry.transaction;
        final effective = index.apply(original);
        final merchant = index.merchantFor(original.description);
        final exception = index.exceptions[original.id];
        final excluded = merchant?['na'] == true;
        // An excluded merchant can contribute only explicit valid exceptions,
        // independently for each dimension. Never resurrect stale sheet values.
        final essential = excluded && exception?['group'] == null
            ? null
            : effective.baselineGroup ?? legacyGroups[original];
        if (essential == 'Essential' || essential == 'Potentially Flexible') {
          essentiality[essential!] =
              (essentiality[essential] ?? 0) + entry.netAmount;
        }
        if (excluded &&
            exception?['category'] == null &&
            exception?['categoryId'] == null) {
          continue;
        }
        final categorySource =
            exception?['category'] != null || exception?['categoryId'] != null
            ? exception
            : merchant;
        final explicitLabel = categorySource?['category'] as String?;
        if (explicitLabel != null && !_knownCategory(explicitLabel.trim())) {
          continue;
        }
        final category =
            categoryNames[effective.categoryId] ?? effective.category.trim();
        if (_knownCategory(category)) {
          categoryTotals[category] =
              (categoryTotals[category] ?? 0) + entry.netAmount;
        }
      }
    }
    return ClassifiedSpendingBreakdown(
      ClassifiedSpendingDimension(essentiality, eligibleTotal),
      ClassifiedSpendingDimension(categoryTotals, eligibleTotal),
    );
  }

  bool _knownCategory(String value) => !{
    '',
    'na',
    'n/a',
    'unknown',
    'unclassified',
    'uncategorized',
    'uncategorised',
    'category / mixed',
  }.contains(value.toLowerCase());
}
